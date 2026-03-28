import SwiftUI

struct BoardView: View {
    @Bindable var store: ProjectStore
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    @Binding var selectedProjects: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Status.allCases) { status in
                    statusColumn(status)
                }
            }
            .padding()
        }
    }

    private func statusColumn(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(projectsFor(status).count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().background(status.color.opacity(0.3))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(projectsFor(status)) { project in
                        ProjectCard(
                            project: project,
                            isSelected: selectedProjects.contains(project.id)
                        ) {
                            selectedProject = project
                        }
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                // Cmd+Click: toggle multi-select
                                if selectedProjects.contains(project.id) {
                                    selectedProjects.remove(project.id)
                                } else {
                                    selectedProjects.insert(project.id)
                                }
                            } else {
                                // Normal click: open detail
                                selectedProject = project
                            }
                        }
                        .draggable(project.id.uuidString)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 240)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.15), lineWidth: 1)
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
