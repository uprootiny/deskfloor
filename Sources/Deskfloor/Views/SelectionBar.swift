import SwiftUI

struct SelectionBar: View {
    @Environment(\.colorScheme) private var scheme
    var store: ProjectStore
    @Binding var selectedProjects: Set<UUID>
    @Binding var showDispatch: Bool

    private var selected: [Project] {
        store.projects.filter { selectedProjects.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: Df.space3) {
            Text("\(selected.count) selected")
                .font(Df.headlineFont)
                .foregroundStyle(Df.textPrimary(scheme))

            Button("Dispatch to Claude Code") {
                showDispatch = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Df.agent)
            .controlSize(.small)

            Menu("Set Status") {
                ForEach(Status.allCases) { status in
                    Button(status.label) {
                        for id in selectedProjects {
                            store.moveProject(id: id, toStatus: status)
                        }
                    }
                }
            }
            .controlSize(.small)

            Button("Open All on GitHub") {
                for project in selected {
                    if let repo = project.repo, let url = URL(string: "https://github.com/\(repo)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Df.textSecondary(scheme))

            Spacer()

            Button("Clear") { selectedProjects.removeAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Df.textTertiary(scheme))
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space2)
        .background(Df.agent.opacity(scheme == .dark ? 0.08 : 0.06))
    }
}
