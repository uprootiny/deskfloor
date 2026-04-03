import SwiftUI

struct SurfacesView: View {
    @Environment(\.colorScheme) private var scheme
    let surfaceStore: SurfaceStore
    let projectStore: ProjectStore

    private var groupedSurfaces: [(project: Project?, surfaces: [Surface])] {
        let all = surfaceStore.allSurfaces

        // Group by projectID
        var byProject: [UUID: [Surface]] = [:]
        var unattached: [Surface] = []
        for surface in all {
            if let pid = surface.projectID {
                byProject[pid, default: []].append(surface)
            } else {
                unattached.append(surface)
            }
        }

        // Build sorted groups: most surfaces first
        var groups: [(project: Project?, surfaces: [Surface])] = []
        let sortedKeys = byProject.keys.sorted { byProject[$0]!.count > byProject[$1]!.count }
        for key in sortedKeys {
            let project = projectStore.projects.first { $0.id == key }
            groups.append((project: project, surfaces: byProject[key]!))
        }

        // Unattached at the bottom
        if !unattached.isEmpty {
            groups.append((project: nil, surfaces: unattached))
        }

        return groups
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Df.space4) {
                HStack {
                    Text("Surfaces")
                        .font(Df.titleFont)
                        .foregroundStyle(Df.textPrimary(scheme))

                    Spacer()

                    if surfaceStore.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }

                    Button(action: { surfaceStore.scan() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Refresh")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Df.textSecondary(scheme))
                }
                .padding(.bottom, Df.space2)

                // Summary row
                HStack(spacing: Df.space3) {
                    ForEach(SurfaceKind.allCases, id: \.rawValue) { kind in
                        let count = surfaceStore.allSurfaces.filter { $0.kind == kind }.count
                        if count > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(kind.color)
                                Text("\(count)")
                                    .font(Df.monoSmallFont)
                                    .foregroundStyle(Df.textSecondary(scheme))
                            }
                        }
                    }
                    Spacer()
                    Text("\(surfaceStore.allSurfaces.count) total")
                        .font(Df.captionFont)
                        .foregroundStyle(Df.textTertiary(scheme))
                }
                .padding(.bottom, Df.space2)

                ForEach(Array(groupedSurfaces.enumerated()), id: \.offset) { _, group in
                    surfaceSection(project: group.project, surfaces: group.surfaces)
                }

                if surfaceStore.allSurfaces.isEmpty && !surfaceStore.isScanning {
                    VStack(spacing: Df.space3) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(Df.textQuaternary(scheme))
                        Text("No surfaces discovered")
                            .font(Df.captionFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                        Text("Open terminals, start servers, or browse GitHub to see surfaces here.")
                            .font(Df.captionFont)
                            .foregroundStyle(Df.textQuaternary(scheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Df.space8)
                }
            }
            .padding(Df.space4)
        }
        .background(Df.canvas(scheme))
    }

    // MARK: - Section

    @ViewBuilder
    private func surfaceSection(project: Project?, surfaces: [Surface]) -> some View {
        VStack(alignment: .leading, spacing: Df.space2) {
            DfSectionHeader(
                title: project?.name ?? "Unattached",
                count: surfaces.count
            )

            ForEach(surfaces, id: \.id) { surface in
                surfaceRow(surface)
            }
        }
    }

    // MARK: - Row

    private func surfaceRow(_ surface: Surface) -> some View {
        DfCard {
            HStack(spacing: Df.space2) {
                Image(systemName: surface.kind.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(surface.kind.color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(surface.label)
                        .font(Df.monoFont)
                        .foregroundStyle(Df.textPrimary(scheme))
                        .lineLimit(1)

                    Text(surface.detail)
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textTertiary(scheme))
                        .lineLimit(1)
                }

                Spacer()

                if let pid = surface.pid {
                    Text("PID \(pid)")
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textQuaternary(scheme))
                }

                Button(action: { jumpTo(surface) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(Df.textSecondary(scheme))
                }
                .buttonStyle(.plain)
                .help("Jump to surface")
            }
            .padding(.horizontal, Df.space2)
            .padding(.vertical, Df.space1)
        }
    }

    // MARK: - Jump Actions

    private func jumpTo(_ surface: Surface) {
        switch surface.kind {
        case .terminal:
            // Activate iTerm2
            let script = """
            tell application "iTerm2"
                activate
            end tell
            """
            runAppleScript(script)

        case .tmux:
            // Parse session:window from the label
            let parts = surface.label.split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count >= 2 {
                let session = parts[0]
                let window = parts[1]
                let cmd = "tmux select-window -t \(session):\(window)"
                DeskfloorApp.openInITerm(cmd)
            }

        case .port:
            // Open in browser
            let url = "http://\(surface.detail)"
            if let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }

        case .claudeCode:
            // Open project directory in terminal with Claude
            if let path = surface.path {
                DeskfloorApp.openInITerm("cd \(path) && claude")
            }

        case .browserTab:
            // Try to activate the browser and open the URL
            let url = surface.detail
            let browserName: String
            if surface.id.contains("safari") {
                browserName = "Safari"
            } else if surface.id.contains("chrome") {
                browserName = "Google Chrome"
            } else if surface.id.contains("arc") {
                browserName = "Arc"
            } else {
                // Fallback: just open URL
                if let nsURL = URL(string: url) {
                    NSWorkspace.shared.open(nsURL)
                }
                return
            }

            let script = """
            tell application "\(browserName)"
                activate
                set found to false
                repeat with w in windows
                    set tabIdx to 0
                    repeat with t in tabs of w
                        set tabIdx to tabIdx + 1
                        if URL of t contains "\(url.replacingOccurrences(of: "\"", with: "\\\""))" then
                            set active tab index of w to tabIdx
                            set index of w to 1
                            set found to true
                            exit repeat
                        end if
                    end repeat
                    if found then exit repeat
                end repeat
            end tell
            """
            runAppleScript(script)
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "" }
        let result = script.executeAndReturnError(&error)
        return result.stringValue ?? ""
    }
}
