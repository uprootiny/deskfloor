import SwiftUI

struct BoardView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var store: ProjectStore
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    @Binding var selectedProjects: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Df.space3) {
                ForEach(Status.allCases) { status in
                    statusColumn(status)
                }
            }
            .padding()
        }
    }

    private func statusColumn(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header — skeuomorphic tab
            HStack {
                DfStatusDot(color: status.color)
                Text(status.label)
                    .font(Df.headlineFont)
                    .foregroundStyle(Df.textSecondary(scheme))
                Text("\(projectsFor(status).count)")
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textTertiary(scheme))
                Spacer()
            }
            .padding(.horizontal, Df.space2)
            .padding(.vertical, Df.space2)

            Divider()
                .overlay(status.color.opacity(0.3))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Df.space2) {
                    ForEach(projectsFor(status)) { project in
                        ProjectCard(
                            project: project,
                            isSelected: selectedProjects.contains(project.id)
                        ) {
                            // Single tap handler — check for Cmd modifier
                            if NSEvent.modifierFlags.contains(.command) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if selectedProjects.contains(project.id) {
                                        selectedProjects.remove(project.id)
                                    } else {
                                        selectedProjects.insert(project.id)
                                    }
                                }
                            } else {
                                selectedProject = project
                            }
                        }
                        .draggable(project.id.uuidString)
                    }
                }
                .padding(Df.space2)
            }
        }
        .frame(minWidth: 220, idealWidth: 260)
        .background(Df.surface(scheme).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Df.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Df.radiusMedium)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            status.color.opacity(0.15),
                            Df.border(scheme)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let uuid = UUID(uuidString: item) {
                    store.moveProject(id: uuid, toStatus: status)
                }
            }
            return true
        }
    }

    private func projectsFor(_ status: Status) -> [Project] {
        filteredProjects.filter { $0.status == status }
    }
}
