import SwiftUI
import AppKit
import NLPEngine

/// Paste a session transcript → auto-analyzed into sections, artifacts, actionables.
struct PasteAnalysisView: View {
    @State private var rawPaste = ""
    @State private var sections: [ParsedSection] = []
    @State private var isParsing = false

    struct ParsedSection: Identifiable {
        let id = UUID()
        var kind: Kind
        var content: String
        var title: String
        var isSelected = false

        enum Kind: String, CaseIterable {
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
                case .userPrompt: return "text.quote"
                case .agentResponse: return "bubble.left"
                case .codeBlock: return "chevron.left.forwardslash.chevron.right"
                case .shellCommand: return "terminal"
                case .gitCommit: return "arrow.triangle.branch"
                case .ciStatus: return "checkmark.circle"
                case .reflection: return "lightbulb"
                case .table: return "tablecells"
                case .error: return "exclamationmark.triangle"
                case .other: return "doc.text"
                }
            }

            var color: Color {
                switch self {
                case .userPrompt: return .blue
                case .agentResponse: return .white
                case .codeBlock: return .green
                case .shellCommand: return .orange
                case .gitCommit: return .purple
                case .ciStatus: return .teal
                case .reflection: return .yellow
                case .table: return .cyan
                case .error: return .red
                case .other: return .gray
                }
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left: paste input
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PASTE SESSION TRANSCRIPT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                    Button("Paste from Clipboard") {
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
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.03))
            }
            .frame(minWidth: 300)

            // Right: analyzed sections
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("ANALYZED SECTIONS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))

                    Spacer()

                    let selectedCount = sections.filter(\.isSelected).count
                    if selectedCount > 0 {
                        Text("\(selectedCount) selected")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.blue.opacity(0.7))

                        Button("Copy Selected") { copySelected() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(.blue.opacity(0.7))

                        Button("Dispatch Selected") { dispatchSelected() }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue.opacity(0.7))
                            .controlSize(.small)
                    }

                    if !sections.isEmpty {
                        Text("\(sections.count) sections")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(8)

                if isParsing {
                    ProgressView("Analyzing...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("Paste a session transcript and click Analyze")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach($sections) { $section in
                            SectionRow(section: $section)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 400)
        }
    }

    // MARK: - Analysis

    private func analyze() {
        isParsing = true
        sections = []

        Task.detached(priority: .userInitiated) {
            let parsed = Self.parseTranscript(rawPaste)
            await MainActor.run {
                sections = parsed
                isParsing = false
            }
        }
    }

    static func parseTranscript(_ text: String) -> [ParsedSection] {
        var sections: [ParsedSection] = []
        let lines = text.components(separatedBy: "\n")
        var currentLines: [String] = []
        var currentKind: ParsedSection.Kind = .other

        func flush() {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }

            let title: String
            let firstLine = content.components(separatedBy: "\n").first ?? content
            if firstLine.count > 80 {
                title = String(firstLine.prefix(77)) + "..."
            } else {
                title = firstLine
            }

            sections.append(ParsedSection(kind: currentKind, content: content, title: title))
            currentLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section boundaries
            if trimmed.hasPrefix("❯ ") || trimmed.hasPrefix("⌂ ") {
                flush()
                currentKind = .userPrompt
                currentLines.append(String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("⏺ Bash(") || trimmed.hasPrefix("⏺ Read(") ||
                       trimmed.hasPrefix("⏺ Write(") || trimmed.hasPrefix("⏺ Update(") ||
                       trimmed.hasPrefix("⏺ Explore(") {
                flush()
                currentKind = .shellCommand
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("⏺ Agent ") {
                flush()
                currentKind = .agentResponse
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("⏺ ") {
                // Agent narrative text
                if currentKind != .agentResponse && currentKind != .reflection {
                    flush()
                    // Check if it's a reflection
                    if trimmed.contains("What") && (trimmed.contains("shipped") || trimmed.contains("happened") || trimmed.contains("next")) {
                        currentKind = .reflection
                    } else {
                        currentKind = .agentResponse
                    }
                }
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("```") {
                if currentKind == .codeBlock {
                    currentLines.append(trimmed)
                    flush()
                    currentKind = .other
                } else {
                    flush()
                    currentKind = .codeBlock
                    currentLines.append(trimmed)
                }
            } else if trimmed.contains("git commit") || trimmed.contains("git add") ||
                       trimmed.hasPrefix("[main ") || trimmed.hasPrefix("[master ") {
                flush()
                currentKind = .gitCommit
                currentLines.append(trimmed)
            } else if trimmed.contains("completed") && (trimmed.contains("success") || trimmed.contains("failure")) {
                flush()
                currentKind = .ciStatus
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("┌") || trimmed.hasPrefix("├") || trimmed.hasPrefix("│") || trimmed.hasPrefix("└") {
                if currentKind != .table {
                    flush()
                    currentKind = .table
                }
                currentLines.append(trimmed)
            } else if trimmed.lowercased().contains("error") || trimmed.contains("failed") || trimmed.contains("FAIL") {
                if currentKind != .error {
                    flush()
                    currentKind = .error
                }
                currentLines.append(trimmed)
            } else if trimmed.hasPrefix("✻ ") {
                flush()
                currentKind = .reflection
                currentLines.append(trimmed)
            } else {
                currentLines.append(line)
            }
        }
        flush()

        return sections
    }

    private func copySelected() {
        let text = sections.filter(\.isSelected).map(\.content).joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func dispatchSelected() {
        let context = sections.filter(\.isSelected).map { section in
            "## \(section.kind.rawValue)\n\(section.content)"
        }.joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context, forType: .string)
        DeskfloorApp.openInITerm("claude")
    }
}

// MARK: - Section Row

struct SectionRow: View {
    @Binding var section: PasteAnalysisView.ParsedSection

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Select checkbox
            Button(action: { section.isSelected.toggle() }) {
                Image(systemName: section.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(section.isSelected ? .blue : .white.opacity(0.3))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)

            // Kind badge
            HStack(spacing: 3) {
                Image(systemName: section.kind.icon)
                    .font(.system(size: 9))
                Text(section.kind.rawValue)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(section.kind.color.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(section.kind.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(width: 80)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Text("\(section.content.count) chars · \(section.content.components(separatedBy: "\n").count) lines")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            // Copy button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(section.content, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Copy this section")
        }
        .padding(.vertical, 4)
        .background(section.isSelected ? Color.blue.opacity(0.05) : .clear)
    }
}
