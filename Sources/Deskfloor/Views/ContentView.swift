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
    @State var fleet: FleetStore = FleetStore()
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
                toolbar
                Divider().opacity(0.5)
                mainContent
                Divider().opacity(0.5)
                if !selectedProjects.isEmpty {
                    selectionBar
                }
                fleetBar
            }
            .onAppear {
                fleet.startPolling()
                dataBus.poll(projects: store.projects)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Df.canvas(scheme))
        .sheet(isPresented: $showDispatch) { dispatchPanel }
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
        .onReceive(NotificationCenter.default.publisher(for: .projectStatusChange)) { notification in
            if let info = notification.userInfo,
               let id = info["id"] as? UUID,
               let status = info["status"] as? Status {
                store.moveProject(id: id, toStatus: status)
            }
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
                Button("") { viewMode = .paste }
                    .keyboardShortcut("6", modifiers: .command)
                Button("") { viewMode = .attention }
                    .keyboardShortcut("7", modifiers: .command)
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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Df.space3) {
            // View mode picker — skeuomorphic segmented control
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    Button(action: { viewMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                viewMode == mode
                                    ? Df.textPrimary(scheme)
                                    : Df.textTertiary(scheme)
                            )
                            .frame(width: 28, height: 24)
                            .background(
                                viewMode == mode
                                    ? Df.elevated(scheme)
                                    : .clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
                            .shadow(
                                color: viewMode == mode ? Df.bevelShadow(scheme) : .clear,
                                radius: 2, y: 1
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(2)
            .background(Df.inset(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall + 2))

            Text(viewMode.label)
                .font(Df.captionFont)
                .foregroundStyle(Df.textSecondary(scheme))

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
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }
                }
            }

            toolbarButton("Scan", icon: "folder.badge.gearshape", disabled: store.isScanning) {
                store.scanLocalProjects()
            }

            toolbarButton("Refresh", icon: "arrow.clockwise") {
                store.refreshGitInfo()
            }

            toolbarButton("Import", icon: "square.and.arrow.down", disabled: importInProgress) {
                importFromGitHub()
            }

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
            .tint(Df.accent)
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space2)
        .background(Df.surface(scheme))
    }

    private func toolbarButton(_ label: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Df.textSecondary(scheme))
        .disabled(disabled)
        .help(label)
    }

    // MARK: - Main Content

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

            if viewMode == .paste {
                PasteAnalysisView()
            }

            if viewMode == .attention {
                AttentionView(dataBus: dataBus, store: store)
            }
        }
    }

    // MARK: - Fleet Bar

    private var fleetBar: some View {
        HStack(spacing: Df.space4) {
            if fleet.isReachable {
                ForEach(fleet.hosts) { host in
                    Button(action: { DeskfloorApp.sshJump(host: host.name) }) {
                        HStack(spacing: 4) {
                            Text(host.sigil)
                                .font(.system(size: 10))
                            Text(host.name)
                                .font(Df.monoSmallFont)
                                .foregroundStyle(Df.textSecondary(scheme))
                            DfPill(
                                text: String(format: "%.0f", host.load),
                                color: host.load > 4 ? Df.critical : host.load > 2 ? Df.uncertain : Df.certain
                            )
                            DfPill(
                                text: "\(host.diskPercent)%",
                                color: host.diskPercent >= 85 ? Df.uncertain : Df.certain
                            )
                            if host.claudeCount > 0 {
                                DfPill(text: "\(host.claudeCount)cl", color: Df.agent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("SSH to \(host.name)")
                }
            } else {
                Text("Fleet offline")
                    .font(Df.captionFont)
                    .foregroundStyle(Df.textTertiary(scheme))
            }

            Spacer()

            if let update = fleet.lastUpdate {
                Text(update, style: .relative)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }

            Text("Ctrl+Space: Launcher")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textQuaternary(scheme))
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, 5)
        .background(Df.surface(scheme).opacity(0.8))
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        let selected = store.projects.filter { selectedProjects.contains($0.id) }
        return HStack(spacing: Df.space3) {
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
