import SwiftUI

struct GraphView: View {
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    // showDetail removed

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var draggedNode: UUID?
    @State private var hasInitialized = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Edges
                ForEach(filteredProjects) { project in
                    ForEach(project.connections, id: \.self) { connectionName in
                        if let target = filteredProjects.first(where: { $0.name == connectionName }) {
                            let from = position(for: project.id, in: size)
                            let to = position(for: target.id, in: size)
                            Path { path in
                                path.move(to: from)
                                path.addLine(to: to)
                            }
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                    }
                }

                // Nodes
                ForEach(filteredProjects) { project in
                    let pos = position(for: project.id, in: size)
                    graphNode(project: project)
                        .opacity(draggedNode == project.id ? 0.6 : 1.0)
                        .position(pos)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    draggedNode = project.id
                                    positions[project.id] = value.location
                                }
                                .onEnded { _ in
                                    draggedNode = nil
                                }
                        )
                        .onTapGesture {
                            selectedProject = project
                        }
                        .contextMenu {
                            Button(action: {
                                let cmd: String
                                if let path = project.localPath {
                                    cmd = "cd \(path) && claude"
                                } else if let repo = project.repo {
                                    cmd = "cd ~/Nissan && gh repo clone \(repo) 2>/dev/null; cd ~/Nissan/\(project.name) && claude"
                                } else {
                                    cmd = "claude"
                                }
                                DeskfloorApp.openInITerm(cmd)
                            }) {
                                Label("Run Agent Session", systemImage: "play.fill")
                            }
                            if let repo = project.repo {
                                Button(action: {
                                    if let url = URL(string: "https://github.com/\(repo)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Label("Open on GitHub", systemImage: "link")
                                }
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if !hasInitialized {
                    initializePositions(in: size)
                    hasInitialized = true
                }
            }
            .onChange(of: filteredProjects.count) {
                initializePositions(in: size)
            }
        }
    }

    private func graphNode(project: Project) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(project.perspective.color.opacity(0.6))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(project.status.color, lineWidth: 2)
                )

            Text(project.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 80)
        }
    }

    private func position(for id: UUID, in size: CGSize) -> CGPoint {
        positions[id] ?? CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func initializePositions(in size: CGSize) {
        let count = filteredProjects.count
        guard count > 0 else { return }

        // Group by perspective and lay out in a grid-like pattern
        let perspectives = Dictionary(grouping: filteredProjects, by: \.perspective)
        let perspectiveList = Perspective.allCases.filter { perspectives[$0] != nil }

        let cols = max(perspectiveList.count, 1)
        let colWidth = size.width / CGFloat(cols + 1)

        for (colIdx, perspective) in perspectiveList.enumerated() {
            let projects = perspectives[perspective] ?? []
            let rows = projects.count
            let rowHeight = size.height / CGFloat(rows + 1)
            let x = colWidth * CGFloat(colIdx + 1)

            for (rowIdx, project) in projects.enumerated() {
                let y = rowHeight * CGFloat(rowIdx + 1)
                // Add a little jitter to prevent perfect grid
                let jitterX = CGFloat.random(in: -15...15)
                let jitterY = CGFloat.random(in: -15...15)
                positions[project.id] = CGPoint(x: x + jitterX, y: y + jitterY)
            }
        }
    }
}
