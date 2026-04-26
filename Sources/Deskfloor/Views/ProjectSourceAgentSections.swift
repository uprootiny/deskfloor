import SwiftUI

struct ProjectSourceSection: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var expandedSections: Binding<Set<String>>

    private var hasSource: Bool { project.localPath != nil }
    private var hasRepo: Bool { project.repo != nil }

    var body: some View {
        ProjectActionSection(title: "SOURCE", icon: "doc.text", key: "source", expandedSections: expandedSections, project: $project) {
            HStack(spacing: Df.space2) {
                if let path = project.localPath {
                    ProjectActionBtn("folder", "Open", .primary) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } else {
                    ProjectDisabledAction("folder", "Open", hint: "needs local path")
                }

                if let repo = project.repo {
                    ProjectActionBtn("link", "GitHub", .secondary) {
                        if let url = URL(string: "https://github.com/\(repo)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    ProjectDisabledAction("link", "GitHub", hint: "set repo")
                }

                if let repo = project.repo {
                    ProjectActionBtn("arrow.down.circle", "Clone", .secondary) {
                        TerminalLauncher.run("gh repo clone \(Sh.q(repo))", in: NSString(string: "~/Nissan").expandingTildeInPath)
                    }
                }

                Spacer()
            }
        }
    }
}

struct ProjectAgentSection: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var expandedSections: Binding<Set<String>>
    var skein: SkeinStore?
    var sessionRegistry: SessionRegistry?
    @State private var showAllSessions = false

    private var hasSource: Bool { project.localPath != nil }
    private var hasRepo: Bool { project.repo != nil }

    /// Real Claude transcripts for this project (from ~/.claude/projects/),
    /// oldest excluded — substantial sessions only when the count is high.
    private var claudeSessions: [SessionRegistry.Session] {
        sessionRegistry?.sessions(for: project) ?? []
    }

    private var agentThreads: [Thread] {
        guard let skein else { return [] }
        return skein.threadsForProject(project.id)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ProjectActionSection(title: "AGENT", icon: "brain", key: "agent", expandedSections: expandedSections, project: $project) {
            VStack(alignment: .leading, spacing: Df.space2) {
                actionRow
                sessionList
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: Df.space2) {
            if let path = project.localPath {
                ProjectActionBtn("plus.circle", "Fresh", .primary) {
                    TerminalLauncher.run("claude", in: path)
                }
            } else if let repo = project.repo {
                ProjectActionBtn("plus.circle", "Fresh", .primary) {
                    let nissan = NSString(string: "~/Nissan").expandingTildeInPath
                    let cmd = "gh repo clone \(Sh.q(repo)) 2>/dev/null; cd \(Sh.q(project.name)) && claude"
                    TerminalLauncher.run(cmd, in: nissan)
                }
            } else {
                ProjectDisabledAction("plus.circle", "Fresh", hint: "needs source")
            }

            if let recent = claudeSessions.first, let path = project.localPath {
                ProjectActionBtn("arrow.counterclockwise", "Resume latest", .accent) {
                    TerminalLauncher.run("claude --resume \(recent.uuid)", in: path)
                }
            } else if hasSource {
                ProjectDisabledAction("arrow.counterclockwise", "Resume", hint: "no claude sessions yet")
            } else {
                ProjectDisabledAction("arrow.counterclockwise", "Resume", hint: "needs source")
            }

            let count = claudeSessions.count
            if count > 0 {
                ProjectActionBtn("clock.arrow.circlepath", "History (\(count))", .secondary) {
                    showAllSessions.toggle()
                }
            } else {
                ProjectDisabledAction("clock.arrow.circlepath", "History", hint: "none yet")
            }

            if let primer = primerPath() {
                ProjectActionBtn("text.book.closed", "Primer", .secondary) {
                    if let path = project.localPath {
                        let safe = primer.replacingOccurrences(of: "'", with: "'\\''")
                        let cmd = "claude 'Read '\\''\(safe)'\\'' and orient yourself, then ask what to do next.'"
                        TerminalLauncher.run(cmd, in: path)
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let visible = showAllSessions ? claudeSessions : Array(claudeSessions.prefix(3))
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visible, id: \.uuid) { s in
                    sessionRow(s)
                }
                if !showAllSessions && claudeSessions.count > 3 {
                    Button {
                        showAllSessions = true
                    } label: {
                        Text("\(claudeSessions.count - 3) more…")
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Df.space2)
                }
            }
            .padding(.top, Df.space1)
        }
    }

    private func sessionRow(_ s: SessionRegistry.Session) -> some View {
        Button {
            if let path = project.localPath {
                TerminalLauncher.run("claude --resume \(s.uuid)", in: path)
            }
        } label: {
            HStack(spacing: Df.space2) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Df.agent.opacity(0.8))
                Text(s.summary ?? s.uuid.prefix(8).description)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textSecondary(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(relativeAge(s.lastModified))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Df.textTertiary(scheme))
                Text("\(s.byteSize / 1024) KB")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Df.textQuaternary(scheme))
            }
            .padding(.horizontal, Df.space2)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Df.inset(scheme).opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .help("Resume \(s.uuid) — \(s.byteSize / 1024) KB")
    }

    private func primerPath() -> String? {
        guard let p = project.localPath else { return nil }
        let fm = FileManager.default
        for name in ["PLAN.md", "DEVNOTES.md", "README.md"] {
            let full = (p as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: full) { return full }
        }
        return nil
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
}
