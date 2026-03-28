import SwiftUI

// MARK: - Launcher Panel (Nielsen Usability Heuristics variant)
//
// Every design choice maps to one of Nielsen's 10 heuristics.
// Comments reference the heuristic number: [N1] = visibility of system status, etc.

struct LauncherPanelView: View {
    @State var store: ProjectStore
    @State var fleet: FleetStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var toast: ToastMessage?
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "launcherUsed")
    @FocusState private var searchFocused: Bool

    var onDismiss: () -> Void
    var onAction: (LauncherItem) -> Void

    private let searcher = LauncherSearch()

    struct ToastMessage: Equatable {
        let text: String
        let icon: String
        let color: Color
    }

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

    private var results: [LauncherItem] { searcher.search(query: query, items: allItems) }
    private var flatResults: [LauncherItem] { results }
    private var grouped: [(String, [LauncherItem])] {
        let dict = Dictionary(grouping: results, by: \.category)
        return ["Hosts", "Sessions", "Projects", "Commands"].compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.3)

            if isFirstLaunch && query.isEmpty {
                welcomeState // [N10] Help and documentation
            } else if flatResults.isEmpty && !query.isEmpty {
                errorRecoveryState // [N9] Help recognize/recover from errors
            } else {
                resultsList
            }

            if let toast {
                toastBar(toast) // [N1] Visibility of system status
            } else {
                footerBar // [N6] Recognition, [N10] Help
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
            selectedIndex = 0 // [N3] User control — reset on new search
        }
        .onKeyPress(.escape) {
            onDismiss() // [N3] User control and freedom
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
            jumpToNextCategory() // [N7] Flexibility — accelerator for power users
            return .handled
        }
    }

    // MARK: - Search Bar [N8] Aesthetic and minimalist

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            // [N2] Match real world — "Jump to" matches mental model
            TextField("", text: $query, prompt: Text("Jump to...").foregroundStyle(.white.opacity(0.25)))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { executeSelected() }

            // [N3] User control — always clearable
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .help("Clear search") // [N10] Help
            }

            // [N1] System status — live result count
            Text("\(flatResults.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(query.isEmpty ? 0.15 : 0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // [N1] System status — fleet connection indicator
            Circle()
                .fill(fleet.isReachable ? .green : .red)
                .frame(width: 6, height: 6)
                .help(fleet.isReachable ? "Fleet connected" : "Fleet offline") // [N10]
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Results [N4] Consistency, [N6] Recognition

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(grouped.enumerated()), id: \.0) { _, group in
                        let (category, items) = group
                        categoryHeader(category, count: items.count)
                        ForEach(items) { item in
                            let idx = flatResults.firstIndex(where: { $0.id == item.id }) ?? 0
                            NielsenRow(
                                item: item,
                                isSelected: idx == selectedIndex,
                                isDisabled: isItemDisabled(item) // [N5] Error prevention
                            )
                            .id(item.id)
                            .onTapGesture {
                                guard !isItemDisabled(item) else { return }
                                selectedIndex = idx
                                executeSelected()
                            }
                            .help(tooltipFor(item)) // [N10] Help on every element
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
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            Text("\(count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.15))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Welcome State [N10] Help and documentation

    private var welcomeState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.2))

            Text("Deskfloor Launcher")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                hintRow("Type a host name", "to SSH in iTerm")
                hintRow("Type a session name", "to attach tmux")
                hintRow("Type a project name", "to open on GitHub")
                hintRow("Press Tab", "to jump between groups")
            }
            .padding(.horizontal, 40)

            Button("Got it") {
                UserDefaults.standard.set(true, forKey: "launcherUsed")
                isFirstLaunch = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func hintRow(_ action: String, _ result: String) -> some View {
        HStack(spacing: 4) {
            Text(action)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(result)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Error Recovery [N9]

    private var errorRecoveryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.15))

            Text("No results for \"\(query)\"")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))

            // [N9] Suggest recovery actions
            VStack(spacing: 6) {
                if query.count > 3 {
                    Button("Try \"\(String(query.prefix(3)))\"") {
                        query = String(query.prefix(3))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.blue.opacity(0.7))
                }

                Button("Clear and browse all") {
                    query = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.blue.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer [N6] Recognition, [N10] Documentation

    private var footerBar: some View {
        HStack(spacing: 0) {
            footerKey("Enter", label: actionLabelForSelected) // [N6] Show what Enter will do
            footerKey("Tab", label: "next group")
            footerKey("Esc", label: "close")
            Spacer()
            // [N1] System status — data freshness
            if let update = fleet.lastUpdate {
                Text(update, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.white.opacity(0.02))
    }

    // [N6] Dynamic label shows what Enter will do for current selection
    private var actionLabelForSelected: String {
        guard let item = flatResults[safe: selectedIndex] else { return "open" }
        switch item {
        case .host: return "ssh"
        case .session: return "attach"
        case .project: return "open"
        case .command: return "run"
        }
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

    // MARK: - Toast [N1] Visibility of system status

    private func toastBar(_ msg: ToastMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: msg.icon)
                .foregroundStyle(msg.color)
                .font(.system(size: 11))
            Text(msg.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(msg.color.opacity(0.08))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Logic

    // [N5] Error prevention — disable unreachable hosts
    private func isItemDisabled(_ item: LauncherItem) -> Bool {
        if case .host(let h) = item, !h.reachable { return true }
        return false
    }

    // [N10] Contextual help via tooltips
    private func tooltipFor(_ item: LauncherItem) -> String {
        switch item {
        case .host(let h):
            return h.reachable
                ? "Press Enter to SSH to \(h.name)"
                : "\(h.name) is unreachable"
        case .session(let h, let s):
            return "Attach tmux session \(s.name) on \(h.name)"
        case .project(let p):
            return "Open \(p.repo ?? p.name) on GitHub"
        case .command(let label, _):
            return "Run: \(label)"
        }
    }

    private func executeSelected() {
        guard let item = flatResults[safe: selectedIndex] else { return }
        guard !isItemDisabled(item) else {
            // [N9] Error feedback for disabled items
            withAnimation { toast = ToastMessage(text: "Host unreachable", icon: "xmark.circle.fill", color: .red) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { toast = nil }
            }
            return
        }

        // [N1] Confirm action with toast
        let msg: String
        switch item {
        case .host(let h): msg = "Connecting to \(h.name)..."
        case .session(let h, let s): msg = "Attaching \(h.name):\(s.name)..."
        case .project(let p): msg = "Opening \(p.name)..."
        case .command(let label, _): msg = "Running \(label)..."
        }
        withAnimation(.easeIn(duration: 0.15)) {
            toast = ToastMessage(text: msg, icon: "checkmark.circle.fill", color: .green)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAction(item)
        }
    }

    private func jumpToNextCategory() {
        let flat = flatResults
        guard !flat.isEmpty else { return }
        let currentCat = flat[safe: selectedIndex]?.category ?? ""
        var foundCurrent = false
        for (i, item) in flat.enumerated() {
            if item.category == currentCat { foundCurrent = true }
            else if foundCurrent { selectedIndex = i; return }
        }
        selectedIndex = 0
    }
}

// MARK: - Row [N4] Consistency — same format for all item types

struct NielsenRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 0) {
            // [N4] Consistent icon treatment
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(isDisabled ? 0.05 : isSelected ? 0.2 : 0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDisabled ? .gray : iconColor)
            }
            .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isDisabled ? .white.opacity(0.3) : .white)
                    .lineLimit(1)
                    .strikethrough(isDisabled) // [N5] Visual signal for disabled

                Text(item.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(isDisabled ? 0.2 : 0.4))
                    .lineLimit(1)
            }

            Spacer()

            // [N6] Recognition — show what action will happen
            if isSelected && !isDisabled {
                Text(actionHint)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // [N5] Warning for disabled items
            if isDisabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.6))
            }

            // [N1] Inline status for hosts
            if case .host(let h) = item, !isDisabled {
                HStack(spacing: 8) {
                    metricPill("\(String(format: "%.0f", h.load))",
                               color: h.load > 4 ? .red : h.load > 2 ? .orange : .green)
                    metricPill("\(h.diskPercent)%",
                               color: h.diskPercent >= 85 ? .orange : .green)
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
        .opacity(isDisabled ? 0.6 : 1.0) // [N5] Dimmed disabled items
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
        case .host: "SSH"
        case .session: "ATTACH"
        case .project: "OPEN"
        case .command: "RUN"
        }
    }

    private var iconName: String {
        switch item {
        case .host: "server.rack"
        case .session: "terminal"
        case .project: "folder.fill"
        case .command: "command"
        }
    }

    private var iconColor: Color {
        switch item {
        case .host(let h): h.reachable ? .green : .red
        case .session(_, let s): s.attached ? .blue : .gray
        case .project(let p): p.perspective.color
        case .command: .orange
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
