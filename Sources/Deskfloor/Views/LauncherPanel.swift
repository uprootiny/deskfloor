import SwiftUI

// MARK: - Launcher Panel (v2: dense, keyboard-driven)

struct LauncherPanelView: View {
    @State var store: ProjectStore
    @State var fleet: FleetStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    var onDismiss: () -> Void
    var onAction: (LauncherItem) -> Void

    private let searcher = LauncherSearch()

    private var allItems: [LauncherItem] {
        var items: [LauncherItem] = []

        // Fleet hosts — always first
        for host in fleet.hosts {
            items.append(.host(host))
            for session in host.sessions {
                items.append(.session(host, session))
            }
        }

        // Active projects, most recent first
        let active = store.projects
            .filter { $0.status == .active }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        for project in active.prefix(30) {
            items.append(.project(project))
        }

        return items
    }

    private var results: [LauncherItem] {
        let r = searcher.search(query: query, items: allItems)
        return r
    }

    private var flatResults: [LauncherItem] {
        results
    }

    private var grouped: [(String, [LauncherItem])] {
        let dict = Dictionary(grouping: results, by: \.category)
        let order = ["Hosts", "Sessions", "Projects", "Commands"]
        return order.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.3)
            resultsList
            if let toast {
                toastBar(toast)
            } else {
                footerBar
            }
        }
        .frame(width: 640)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, flatResults.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.tab) {
            jumpToNextCategory()
            return .handled
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            TextField("", text: $query, prompt: Text("Jump to...").foregroundStyle(.white.opacity(0.25)))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light, design: .default))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { executeSelected() }

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .buttonStyle(.plain)
            }

            // Item count badge
            if !query.isEmpty {
                Text("\(flatResults.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if flatResults.isEmpty && !query.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(grouped.enumerated()), id: \.0) { _, group in
                            let (category, items) = group
                            categoryHeader(category, count: items.count)
                            ForEach(items) { item in
                                let idx = flatResults.firstIndex(where: { $0.id == item.id }) ?? 0
                                LauncherRow(
                                    item: item,
                                    isSelected: idx == selectedIndex
                                )
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = idx
                                    executeSelected()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 100, maxHeight: 420)
            .onChange(of: selectedIndex) { _, newIndex in
                if let item = flatResults[safe: newIndex] {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func categoryHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
            Text("\(count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.15))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.15))
            Text("No results for \"\(query)\"")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 0) {
            footerKey("Enter", label: "open")
            footerKey("Tab", label: "next group")
            footerKey("Esc", label: "close")
            Spacer()
            if fleet.isReachable {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("\(fleet.hosts.count) hosts")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.white.opacity(0.02))
    }

    private func footerKey(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.trailing, 12)
    }

    private func toastBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.green.opacity(0.08))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func executeSelected() {
        guard let item = flatResults[safe: selectedIndex] else { return }

        // Show toast
        let msg: String
        switch item {
        case .host(let h): msg = "Connecting to \(h.name)..."
        case .session(let h, let s): msg = "Attaching \(h.name):\(s.name)..."
        case .project(let p): msg = "Opening \(p.name)..."
        case .command(let label, _): msg = "Running \(label)..."
        }

        withAnimation(.easeIn(duration: 0.15)) { toast = msg }

        // Execute after brief delay for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAction(item)
        }
    }

    private func jumpToNextCategory() {
        let flat = flatResults
        guard !flat.isEmpty else { return }

        let currentCat = flat[safe: selectedIndex]?.category ?? ""
        // Find first item of the next category
        var foundCurrent = false
        for (i, item) in flat.enumerated() {
            if item.category == currentCat {
                foundCurrent = true
            } else if foundCurrent {
                selectedIndex = i
                return
            }
        }
        // Wrap to beginning
        selectedIndex = 0
    }
}

// MARK: - Row

struct LauncherRow: View {
    let item: LauncherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .padding(.trailing, 10)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            // Action hint
            if isSelected {
                Text(actionHint)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Inline metric for hosts
            if case .host(let h) = item {
                HStack(spacing: 8) {
                    metricPill(
                        "\(String(format: "%.0f", h.load))",
                        color: h.load > 4 ? .red : h.load > 2 ? .orange : .green
                    )
                    metricPill(
                        "\(h.diskPercent)%",
                        color: h.diskPercent >= 85 ? .orange : .green
                    )
                    if h.claudeCount > 0 {
                        metricPill("\(h.claudeCount)cl", color: .blue)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(isSelected ? Color.white.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    private func metricPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var actionHint: String {
        switch item {
        case .host: return "SSH"
        case .session: return "ATTACH"
        case .project: return "OPEN"
        case .command: return "RUN"
        }
    }

    private var iconName: String {
        switch item {
        case .host: return "server.rack"
        case .session: return "terminal"
        case .project: return "folder.fill"
        case .command: return "command"
        }
    }

    private var iconColor: Color {
        switch item {
        case .host(let h): return h.reachable ? .green : .red
        case .session(_, let s): return s.attached ? .blue : .gray
        case .project(let p): return p.perspective.color
        case .command: return .orange
        }
    }
}

// MARK: - Safe Array Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
