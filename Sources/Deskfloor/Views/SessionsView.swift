import SwiftUI
import AppKit

/// Browse every Claude Code transcript on disk (`~/.claude/projects/`),
/// across every project, sorted recent-first. Click to revive.
///
/// Why this exists: the dashboard's "Claude sessions" stat reads from the
/// remote fleet (AgentSlack), which is offline most of the time and never
/// reflects local history. SessionRegistry already indexes the local truth;
/// this view surfaces it.
struct SessionsView: View {
    @Environment(\.colorScheme) private var scheme
    let store: ProjectStore
    let registry: SessionRegistry

    @State private var query: String = ""
    @State private var scopeProjectDir: String? = nil          // optional facet filter
    @State private var hoveredID: String? = nil
    @State private var refreshTick: Int = 0                    // bump to force list re-evaluation

    private struct Row: Identifiable {
        let session: SessionRegistry.Session
        let project: Project?
        var id: String { session.uuid }
    }

    private var allRows: [Row] {
        _ = refreshTick
        let projectByCwd: [String: Project] = Dictionary(
            uniqueKeysWithValues: store.projects.compactMap { p in
                guard let path = p.localPath else { return nil }
                return (path, p)
            }
        )
        var rows: [Row] = []
        for (_, sessions) in registry.byDirName {
            for s in sessions {
                rows.append(Row(session: s, project: projectByCwd[s.cwd]))
            }
        }
        return rows.sorted { $0.session.lastModified > $1.session.lastModified }
    }

    private var filteredRows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return allRows.filter { row in
            if let scope = scopeProjectDir, row.session.projectDirName != scope { return false }
            guard !q.isEmpty else { return true }
            if row.session.uuid.lowercased().contains(q) { return true }
            if row.session.cwd.lowercased().contains(q) { return true }
            if (row.session.summary ?? "").lowercased().contains(q) { return true }
            if (row.session.gitBranch ?? "").lowercased().contains(q) { return true }
            if let p = row.project, p.name.lowercased().contains(q) { return true }
            return false
        }
    }

    private var totalBytes: Int64 {
        registry.byDirName.values.flatMap { $0 }.map { $0.byteSize }.reduce(0, +)
    }

    private var topDirs: [(dir: String, count: Int, cwd: String)] {
        registry.byDirName
            .map { (dir: $0.key, count: $0.value.count, cwd: $0.value.first?.cwd ?? $0.key) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                facetRail
                Divider().opacity(0.3)
                rowList
            }
            Divider().opacity(0.4)
            footer
        }
        .background(Df.canvas(scheme))
        .onAppear { registry.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Df.space3) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(Df.textTertiary(scheme))
            TextField("Filter by summary, cwd, branch, project, uuid…", text: $query)
                .textFieldStyle(.plain)
                .font(Df.bodyFont)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Df.textQuaternary(scheme))
                }
                .buttonStyle(.plain)
            }
            Button {
                registry.refresh()
                refreshTick &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Df.textSecondary(scheme))
            .help("Re-scan ~/.claude/projects/")
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space3)
        .background(Df.surface(scheme))
    }

    // MARK: - Facet rail

    private var facetRail: some View {
        VStack(alignment: .leading, spacing: Df.space1) {
            Text("PROJECTS")
                .font(Df.microFont)
                .foregroundStyle(Df.textQuaternary(scheme))
                .padding(.horizontal, Df.space3)
                .padding(.top, Df.space3)
            facetButton(
                label: "All",
                count: registry.byDirName.values.map(\.count).reduce(0, +),
                active: scopeProjectDir == nil,
                action: { scopeProjectDir = nil }
            )
            ForEach(topDirs.prefix(20), id: \.dir) { entry in
                facetButton(
                    label: shortPath(entry.cwd),
                    count: entry.count,
                    active: scopeProjectDir == entry.dir,
                    action: { scopeProjectDir = entry.dir }
                )
            }
            Spacer()
        }
        .frame(width: 220)
        .background(Df.surface(scheme).opacity(0.4))
    }

    private func facetButton(label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(Df.monoSmallFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(count)")
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }
            .padding(.horizontal, Df.space3)
            .padding(.vertical, 4)
            .foregroundStyle(active ? Df.textPrimary(scheme) : Df.textSecondary(scheme))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(active ? Df.elevated(scheme) : .clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Df.space2)
    }

    // MARK: - Row list

    private var rowList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredRows) { row in
                    rowView(row)
                        .contextMenu { rowMenu(row) }
                        .onTapGesture {
                            DeskfloorApp.openClaudeForProject(
                                row.project ?? syntheticProject(for: row),
                                registry: registry,
                                mode: .resumeSpecific(uuid: row.session.uuid)
                            )
                        }
                        .onHover { hovered in
                            hoveredID = hovered ? row.id : nil
                        }
                }
                if filteredRows.isEmpty {
                    Text(allRows.isEmpty ? "No sessions on disk yet." : "No sessions match the filter.")
                        .font(Df.captionFont)
                        .foregroundStyle(Df.textTertiary(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.vertical, Df.space2)
        }
    }

    private func rowView(_ row: Row) -> some View {
        let s = row.session
        let isHover = hoveredID == row.id
        return HStack(alignment: .top, spacing: Df.space3) {
            VStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Df.agent.opacity(0.8))
                    .frame(width: 22, height: 22)
                Text(relativeAge(s.lastModified))
                    .font(Df.microFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let p = row.project {
                        Text(p.name)
                            .font(Df.headlineFont)
                            .foregroundStyle(Df.textPrimary(scheme))
                    } else {
                        Text(shortPath(s.cwd))
                            .font(Df.headlineFont)
                            .foregroundStyle(Df.textPrimary(scheme))
                    }
                    if let branch = s.gitBranch {
                        Text(branch)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Df.inset(scheme).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    Text(humanBytes(s.byteSize))
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textTertiary(scheme))
                    Text(s.uuid.prefix(8))
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textQuaternary(scheme))
                }

                Text(s.summary ?? "—")
                    .font(Df.captionFont)
                    .foregroundStyle(Df.textSecondary(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(s.cwd)
                    .font(Df.microFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space2)
        .background(
            RoundedRectangle(cornerRadius: Df.radiusSmall)
                .fill(isHover ? Df.elevated(scheme).opacity(0.4) : .clear)
        )
        .padding(.horizontal, Df.space3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowMenu(_ row: Row) -> some View {
        Button("Resume in Terminal") {
            DeskfloorApp.openClaudeForProject(
                row.project ?? syntheticProject(for: row),
                registry: registry,
                mode: .resumeSpecific(uuid: row.session.uuid)
            )
        }
        Button("Fresh Claude session in this cwd") {
            DeskfloorApp.openClaudeForProject(
                row.project ?? syntheticProject(for: row),
                registry: registry,
                mode: .fresh
            )
        }
        Divider()
        Button("Copy UUID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.session.uuid, forType: .string)
        }
        Button("Copy cwd") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.session.cwd, forType: .string)
        }
        Button("Reveal .jsonl in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([row.session.path])
        }
    }

    /// When a session's cwd doesn't match any project in the store, build a
    /// thin shim Project so the existing openClaudeForProject machinery still works.
    private func syntheticProject(for row: Row) -> Project {
        var p = Project.blank()
        p.name = (row.session.cwd as NSString).lastPathComponent
        p.localPath = row.session.cwd
        return p
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Df.space4) {
            Text("\(registry.byDirName.count) project dirs")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textTertiary(scheme))
            Text("·")
                .foregroundStyle(Df.textQuaternary(scheme))
            Text("\(registry.byDirName.values.map(\.count).reduce(0, +)) sessions")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textTertiary(scheme))
            Text("·")
                .foregroundStyle(Df.textQuaternary(scheme))
            Text(humanBytes(totalBytes))
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textTertiary(scheme))
            Spacer()
            Text("indexed \(registry.lastRefresh, style: .relative) ago")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textQuaternary(scheme))
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, 6)
        .background(Df.surface(scheme).opacity(0.6))
    }

    // MARK: - Helpers

    private func shortPath(_ path: String) -> String {
        let home = NSString(string: "~").expandingTildeInPath
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private func relativeAge(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        case ..<604800: return "\(Int(s / 86400))d"
        default: return "\(Int(s / 604800))w"
        }
    }

    private func humanBytes(_ b: Int64) -> String {
        let kb = Double(b) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(b) B"
    }
}
