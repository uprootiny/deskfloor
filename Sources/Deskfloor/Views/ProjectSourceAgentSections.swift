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

    private var hasSource: Bool { project.localPath != nil }
    private var hasRepo: Bool { project.repo != nil }

    private var agentThreads: [Thread] {
        guard let skein else { return [] }
        return skein.threadsForProject(project.id)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ProjectActionSection(title: "AGENT", icon: "brain", key: "agent", expandedSections: expandedSections, project: $project) {
            VStack(alignment: .leading, spacing: Df.space2) {
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

                    if let latest = agentThreads.first, latest.status == .live || latest.status == .paused {
                        ProjectActionBtn("arrow.counterclockwise", "Resume", .accent) {
                            if let path = project.localPath {
                                TerminalLauncher.run("claude --continue", in: path)
                            }
                        }
                    } else {
                        ProjectDisabledAction("arrow.counterclockwise", "Resume", hint: agentThreads.isEmpty ? "no sessions" : "none active")
                    }

                    let count = agentThreads.count
                    if count > 0 {
                        ProjectActionBtn("clock.arrow.circlepath", "History (\(count))", .secondary) {}
                    } else {
                        ProjectDisabledAction("clock.arrow.circlepath", "History", hint: "none yet")
                    }

                    Spacer()
                }

                if let latest = agentThreads.first {
                    HStack(spacing: Df.space2) {
                        Circle()
                            .fill(latest.status.color)
                            .frame(width: 6, height: 6)
                        Text(latest.title)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textSecondary(scheme))
                            .lineLimit(1)
                        Spacer()
                        Text(latest.updatedAt, style: .relative)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }
                    .padding(.horizontal, Df.space2)
                }
            }
        }
    }
}
