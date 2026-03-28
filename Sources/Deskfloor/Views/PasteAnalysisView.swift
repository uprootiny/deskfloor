import SwiftUI
import AppKit
import NLPEngine

// MARK: - Loom: Paste Analysis + Excerpt Workshop

struct PasteAnalysisView: View {
    @State private var rawPaste = ""
    @State private var sections: [ParsedSection] = []
    @State private var isParsing = false
    @State private var filterKind: ParsedSection.Kind?
    @State private var filterThread: String?
    @State private var expandedSections: Set<UUID> = []
    @State private var composerPieces: [ComposerPiece] = []
    @State private var composerPrompt = ""
    @State private var showComposer = false
    @State private var sessionTitle = ""
    @State private var keywords: [(String, Int)] = []

    struct ComposerPiece: Identifiable {
        let id = UUID()
        let sectionID: UUID
        let kind: ParsedSection.Kind
        let content: String
        let title: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
            Divider().opacity(0.2)

            HSplitView {
                // Left: raw paste input
                inputPane
                    .frame(minWidth: 250, idealWidth: 300)

                // Center: analyzed sections
                analysisPane
                    .frame(minWidth: 350, idealWidth: 450)

                // Right: composer (when active)
                if showComposer {
                    composerPane
                        .frame(minWidth: 280, idealWidth: 320)
                }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Session title
            if !sections.isEmpty {
                TextField("Session title...", text: $sessionTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: 200)
            }

            // Keywords
            if !keywords.isEmpty {
                HStack(spacing: 4) {
                    ForEach(keywords.prefix(6), id: \.0) { kw, count in
                        Text(kw)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            // Stats
            if !sections.isEmpty {
                let selectedCount = sections.filter(\.isSelected).count
                let byKind = Dictionary(grouping: sections, by: \.kind)

                HStack(spacing: 8) {
                    ForEach(ParsedSection.Kind.allCases, id: \.self) { kind in
                        let count = byKind[kind]?.count ?? 0
                        if count > 0 {
                            Button(action: {
                                filterKind = filterKind == kind ? nil : kind
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: kind.icon)
                                        .font(.system(size: 8))
                                    Text("\(count)")
                                        .font(.system(size: 8, design: .monospaced))
                                }
                                .foregroundStyle(filterKind == kind ? kind.color : kind.color.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .help("\(kind.rawValue): \(count)")
                        }
                    }
                }

                // Thread filter pills
                let threads = Set(sections.map(\.inferredThread)).sorted()
                if threads.count > 1 {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.1))
                    ForEach(threads, id: \.self) { thread in
                        Button(action: {
                            filterThread = filterThread == thread ? nil : thread
                        }) {
                            Text(thread)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(filterThread == thread ? .white.opacity(0.8) : .white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedCount > 0 {
                    Text("\(selectedCount) sel")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }

            // Composer toggle
            Button(action: { showComposer.toggle() }) {
                Image(systemName: showComposer ? "sidebar.trailing" : "rectangle.rightthird.inset.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(showComposer ? 0.7 : 0.3))
            }
            .buttonStyle(.plain)
            .help("Toggle Composer panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // MARK: - Input Pane (left)

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INPUT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        rawPaste = text
                        analyze()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

                Button("Analyze") { analyze() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.7))
                    .controlSize(.small)
                    .disabled(rawPaste.isEmpty || isParsing)
            }
            .padding(8)

            TextEditor(text: $rawPaste)
                .font(.system(size: 10, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.02))
                .onKeyPress(keys: [.init("v")], phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            rawPaste = text
                            analyze()
                        }
                        return .handled
                    }
                    return .ignored
                }
        }
    }

    // MARK: - Analysis Pane (center)

    private var analysisPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SECTIONS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))

                Spacer()

                if !sections.isEmpty {
                    // Select all of filtered kind
                    Button("Select All") {
                        for i in sections.indices {
                            if filterKind == nil || sections[i].kind == filterKind {
                                sections[i].isSelected = true
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))

                    Button("Clear") {
                        for i in sections.indices { sections[i].isSelected = false }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))

                    Button("→ Composer") {
                        addSelectedToComposer()
                        showComposer = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.blue.opacity(0.7))
                    .disabled(sections.filter(\.isSelected).isEmpty)
                }
            }
            .padding(8)

            if isParsing {
                ProgressView("Analyzing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach($sections) { $section in
                            if (filterKind == nil || section.kind == filterKind)
                                && (filterThread == nil || section.inferredThread == filterThread) {
                                LoomSectionRow(
                                    section: $section,
                                    isExpanded: expandedSections.contains(section.id),
                                    onToggleExpand: {
                                        if expandedSections.contains(section.id) {
                                            expandedSections.remove(section.id)
                                        } else {
                                            expandedSections.insert(section.id)
                                        }
                                    },
                                    onAddToComposer: {
                                        composerPieces.append(ComposerPiece(
                                            sectionID: section.id,
                                            kind: section.kind,
                                            content: section.content,
                                            title: section.title
                                        ))
                                        showComposer = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.1))
            Text("Paste a session transcript")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text("Claude Code sessions, ChatGPT chats, agent logs, terminal output — anything.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer Pane (right)

    private var composerPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COMPOSER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text("~\(composerTokenEstimate) tokens")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(8)

            // Pieces
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(composerPieces) { piece in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: piece.kind.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(piece.kind.color.opacity(0.6))
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(piece.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(2)
                                Text("\(piece.content.count) chars")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.25))
                            }

                            Spacer()

                            Button(action: {
                                composerPieces.removeAll { $0.id == piece.id }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.1)

            // Prompt area
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR PROMPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                TextEditor(text: $composerPrompt)
                    .font(.system(size: 11))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(minHeight: 60, maxHeight: 120)
            }
            .padding(8)

            // Actions
            HStack(spacing: 8) {
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(composerFullText, forType: .string)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

                Button("Dispatch") {
                    DeskfloorApp.dispatchToAgent(context: composerFullText)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue.opacity(0.7))
                .controlSize(.small)
                .disabled(composerPieces.isEmpty && composerPrompt.isEmpty)

                Spacer()

                Button("Clear") {
                    composerPieces.removeAll()
                    composerPrompt = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
            }
            .padding(8)
            .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        }
    }

    private var composerFullText: String {
        var parts: [String] = []
        for piece in composerPieces {
            parts.append("## \(piece.kind.rawValue)\n\(piece.content)")
        }
        if !composerPrompt.isEmpty {
            parts.append("## Task\n\(composerPrompt)")
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    private var composerTokenEstimate: Int { composerFullText.count / 4 }

    // MARK: - Analysis

    private func analyze() {
        isParsing = true
        sections = []
        keywords = []

        let text = rawPaste
        Task.detached(priority: .userInitiated) {
            let parsed = Self.parseTranscript(text)

            // NLP keyword extraction from all content
            let analyzer = TextAnalyzer()
            let allText = parsed.map(\.content).joined(separator: " ")
            let kw = analyzer.extractKeywords(allText, topN: 10)

            // Auto-generate title from first prompt or first line
            let autoTitle = parsed.first(where: { $0.kind == .userPrompt })?.title
                ?? parsed.first?.title
                ?? "Untitled Session"

            await MainActor.run {
                sections = parsed
                keywords = kw
                sessionTitle = autoTitle
                isParsing = false
            }
        }
    }

    private func addSelectedToComposer() {
        for section in sections where section.isSelected {
            if !composerPieces.contains(where: { $0.sectionID == section.id }) {
                composerPieces.append(ComposerPiece(
                    sectionID: section.id,
                    kind: section.kind,
                    content: section.content,
                    title: section.title
                ))
            }
        }
    }

    // MARK: - Parser

    static func parseTranscript(_ text: String) -> [ParsedSection] {
        var sections: [ParsedSection] = []
        let lines = text.components(separatedBy: "\n")
        var currentLines: [String] = []
        var currentKind: ParsedSection.Kind = .other

        func flush() {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }

            let firstLine = content.components(separatedBy: "\n").first ?? content
            let title = firstLine.count > 80 ? String(firstLine.prefix(77)) + "..." : firstLine

            sections.append(ParsedSection(kind: currentKind, content: content, title: title))
            currentLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("❯ ") || trimmed.hasPrefix("⌂ ") {
                flush(); currentKind = .userPrompt
                currentLines.append(String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("⏺ Bash(") || trimmed.hasPrefix("⏺ Read(") ||
                       trimmed.hasPrefix("⏺ Write(") || trimmed.hasPrefix("⏺ Update(") ||
                       trimmed.hasPrefix("⏺ Explore(") || trimmed.hasPrefix("  ⎿") {
                if currentKind != .shellCommand { flush(); currentKind = .shellCommand }
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("⏺ Agent ") {
                flush(); currentKind = .agentResponse
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("⏺ ") {
                if currentKind != .agentResponse && currentKind != .reflection {
                    flush()
                    currentKind = trimmed.contains("What") && (trimmed.contains("shipped") || trimmed.contains("happened") || trimmed.contains("next"))
                        ? .reflection : .agentResponse
                }
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("```") {
                if currentKind == .codeBlock {
                    currentLines.append(trimmed); flush(); currentKind = .other
                } else {
                    flush(); currentKind = .codeBlock; currentLines.append(trimmed)
                }
            } else if trimmed.contains("git commit") || trimmed.hasPrefix("[main ") || trimmed.hasPrefix("[master ") || trimmed.hasPrefix("[skein ") {
                flush(); currentKind = .gitCommit; currentLines.append(trimmed)
            } else if trimmed.contains("completed") && (trimmed.contains("success") || trimmed.contains("failure")) {
                flush(); currentKind = .ciStatus; currentLines.append(trimmed)
            } else if trimmed.hasPrefix("┌") || trimmed.hasPrefix("├") || trimmed.hasPrefix("│") || trimmed.hasPrefix("└") {
                if currentKind != .table { flush(); currentKind = .table }
                currentLines.append(trimmed)
            } else if (trimmed.lowercased().contains("error:") || trimmed.contains("FAIL") || trimmed.contains("fatal:")) && currentKind != .codeBlock {
                if currentKind != .error { flush(); currentKind = .error }
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("✻ ") {
                flush(); currentKind = .reflection; currentLines.append(trimmed)
            } else {
                currentLines.append(line)
            }
        }
        flush()

        // Post-process: infer thread context for each section
        var currentThread = "main"
        for i in sections.indices {
            let content = sections[i].content.lowercased()
            // Detect SSH/host context switches
            if content.contains("ssh") && content.contains("nabla") || content.contains("35.252") {
                currentThread = "nabla"
            } else if content.contains("ssh") && content.contains("finml") || content.contains("5.189") || content.contains("helix-lab") {
                currentThread = "finml"
            } else if content.contains("ssh") && content.contains("gcp1") || content.contains("35.225") {
                currentThread = "gcp1"
            } else if content.contains("ssh") && content.contains("hyle") || content.contains("173.212") {
                currentThread = "hyle"
            } else if content.contains("gemini") && (content.contains("session") || content.contains("tmux send")) {
                currentThread = "nabla:gemini"
            } else if content.contains("deskfloor") || content.contains("swift build") || content.contains("contentview") {
                currentThread = "deskfloor"
            } else if content.contains("bespokesynth") || content.contains("juce") || content.contains("nanovg") {
                currentThread = "bespokesynth"
            }
            sections[i].inferredThread = currentThread
        }

        return sections
    }
}

// MARK: - Section Row (expanded/collapsed)

struct LoomSectionRow: View {
    @Binding var section: ParsedSection
    let isExpanded: Bool
    var onToggleExpand: () -> Void
    var onAddToComposer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 6) {
                // Checkbox
                Button(action: { section.isSelected.toggle() }) {
                    Image(systemName: section.isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(section.isSelected ? .blue : .white.opacity(0.25))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                // Kind badge
                HStack(spacing: 2) {
                    Image(systemName: section.kind.icon)
                        .font(.system(size: 8))
                    Text(section.kind.rawValue)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(section.kind.color.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(section.kind.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))

                // Thread badge
                if section.inferredThread != "main" {
                    Text(section.inferredThread)
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                // Title / content preview
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(isExpanded ? nil : 1)

                    if !isExpanded {
                        Text("\(section.content.components(separatedBy: "\n").count) lines · \(section.content.count) chars")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    Button(action: onAddToComposer) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .help("Add to Composer")

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(section.content, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // Expanded content
            if isExpanded {
                Text(section.content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.015))
            }
        }
        .background(section.isSelected ? Color.blue.opacity(0.04) : .clear)
    }
}

// MARK: - ParsedSection type (shared)

struct ParsedSection: Identifiable {
    let id = UUID()
    var kind: Kind
    var content: String
    var title: String
    var isSelected = false
    var inferredThread: String = "main"

    enum Kind: String, CaseIterable, Hashable {
        case userPrompt = "Prompt"
        case agentResponse = "Response"
        case codeBlock = "Code"
        case shellCommand = "Command"
        case gitCommit = "Commit"
        case ciStatus = "CI"
        case reflection = "Reflection"
        case table = "Table"
        case error = "Error"
        case other = "Other"

        var icon: String {
            switch self {
            case .userPrompt: "text.quote"
            case .agentResponse: "bubble.left"
            case .codeBlock: "chevron.left.forwardslash.chevron.right"
            case .shellCommand: "terminal"
            case .gitCommit: "arrow.triangle.branch"
            case .ciStatus: "checkmark.circle"
            case .reflection: "lightbulb"
            case .table: "tablecells"
            case .error: "exclamationmark.triangle"
            case .other: "doc.text"
            }
        }

        var color: Color {
            switch self {
            case .userPrompt: .blue
            case .agentResponse: .white
            case .codeBlock: .green
            case .shellCommand: .orange
            case .gitCommit: .purple
            case .ciStatus: .teal
            case .reflection: .yellow
            case .table: .cyan
            case .error: .red
            case .other: .gray
            }
        }
    }
}
