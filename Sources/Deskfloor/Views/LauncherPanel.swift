import SwiftUI

// MARK: - Launcher Panel (Apple HIG variant)
// Follows Human Interface Guidelines: system fonts, standard controls,
// generous spacing, sidebar material, accent color selection, accessibility.

struct LauncherPanelView: View {
    @State var store: ProjectStore
    @State var fleet: FleetStore
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    var onDismiss: () -> Void
    var onAction: (LauncherItem) -> Void

    private let searcher = LauncherSearch()

    private var allItems: [LauncherItem] {
        var items: [LauncherItem] = []
        for host in fleet.hosts {
            items.append(.host(host))
            for session in host.sessions {
                items.append(.session(host, session))
            }
        }
        let active = store.projects
            .filter { $0.status == .active }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        for project in active.prefix(30) {
            items.append(.project(project))
        }
        return items
    }

    private var results: [LauncherItem] {
        searcher.search(query: query, items: allItems)
    }

    private var grouped: [(String, [LauncherItem])] {
        let dict = Dictionary(grouping: results, by: \.category)
        return ["Hosts", "Sessions", "Projects", "Commands"].compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Search — standard macOS search field appearance
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { executeSelected() }
                    .accessibilityLabel("Search hosts, sessions, and projects")
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(.bar)

            Divider()

            // MARK: Results — source list style
            if results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(height: 200)
            } else {
                List(selection: $selectedID) {
                    ForEach(grouped, id: \.0) { category, items in
                        Section(category) {
                            ForEach(items) { item in
                                HIGLauncherRow(item: item)
                                    .tag(item.id)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minHeight: 200, maxHeight: 420)
                .onChange(of: query) { _, _ in
                    selectedID = results.first?.id
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .onKeyPress(.return) {
                    executeSelected()
                    return .handled
                }
            }

            Divider()

            // MARK: Footer — standard toolbar appearance
            HStack {
                Label("Return to open", systemImage: "return")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if fleet.isReachable {
                    Label("\(fleet.hosts.count) hosts online", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .onAppear {
            searchFocused = true
            selectedID = results.first?.id
        }
        .environment(\.colorScheme, .dark)
    }

    private func executeSelected() {
        guard let id = selectedID,
              let item = results.first(where: { $0.id == id }) else { return }
        onAction(item)
    }
}

// MARK: - Row (HIG style: SF Symbol + primary/secondary text + accessory)

struct HIGLauncherRow: View {
    let item: LauncherItem

    var body: some View {
        HStack(spacing: 10) {
            // Standard SF Symbol — no colored background box
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Accessory: system-style badges
            accessory
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var accessory: some View {
        switch item {
        case .host(let h):
            HStack(spacing: 6) {
                if h.diskPercent >= 85 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.caption)
                }
                Text("load \(String(format: "%.1f", h.load))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .session(_, let s):
            Text(s.attached ? "attached" : "detached")
                .font(.caption2)
                .foregroundStyle(s.attached ? .blue : .secondary)
        case .project(let p):
            if let lang = p.tags.first {
                Text(lang)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .command:
            Image(systemName: "terminal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch item {
        case .host: "server.rack"
        case .session: "terminal"
        case .project: "folder"
        case .command: "command"
        }
    }

    private var iconColor: Color {
        switch item {
        case .host(let h): h.reachable ? .green : .red
        case .session(_, let s): s.attached ? .blue : .gray
        case .project: .accentColor
        case .command: .orange
        }
    }

    private var accessibilityHint: String {
        switch item {
        case .host: "Press return to SSH to this host"
        case .session: "Press return to attach this tmux session"
        case .project: "Press return to open on GitHub"
        case .command: "Press return to run this command"
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
