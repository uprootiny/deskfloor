import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case board
    case perspective
    case timeline
    case graph
    case skein

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: "Board"
        case .perspective: "Perspective"
        case .timeline: "Timeline"
        case .graph: "Graph"
        case .skein: "Skein"
        }
    }

    var icon: String {
        switch self {
        case .board: "rectangle.split.3x1"
        case .perspective: "square.grid.3x3"
        case .timeline: "chart.bar.xaxis"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .skein: "line.3.horizontal"
        }
    }
}

struct ContentView: View {
    @State var store: ProjectStore
    @State var fleet: FleetStore = FleetStore()
    @State var skein: SkeinStore = SkeinStore()
    @State private var viewMode: ViewMode = .board
    @State private var searchText = ""
    @State private var selectedPerspectives: Set<Perspective> = []
    @State private var selectedStatuses: Set<Status> = []
    @State private var selectedEncumbranceKinds: Set<EncumbranceKind> = []
    @State private var handoffOnly = false
    @State private var encumberedOnly = false
    @State private var selectedProject: Project?
    @State private var selectedProjects: Set<UUID> = []  // multi-select
    @State private var showDispatch = false
    @State private var showNewProject = false
    @State private var editingProject = Project.blank()
    @State private var importInProgress = false
    @State private var importError: String?
    @State private var showImportAlert = false

    private var filteredProjects: [Project] {
        store.filtered(
            searchText: searchText,
            perspectives: selectedPerspectives,
            statuses: selectedStatuses,
            encumbranceKinds: selectedEncumbranceKinds,
            handoffOnly: handoffOnly,
            encumberedOnly: encumberedOnly
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                searchText: $searchText,
                selectedPerspectives: $selectedPerspectives,
                selectedStatuses: $selectedStatuses,
                selectedEncumbranceKinds: $selectedEncumbranceKinds,
                handoffOnly: $handoffOnly,
                encumberedOnly: $encumberedOnly,
                projectCount: store.projects.count,
                filteredCount: filteredProjects.count
            )
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider().background(Color.white.opacity(0.1))
                mainContent
                Divider().background(Color.white.opacity(0.1))
                // Selection bar (appears when projects are multi-selected)
                if !selectedProjects.isEmpty {
                    selectionBar
                }
                fleetBar
            }
            .onAppear { fleet.startPolling() }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDispatch) { dispatchPanel }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(
                project: Binding(
                    get: { selectedProject ?? project },
                    set: { selectedProject = $0 }
                ),
                isNew: false,
                onSave: { updated in
                    store.updateProject(updated)
                    selectedProject = nil
                },
                onDelete: {
                    store.deleteProject(project)
                    selectedProject = nil
                },
                onCancel: {
                    selectedProject = nil
                }
            )
        }
        .sheet(isPresented: $showNewProject) {
            ProjectDetailSheet(
                project: $editingProject,
                isNew: true,
                onSave: { newProject in
                    store.addProject(newProject)
                    showNewProject = false
                    editingProject = Project.blank()
                },
                onCancel: {
                    showNewProject = false
                    editingProject = Project.blank()
                }
            )
        }
        .alert("Import Error", isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .background(
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
                Button("") {
                    editingProject = Project.blank()
                    showNewProject = true
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("") { importFromGitHub() }
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
            .frame(width: 0, height: 0)
            .opacity(0)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // View mode picker
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    Button(action: { viewMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(viewMode == mode ? .white : .white.opacity(0.3))
                            .frame(width: 28, height: 24)
                            .background(viewMode == mode ? Color.white.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(viewMode.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Picker("Sort", selection: Binding(
                get: { store.sortOrder },
                set: { store.sortOrder = $0 }
            )) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Spacer()

            if importInProgress {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            }

            if store.isScanning {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    if store.scanProgress.total > 0 {
                        Text("\(store.scanProgress.done)/\(store.scanProgress.total)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            Button(action: {
                store.scanLocalProjects()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 11))
                    Text("Scan")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .disabled(store.isScanning)
            .help("Scan ~/Nissan/ for local projects")

            Button(action: {
                store.refreshGitInfo()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Refresh")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .help("Refresh git status for all projects")

            Button(action: importFromGitHub) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                    Text("Import")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .disabled(importInProgress)

            Button(action: {
                editingProject = Project.blank()
                showNewProject = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("New")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.3, green: 0.7, blue: 0.5).opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    @ViewBuilder
    private var mainContent: some View {
        // ZStack keeps all views alive — switching is instant (no teardown/rebuild)
        ZStack {
            BoardView(
                store: store,
                filteredProjects: filteredProjects,
                selectedProject: $selectedProject,
                selectedProjects: $selectedProjects
            )
            .opacity(viewMode == .board ? 1 : 0)
            .allowsHitTesting(viewMode == .board)

            if viewMode == .perspective {
                PerspectiveView(
                    store: store,
                    filteredProjects: filteredProjects,
                    selectedProject: $selectedProject
                )
            }

            if viewMode == .timeline {
                ProjectTimelineView(
                    filteredProjects: filteredProjects,
                    selectedProject: $selectedProject
                )
            }

            if viewMode == .graph {
                GraphView(
                    filteredProjects: filteredProjects,
                    selectedProject: $selectedProject
                )
            }

            if viewMode == .skein {
                SkeinView(skein: skein, store: store)
            }
        }
    }

    private var fleetBar: some View {
        HStack(spacing: 16) {
            if fleet.isReachable {
                ForEach(fleet.hosts) { host in
                    Button(action: { DeskfloorApp.sshJump(host: host.name) }) {
                        HStack(spacing: 4) {
                            Text(host.sigil)
                                .font(.system(size: 10))
                            Text(host.name)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(String(format: "%.0f", host.load))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(host.load > 4 ? .red : .white.opacity(0.4))
                            Text("\(host.diskPercent)%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(host.diskPercent >= 85 ? .orange : .white.opacity(0.4))
                            if host.claudeCount > 0 {
                                Text("\(host.claudeCount)cl")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.blue.opacity(0.7))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("SSH to \(host.name)")
                }
            } else {
                Text("Fleet offline")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            if let update = fleet.lastUpdate {
                Text(update, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            Text("Ctrl+Space: Launcher")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }

    // MARK: - Selection Bar (multi-select actions)

    private var selectionBar: some View {
        let selected = store.projects.filter { selectedProjects.contains($0.id) }
        return HStack(spacing: 12) {
            Text("\(selected.count) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)

            Button("Dispatch to Claude Code") {
                showDispatch = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue.opacity(0.8))
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
            .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Button("Clear") { selectedProjects.removeAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
    }

    // MARK: - Dispatch Panel

    private var dispatchPanel: some View {
        DispatchView(
            projects: store.projects.filter { selectedProjects.contains($0.id) },
            onDismiss: { showDispatch = false }
        )
    }

    private func importFromGitHub() {
        importInProgress = true
        Task {
            do {
                let imported = try await GitHubImporter.importRepos(owner: nil)
                let existingNames = Set(store.projects.map(\.name))
                let newProjects = imported.filter { !existingNames.contains($0.name) }
                for project in newProjects {
                    store.addProject(project)
                }
                importInProgress = false
            } catch {
                importError = error.localizedDescription
                showImportAlert = true
                importInProgress = false
            }
        }
    }
}
