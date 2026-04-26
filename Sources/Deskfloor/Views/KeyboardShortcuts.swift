import SwiftUI

struct ContentViewShortcuts: View {
    @Binding var viewMode: ViewMode
    @Binding var showNewProject: Bool
    @Binding var editingProject: Project
    var selectedProject: Project?
    var onImport: () -> Void

    var body: some View {
        // Split into two Groups to stay under SwiftUI's TupleView 10-child ceiling.
        Group {
            Group {
                Button("") { viewMode = .board }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { viewMode = .perspective }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { viewMode = .timeline }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { viewMode = .graph }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { viewMode = .skein }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { viewMode = .paste }
                    .keyboardShortcut("6", modifiers: .command)
                Button("") { viewMode = .attention }
                    .keyboardShortcut("7", modifiers: .command)
                Button("") { viewMode = .loom }
                    .keyboardShortcut("8", modifiers: .command)
            }
            Group {
                Button("") {
                    editingProject = Project.blank()
                    showNewProject = true
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("") { onImport() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("") {
                    if let repo = selectedProject?.repo {
                        let urlString = "https://github.com/\(repo)"
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
