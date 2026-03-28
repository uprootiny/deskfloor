import SwiftUI

// MARK: - Skein View (Cmd+5) — Conversation thread timeline
// Pure SwiftUI — no Canvas. 79 threads is fine without Canvas optimization.

struct SkeinView: View {
    @State var skein: SkeinStore
    @State var store: ProjectStore
    @State private var selectedThreadID: UUID?
    @State private var filterText = ""
    @State private var filterSource: Thread.Source?
    @State private var filterStatus: SessionStatus?
    @State private var showImport = false

    private var filteredThreads: [Thread] {
        skein.threads.filter { thread in
            if let source = filterSource, thread.source != source { return false }
            if let status = filterStatus, thread.status != status { return false }
            if !filterText.isEmpty {
                let q = filterText.lowercased()
                // Search thread metadata
                if thread.title.lowercased().contains(q) { return true }
                if thread.topics.contains(where: { $0.lowercased().contains(q) }) { return true }
                if thread.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
                // Search turn content (the important part)
                if thread.turns.contains(where: {
                    $0.userContent.lowercased().contains(q)
                    || ($0.assistantContent?.lowercased().contains(q) ?? false)
                }) { return true }
                return false
            }
            return true
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var grouped: [(Thread.Source, [Thread])] {
        let dict = Dictionary(grouping: filteredThreads, by: \.source)
        let order: [Thread.Source] = [.claudeCode, .claudeWeb, .chatGPT, .agentSlack, .manual]
        return order.compactMap { s in
            guard let t = dict[s], !t.isEmpty else { return nil }
            return (s, t)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.2)

            if skein.threads.isEmpty {
                emptyState
            } else {
                HSplitView {
                    threadList
                        .frame(minWidth: 300, idealWidth: 400)
                    detailPane
                        .frame(minWidth: 300)
                }
            }

            // Status footer
            statusFooter
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .task {
            // Auto-import Claude Code conversations on first appearance
            if skein.threads.isEmpty {
                importClaudeCode()
            }
        }
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
        let byStatus = Dictionary(grouping: skein.threads, by: \.status)
        return HStack(spacing: 12) {
            ForEach(SessionStatus.allCases) { status in
                let count = byStatus[status]?.count ?? 0
                if count > 0 {
                    Button(action: {
                        // Toggle filter: click to filter by this status, click again to clear
                        if filterStatus == status {
                            filterStatus = nil
                        } else {
                            filterStatus = status
                        }
                    }) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(status.color)
                                .frame(width: 5, height: 5)
                            Text("\(count) \(status.label.lowercased())")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(filterStatus == status ? .white.opacity(0.7) : .white.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            let stats = skein.stats
            Text("\(stats.turns) turns · \(stats.artifacts) artifacts · \(stats.excerpts) excerpts")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))

            TextField("Filter threads...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            Picker("Source", selection: $filterSource) {
                Text("All Sources").tag(nil as Thread.Source?)
                ForEach(Thread.Source.allCases, id: \.self) { s in
                    Label(s.label, systemImage: s.icon).tag(s as Thread.Source?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Picker("Status", selection: $filterStatus) {
                Text("All").tag(nil as SessionStatus?)
                ForEach(SessionStatus.allCases) { s in
                    Label(s.label, systemImage: s.icon).tag(s as SessionStatus?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            let stats = skein.stats
            Text("\(filteredThreads.count) threads · \(stats.turns) turns · \(stats.artifacts) artifacts")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))

            Button(action: { showImport.toggle() }) {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .popover(isPresented: $showImport) { importMenu }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // MARK: - Thread List (left pane)

    private var threadList: some View {
        List(selection: $selectedThreadID) {
            ForEach(grouped, id: \.0) { source, threads in
                Section {
                    ForEach(threads) { thread in
                        ThreadRow(thread: thread)
                            .tag(thread.id)
                            .contextMenu { threadContextMenu(thread) }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: source.icon)
                            .font(.system(size: 10))
                        Text(source.label)
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(threads.count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail Pane (right side)

    @ViewBuilder
    private var detailPane: some View {
        if let thread = skein.threads.first(where: { $0.id == selectedThreadID }) {
            ThreadDetailView(thread: thread, skein: skein)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.1))
                Text("Select a thread")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func threadContextMenu(_ thread: Thread) -> some View {
        Menu("Set Status") {
            ForEach(SessionStatus.allCases) { status in
                Button(action: { skein.setThreadStatus(thread.id, status) }) {
                    Label(status.label, systemImage: status.icon)
                }
            }
        }

        Divider()

        Button("Extract Prompts → Loom") {
            for turn in thread.turns where !turn.userContent.isEmpty {
                skein.extractExcerpt(
                    threadID: thread.id, turnID: turn.id,
                    content: turn.userContent, kind: .prompt, column: .prompts
                )
            }
        }

        Button("Extract Artifacts → Loom") {
            for turn in thread.turns {
                for artifact in turn.artifacts {
                    skein.extractExcerpt(
                        threadID: thread.id, turnID: turn.id,
                        content: artifact.content, kind: artifact.kind, column: .artifacts
                    )
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))

            Text("No conversation threads")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Button("Import Claude Code Conversations") { importClaudeCode() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.65, blue: 0.95).opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import

    private var importMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { importClaudeCode(); showImport = false }) {
                Label("Import Claude Code (local)", systemImage: "terminal")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(8)

            Button(action: {}) {
                Label("Import ChatGPT (select file)", systemImage: "doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(8)
            .disabled(true)
        }
        .padding(4)
        .frame(width: 260)
    }

    private func importClaudeCode() {
        Task {
            let threads = ClaudeCodeImporter.importAll()
            let existingIDs = Set(skein.threads.map(\.id))
            var added = 0
            for thread in threads where !existingIDs.contains(thread.id) {
                skein.addThread(thread)
                added += 1
            }
            NSLog("[SkeinView] Imported \(added) new threads")
        }
    }
}

// MARK: - Thread Row

struct ThreadRow: View {
    let thread: Thread

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Image(systemName: thread.status.icon)
                .font(.system(size: 10))
                .foregroundStyle(thread.status.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(thread.turns.count) turns")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))

                    if thread.toolLoopCount > 0 {
                        Text("\(thread.toolLoopCount) tools")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    if !thread.topics.isEmpty {
                        Text(thread.topics.prefix(3).joined(separator: ", "))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Time badge
            VStack(alignment: .trailing, spacing: 1) {
                Text(thread.updatedAt, style: .date)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                Text(thread.updatedAt, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Thread Detail View (right pane)

struct ThreadDetailView: View {
    let thread: Thread
    @State var skein: SkeinStore
    @State private var showOnlyBookmarked = false

    private var visibleTurns: [Turn] {
        if showOnlyBookmarked {
            return thread.turns.filter { $0.isBookmarked || $0.isBreakthrough || $0.isDeadEnd }
        }
        return thread.turns
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: thread.status.icon)
                    .foregroundStyle(thread.status.color)
                Text(thread.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Toggle("Bookmarked only", isOn: $showOnlyBookmarked)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Stats
            HStack(spacing: 12) {
                statPill(thread.source.label, color: .blue)
                statPill("\(thread.turns.count) turns", color: .white)
                statPill("\(thread.toolLoopCount) tools", color: .orange)
                statPill("\(thread.artifactCount) artifacts", color: .green)
                statPill(thread.status.label, color: thread.status.color)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if !thread.topics.isEmpty {
                HStack(spacing: 4) {
                    ForEach(thread.topics, id: \.self) { topic in
                        Text(topic)
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider().opacity(0.2)

            // Turns
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleTurns.enumerated()), id: \.1.id) { idx, turn in
                        TurnRow(
                            turn: turn,
                            index: idx,
                            threadID: thread.id,
                            skein: skein
                        )
                        Divider().opacity(0.06)
                    }
                }
            }
        }
    }

    private func statPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Turn Row

struct TurnRow: View {
    let turn: Turn
    let index: Int
    let threadID: UUID
    @State var skein: SkeinStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // User message
            HStack(alignment: .top, spacing: 8) {
                // Markers
                VStack(spacing: 2) {
                    Text("\(index + 1)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))

                    if turn.isBookmarked {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                    if turn.isDeadEnd {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                    if turn.isBreakthrough {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                    }
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    // User content
                    Text(turn.userContent)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled)

                    // Tool loops summary
                    if !turn.toolLoops.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(turn.toolLoops.prefix(6)) { loop in
                                Text(loop.toolName)
                                    .font(.system(size: 8, design: .monospaced))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.1))
                                    .foregroundStyle(.orange.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                            if turn.toolLoops.count > 6 {
                                Text("+\(turn.toolLoops.count - 6)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }

                    // Assistant response (collapsed by default)
                    if let assistant = turn.assistantContent, expanded {
                        Text(assistant)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .textSelection(.enabled)
                    }

                    // Artifacts
                    if !turn.artifacts.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(turn.artifacts.prefix(4)) { artifact in
                                Label(
                                    artifact.label ?? artifact.kind.rawValue,
                                    systemImage: artifact.kind.icon
                                )
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.08))
                                .foregroundStyle(.green.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 4) {
                    Button(action: { expanded.toggle() }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Collapse" : "Expand")

                    Button(action: { skein.bookmarkTurn(threadID: threadID, turnID: turn.id) }) {
                        Image(systemName: turn.isBookmarked ? "star.fill" : "star")
                            .font(.system(size: 9))
                            .foregroundStyle(turn.isBookmarked ? .yellow : .white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .help("Bookmark")

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(turn.userContent, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .help("Copy prompt")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            turn.isBreakthrough ? Color.green.opacity(0.03) :
            turn.isDeadEnd ? Color.red.opacity(0.03) :
            .clear
        )
    }
}
