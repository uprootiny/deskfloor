import SwiftUI

// MARK: - Launcher Panel
//
// Skeuomorphic: frosted-glass panel with depth, beveled search field, tactile keycaps.
// Epistemic: results encode provenance (host/session/project/prompt) via icon+color;
//            disabled items show *why* with strikethrough + warning; toasts confirm actions.
// Compositional: grouped results with category headers, consistent row rhythm, footer hints.
// Nielsen heuristics: [N1]–[N10] preserved and enhanced.

struct LauncherPanelView: View {
    @Environment(\.colorScheme) private var scheme
    @State var store: ProjectStore
    @State var fleet: FleetStore
    @State var promptStore: PromptStore
    @State var historyStore: HistoryStore
    @State var sessionRegistry: SessionRegistry = SessionRegistry()
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var toast: ToastMessage?
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "launcherUsed")
    @FocusState private var searchFocused: Bool

    var onDismiss: () -> Void
    var onAction: (LauncherItem) -> Void
    /// Variant action for project items — caller decides how to open Claude.
    var onProjectAction: ((Project, DeskfloorApp.ClaudeOpenMode) -> Void)?

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

        let topPrompts = promptStore.prompts
            .sorted { $0.useCount > $1.useCount }
            .prefix(15)
        for prompt in topPrompts {
            items.append(.prompt(prompt))
        }

        let visible = store.projects
            .filter { $0.status != .archived }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        for project in visible.prefix(50) {
            items.append(.project(project))
        }

        for cmd in historyStore.commands.prefix(20) {
            items.append(.historyCommand(cmd))
        }

        for preset in WindowTiling.Preset.allCases {
            items.append(.tile(preset))
        }

        return items
    }

    private var results: [LauncherItem] { searcher.search(query: query, items: allItems) }
    private var flatResults: [LauncherItem] { results }
    private var grouped: [(String, [LauncherItem])] {
        let dict = Dictionary(grouping: results, by: \.category)
        return ["Hosts", "Sessions", "Prompts", "Projects", "History", "Commands", "Tile"].compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)

            if isFirstLaunch && query.isEmpty {
                welcomeState
            } else if flatResults.isEmpty && !query.isEmpty {
                errorRecoveryState
            } else {
                resultsList
            }

            if let toast {
                toastBar(toast)
            } else {
                footerBar
            }
        }
        .frame(width: 640)
        .background(
            ZStack {
                // Layered background: material + subtle gradient for depth
                RoundedRectangle(cornerRadius: Df.radiusLarge)
                    .fill(.ultraThickMaterial)
                RoundedRectangle(cornerRadius: Df.radiusLarge)
                    .fill(
                        LinearGradient(
                            colors: [
                                Df.surface(scheme).opacity(0.3),
                                Df.canvas(scheme).opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Df.radiusLarge))
        .overlay(
            // Skeuomorphic bevel — top highlight, bottom shadow
            RoundedRectangle(cornerRadius: Df.radiusLarge)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Df.bevelHighlight(scheme),
                            .clear,
                            Df.bevelShadow(scheme).opacity(0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.2), radius: 40, y: 16)
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.1), radius: 8, y: 4)
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
        .onKeyPress(.return, phases: .down) { press in
            // ⌘↵ = fresh claude session for the selected project (alternate action).
            // Plain ↵ falls through to the existing onSubmit on the search field.
            if press.modifiers.contains(.command),
               let item = flatResults[safe: selectedIndex],
               case .project(let p) = item {
                triggerProject(p, mode: .fresh)
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Df.space3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Df.textTertiary(scheme))

            TextField("", text: $query, prompt: Text("Jump to...").foregroundStyle(Df.textQuaternary(scheme)))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Df.textPrimary(scheme))
                .focused($searchFocused)
                .onSubmit { executeSelected() }

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Df.textQuaternary(scheme))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            // Live result count
            Text("\(flatResults.count)")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textTertiary(scheme).opacity(query.isEmpty ? 0.5 : 1.0))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Df.inset(scheme))
                .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))

            // Fleet status dot
            DfStatusDot(
                color: fleet.isReachable ? Df.certain : Df.critical,
                isLive: fleet.isReachable
            )
            .help(fleet.isReachable ? "Fleet connected" : "Fleet offline")
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space4)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(grouped.enumerated()), id: \.0) { _, group in
                        let (category, items) = group
                        DfSectionHeader(title: category, count: items.count)
                            .padding(.horizontal, Df.space5)
                            .padding(.top, Df.space3)
                            .padding(.bottom, Df.space1)

                        ForEach(items) { item in
                            let idx = flatResults.firstIndex(where: { $0.id == item.id }) ?? 0
                            LauncherRow(
                                item: item,
                                isSelected: idx == selectedIndex,
                                isDisabled: isItemDisabled(item),
                                scheme: scheme,
                                sessionCount: sessionCountFor(item)
                            )
                            .id(item.id)
                            .onTapGesture {
                                guard !isItemDisabled(item) else { return }
                                selectedIndex = idx
                                executeSelected()
                            }
                            .contextMenu { rowMenu(for: item) }
                            .help(tooltipFor(item))
                        }
                    }
                }
                .padding(.vertical, Df.space1)
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

    // MARK: - Welcome State

    private var welcomeState: some View {
        VStack(spacing: Df.space3) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Df.textQuaternary(scheme))

            Text("Deskfloor Launcher")
                .font(Df.titleFont)
                .foregroundStyle(Df.textSecondary(scheme))

            VStack(alignment: .leading, spacing: Df.space2) {
                hintRow("Type a project name", "↵ resumes latest claude session")
                hintRow("⌘↵", "opens a fresh claude session instead")
                hintRow("Right-click a project", "for session picker / primer / repo")
                hintRow("Type a host name", "↵ to SSH (Ghostty / iTerm / Terminal)")
                hintRow("Press Tab", "to jump between groups")
                hintRow("⌥⌘L from anywhere", "engineers the launcher itself")
            }
            .padding(.horizontal, 40)

            Button("Got it") {
                UserDefaults.standard.set(true, forKey: "launcherUsed")
                isFirstLaunch = false
            }
            .buttonStyle(.plain)
            .font(Df.captionFont)
            .foregroundStyle(Df.textTertiary(scheme))
            .padding(.horizontal, Df.space3)
            .padding(.vertical, Df.space1)
            .background(Df.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func hintRow(_ action: String, _ result: String) -> some View {
        HStack(spacing: 4) {
            Text(action)
                .font(Df.captionFont)
                .foregroundStyle(Df.textSecondary(scheme))
            Text(result)
                .font(.system(size: 11))
                .foregroundStyle(Df.textTertiary(scheme))
        }
    }

    // MARK: - Error Recovery

    private var errorRecoveryState: some View {
        VStack(spacing: Df.space3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Df.textQuaternary(scheme))

            Text("No results for \"\(query)\"")
                .font(Df.bodyFont)
                .foregroundStyle(Df.textTertiary(scheme))

            VStack(spacing: 6) {
                if query.count > 3 {
                    Button("Try \"\(String(query.prefix(3)))\"") {
                        query = String(query.prefix(3))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Df.info)
                }

                Button("Clear and browse all") {
                    query = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Df.info)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 0) {
            DfKeycap(key: "Enter", label: actionLabelForSelected)
                .padding(.trailing, Df.space3)
            DfKeycap(key: "Tab", label: "next group")
                .padding(.trailing, Df.space3)
            DfKeycap(key: "Esc", label: "close")
            Spacer()
            if let update = fleet.lastUpdate {
                Text(update, style: .relative)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space2)
        .background(Df.canvas(scheme).opacity(0.5))
    }

    private var actionLabelForSelected: String {
        guard let item = flatResults[safe: selectedIndex] else { return "open" }
        switch item {
        case .host: return "ssh"
        case .session: return "attach"
        case .project(let p): return p.localPath != nil ? "claude" : "open"
        case .command: return "run"
        case .prompt: return "copy"
        case .historyCommand: return "run"
        case .tile: return "tile"
        }
    }

    // MARK: - Toast

    private func toastBar(_ msg: ToastMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: msg.icon)
                .foregroundStyle(msg.color)
                .font(.system(size: 11))
            Text(msg.text)
                .font(Df.captionFont)
                .foregroundStyle(Df.textSecondary(scheme))
            Spacer()
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space2)
        .background(msg.color.opacity(scheme == .dark ? 0.08 : 0.06))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Logic

    private func isItemDisabled(_ item: LauncherItem) -> Bool {
        if case .host(let h) = item, !h.reachable { return true }
        return false
    }

    private func tooltipFor(_ item: LauncherItem) -> String {
        switch item {
        case .host(let h):
            return h.reachable
                ? "Press Enter to SSH to \(h.name)"
                : "\(h.name) is unreachable"
        case .session(let h, let s):
            return "Attach tmux session \(s.name) on \(h.name)"
        case .project(let p):
            if p.localPath != nil {
                return "Open Claude session in \(p.name)"
            }
            return "Open \(p.repo ?? p.name) on GitHub"
        case .command(let label, _):
            return "Run: \(label)"
        case .prompt(let p):
            return "Copy prompt: \(p.title)"
        case .historyCommand(let h):
            return "Run in terminal: \(h.command)"
        case .tile(let preset):
            return "Apply \(preset.label) to focused window (needs Accessibility permission)"
        }
    }

    private func executeSelected() {
        guard let item = flatResults[safe: selectedIndex] else { return }
        guard !isItemDisabled(item) else {
            withAnimation { toast = ToastMessage(text: "Host unreachable", icon: "xmark.circle.fill", color: Df.critical) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { toast = nil }
            }
            return
        }

        let msg: String
        switch item {
        case .host(let h): msg = "Connecting to \(h.name)..."
        case .session(let h, let s): msg = "Attaching \(h.name):\(s.name)..."
        case .project(let p): msg = "Claude session: \(p.name)..."
        case .command(let label, _): msg = "Running \(label)..."
        case .prompt(let p): msg = "Copied: \(p.title)"
        case .historyCommand(let h):
            let short = h.command.count > 30 ? String(h.command.prefix(30)) + "..." : h.command
            msg = "Running \(short)..."
        case .tile(let preset): msg = preset.label
        }
        withAnimation(.easeIn(duration: 0.15)) {
            toast = ToastMessage(text: msg, icon: "checkmark.circle.fill", color: Df.certain)
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

    // MARK: - Session-aware row context menu

    private func sessionCountFor(_ item: LauncherItem) -> Int {
        if case .project(let p) = item { return sessionRegistry.sessions(for: p).count }
        return 0
    }

    @ViewBuilder
    private func rowMenu(for item: LauncherItem) -> some View {
        if case .project(let p) = item {
            let sessions = sessionRegistry.sessions(for: p)
            if let recent = sessions.first {
                Button("Resume latest — \(recent.displayLabel)") {
                    triggerProject(p, mode: .resumeSpecific(uuid: recent.uuid))
                }
            }
            if sessions.count > 1 {
                Menu("Pick a session… (\(sessions.count))") {
                    ForEach(sessions.prefix(20)) { s in
                        Button(s.displayLabel) {
                            triggerProject(p, mode: .resumeSpecific(uuid: s.uuid))
                        }
                    }
                    if sessions.count > 20 {
                        Divider()
                        Text("\(sessions.count - 20) older not shown")
                    }
                }
            }
            Divider()
            Button("Fresh Claude session  ⌘↵") {
                triggerProject(p, mode: .fresh)
            }
            if let primer = primerPath(for: p) {
                Button("Fresh with primer (\((primer as NSString).lastPathComponent))") {
                    triggerProject(p, mode: .freshWithPrimer(path: primer))
                }
            }
            Divider()
            if let repo = p.repo {
                Button("Open \(repo) on GitHub") {
                    if let url = URL(string: "https://github.com/\(repo)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let path = p.localPath {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
        } else {
            Button("Run") { onAction(item) }
        }
    }

    private func triggerProject(_ p: Project, mode: DeskfloorApp.ClaudeOpenMode) {
        if let onProjectAction {
            onProjectAction(p, mode)
        } else {
            DeskfloorApp.openClaudeForProject(p, registry: sessionRegistry, mode: mode)
        }
        onDismiss()
    }

    private func primerPath(for p: Project) -> String? {
        guard let path = p.localPath else { return nil }
        let candidates = ["PLAN.md", "DEVNOTES.md", "README.md"]
        let fm = FileManager.default
        for name in candidates {
            let full = (path as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: full) { return full }
        }
        return nil
    }

    private func relativeAge(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86400: return "\(Int(s / 3600))h ago"
        case ..<604800: return "\(Int(s / 86400))d ago"
        default: return "\(Int(s / 604800))w ago"
        }
    }
}

// MARK: - Launcher Row

struct LauncherRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let isDisabled: Bool
    let scheme: ColorScheme
    var sessionCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            // Icon badge — shape encodes provenance
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(isDisabled ? 0.05 : isSelected ? 0.2 : 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                iconColor.opacity(isSelected && !isDisabled ? 0.3 : 0),
                                lineWidth: 1
                            )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDisabled ? Df.textQuaternary(scheme) : iconColor)
            }
            .padding(.trailing, Df.space3)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(isSelected ? Df.headlineFont : Df.bodyFont)
                    .foregroundStyle(
                        isDisabled
                            ? Df.textTertiary(scheme)
                            : Df.textPrimary(scheme)
                    )
                    .lineLimit(1)
                    .strikethrough(isDisabled)

                Text(item.subtitle)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(
                        isDisabled
                            ? Df.textQuaternary(scheme)
                            : Df.textTertiary(scheme)
                    )
                    .lineLimit(1)
            }

            Spacer()

            // Session-count badge (projects with prior claude transcripts)
            if sessionCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 9))
                    Text("\(sessionCount)")
                        .font(Df.monoSmallFont)
                }
                .foregroundStyle(Df.agent.opacity(isSelected ? 1.0 : 0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Df.agent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
                .help("\(sessionCount) Claude session\(sessionCount == 1 ? "" : "s") — right-click to pick")
            }

            // Action hint — what Enter will do
            if isSelected && !isDisabled {
                Text(actionHint)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textTertiary(scheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Df.inset(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
            }

            if isDisabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Df.uncertain.opacity(0.7))
            }

            // Host metrics — epistemic: live data inline
            if case .host(let h) = item, !isDisabled {
                HStack(spacing: Df.space2) {
                    DfPill(
                        text: String(format: "%.0f", h.load),
                        color: h.load > 4 ? Df.critical : h.load > 2 ? Df.uncertain : Df.certain
                    )
                    DfPill(
                        text: "\(h.diskPercent)%",
                        color: h.diskPercent >= 85 ? Df.uncertain : Df.certain
                    )
                    if h.claudeCount > 0 {
                        DfPill(text: "\(h.claudeCount)cl", color: Df.agent)
                    }
                }
            }
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: Df.radiusSmall + 2)
                    .fill(Df.elevated(scheme).opacity(0.8))
                    .shadow(color: Df.bevelShadow(scheme).opacity(0.2), radius: 2, y: 1)
                : nil
        )
        .contentShape(Rectangle())
        .opacity(isDisabled ? 0.6 : 1.0)
    }

    private var actionHint: String {
        switch item {
        case .host: "SSH"
        case .session: "ATTACH"
        case .project(let p): p.localPath != nil ? "CLAUDE" : "OPEN"
        case .command: "RUN"
        case .prompt: "COPY"
        case .historyCommand: "RUN"
        case .tile: "TILE"
        }
    }

    private var iconName: String {
        switch item {
        case .host: "server.rack"
        case .session: "terminal"
        case .project: "folder.fill"
        case .command: "command"
        case .prompt: "text.quote"
        case .historyCommand: "clock.arrow.circlepath"
        case .tile: "rectangle.split.2x1"
        }
    }

    private var iconColor: Color {
        switch item {
        case .host(let h): h.reachable ? Df.certain : Df.critical
        case .session(_, let s): s.attached ? Df.info : Df.textTertiary(scheme)
        case .project(let p): p.perspective.color
        case .command: Df.uncertain
        case .prompt: Df.agent
        case .historyCommand: Color(red: 0.3, green: 0.7, blue: 0.8)
        case .tile: Df.info
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
