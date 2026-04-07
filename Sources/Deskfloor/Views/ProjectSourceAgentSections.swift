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
                if hasSource {
                    ProjectActionBtn("folder", "Open", .primary) {
                        DeskfloorApp.openInITerm("cd \(project.localPath!)")
                    }
                } else {
                    ProjectDisabledAction("folder", "Open", hint: "needs local path")
                }

                if hasRepo {
                    ProjectActionBtn("link", "GitHub", .secondary) {
                        if let url = URL(string: "https://github.com/\(project.repo!)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    ProjectDisabledAction("link", "GitHub", hint: "set repo")
                }

                if hasRepo {
                    ProjectActionBtn("arrow.down.circle", "Clone", .secondary) {
                        DeskfloorApp.openInITerm("cd ~/Nissan && gh repo clone \(project.repo!)")
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
                    if hasSource {
                        ProjectActionBtn("plus.circle", "Fresh", .primary) {
                            DeskfloorApp.openInITerm("cd \(project.localPath!) && claude")
                        }
                    } else if hasRepo {
                        ProjectActionBtn("plus.circle", "Fresh", .primary) {
                            DeskfloorApp.openInITerm("cd ~/Nissan && gh repo clone \(project.repo!) 2>/dev/null; cd ~/Nissan/\(project.name) && claude")
                        }
                    } else {
                        ProjectDisabledAction("plus.circle", "Fresh", hint: "needs source")
                    }

                    if let latest = agentThreads.first, latest.status == .live || latest.status == .paused {
                        ProjectActionBtn("arrow.counterclockwise", "Resume", .accent) {
                            if let path = project.localPath {
                                DeskfloorApp.openInITerm("cd \(path) && claude --continue")
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
