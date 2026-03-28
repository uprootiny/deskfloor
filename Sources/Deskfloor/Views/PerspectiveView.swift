import SwiftUI

struct PerspectiveView: View {
    @Bindable var store: ProjectStore
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    @Binding var showDetail: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Perspective.allCases) { perspective in
                    perspectiveColumn(perspective)
                }
            }
            .padding()
        }
    }

    private func perspectiveColumn(_ perspective: Perspective) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(perspective.color)
                    .frame(width: 8, height: 8)
                Text(perspective.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(projectsFor(perspective).count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().background(perspective.color.opacity(0.3))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(projectsFor(perspective)) { project in
                        ProjectCard(project: project) {
                            selectedProject = project
                            showDetail = true
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
                .stroke(perspective.color.opacity(0.15), lineWidth: 1)
        )
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let uuid = UUID(uuidString: item) {
                    store.moveProject(id: uuid, toPerspective: perspective)
                }
            }
            return true
        }
    }

    private func projectsFor(_ perspective: Perspective) -> [Project] {
        filteredProjects.filter { $0.perspective == perspective }
    }
}
