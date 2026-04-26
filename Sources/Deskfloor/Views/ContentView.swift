import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case board
    case perspective
    case timeline
    case graph
    case skein
    case paste
    case attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: "Board"
        case .perspective: "Perspective"
        case .timeline: "Timeline"
        case .graph: "Graph"
        case .skein: "Skein"
        case .paste: "Loom"
        case .attention: "Attention"
        }
    }

    var icon: String {
        switch self {
        case .board: "rectangle.split.3x1"
        case .perspective: "square.grid.3x3"
        case .timeline: "chart.bar.xaxis"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .skein: "line.3.horizontal"
        case .paste: "doc.on.clipboard"
        case .attention: "exclamationmark.triangle"
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    @State var store: ProjectStore
    @State var fleet: FleetStore
    @State var skein: SkeinStore = SkeinStore()
    @State var dataBus: DataBus = DataBus()
    @State private var viewMode: ViewMode = .board
    @State private var searchText = ""
    @State private var selectedPerspectives: Set<Perspective> = []
    @State private var selectedStatuses: Set<Status> = []
    @State private var selectedEncumbranceKinds: Set<EncumbranceKind> = []
    @State private var handoffOnly = false
    @State private var encumberedOnly = false
    @State private var selectedProject: Project?
    @State private var selectedProjects: Set<UUID> = []
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
                ViewModeToolbar(
                    viewMode: $viewMode,
                    sortOrder: Binding(get: { store.sortOrder }, set: { store.sortOrder = $0 }),
                    isScanning: store.isScanning,
                    scanProgress: store.scanProgress,
                    importInProgress: importInProgress,
                    onScan: { store.scanLocalProjects() },
                    onRefresh: { store.refreshGitInfo() },
                    onImport: { importFromGitHub() },
                    onNewProject: { editingProject = Project.blank(); showNewProject = true }
                )
                Divider().opacity(0.5)
                mainContent
                Divider().opacity(0.5)
                if !selectedProjects.isEmpty {
                    SelectionBar(store: store, selectedProjects: $selectedProjects, showDispatch: $showDispatch)
                }
                FleetBar(fleet: fleet)
            }
            .onAppear {
                fleet.startPolling()
                dataBus.poll(projects: store.projects)
            }
            .onChange(of: dataBus.lastCIPoll) { _, _ in
                dataBus.syncCIToProjects(store)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Df.canvas(scheme))
        .sheet(isPresented: $showDispatch) {
            DispatchView(
                projects: store.projects.filter { selectedProjects.contains($0.id) },
                onDismiss: { showDispatch = false }
            )
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(
                project: Binding(
                    get: { selectedProject ?? project },
                    set: { selectedProject = $0 }
                ),
                isNew: false,
                skein: skein,
                fleet: fleet,
                dataBus: dataBus,
                onSave: { updated in store.updateProject(updated); selectedProject = nil },
                onDelete: { store.deleteProject(project); selectedProject = nil },
                onCancel: { selectedProject = nil }
            )
        }
        .sheet(isPresented: $showNewProject) {
            ProjectDetailSheet(
                project: $editingProject,
                isNew: true,
                onSave: { newProject in store.addProject(newProject); showNewProject = false; editingProject = Project.blank() },
                onCancel: { showNewProject = false; editingProject = Project.blank() }
            )
        }
        .alert("Import Error", isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectStatusChange)) { notification in
            if let info = notification.userInfo,
               let id = info["id"] as? UUID,
               let status = info["status"] as? Status {
                store.moveProject(id: id, toStatus: status)
            }
        }
        .background(
            ContentViewShortcuts(
                viewMode: $viewMode,
                showNewProject: $showNewProject,
                editingProject: $editingProject,
                selectedProject: selectedProject,
                onImport: { importFromGitHub() }
            )
        )
    }

    @ViewBuilder
    private var mainContent: some View {
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
                PerspectiveView(store: store, filteredProjects: filteredProjects, selectedProject: $selectedProject)
            }
            if viewMode == .timeline {
                ProjectTimelineView(filteredProjects: filteredProjects, selectedProject: $selectedProject)
            }
            if viewMode == .graph {
                GraphView(filteredProjects: filteredProjects, selectedProject: $selectedProject)
            }
            if viewMode == .skein {
                SkeinView(skein: skein, store: store)
            }
            if viewMode == .paste {
                PasteAnalysisView()
            }
            if viewMode == .attention {
                AttentionView(dataBus: dataBus, store: store)
            }
        }
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
