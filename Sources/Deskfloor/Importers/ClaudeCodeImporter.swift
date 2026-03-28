import Foundation
import NLPEngine

/// Imports conversation threads from local Claude Code storage (~/.claude/).
enum ClaudeCodeImporter {

    /// Import all conversations from Claude Code's local storage.
    static func importAll(basePath: String = "~/.claude") -> [Thread] {
        let base = NSString(string: basePath).expandingTildeInPath
        let fm = FileManager.default
        var threads: [Thread] = []

        // Find all project directories
        let projectsDir = (base as NSString).appendingPathComponent("projects")
        guard let projectEnumerator = fm.enumerator(atPath: projectsDir) else { return threads }

        var jsonlFiles: [String] = []
        while let file = projectEnumerator.nextObject() as? String {
            if file.hasSuffix(".jsonl") && !file.contains("subagents") {
                jsonlFiles.append((projectsDir as NSString).appendingPathComponent(file))
            }
        }

        // Also find subagent files
        var subagentFiles: [String] = []
        let subagentEnumerator = fm.enumerator(atPath: projectsDir)
        while let file = subagentEnumerator?.nextObject() as? String {
            if file.hasSuffix(".jsonl") && file.contains("subagents") {
                subagentFiles.append((projectsDir as NSString).appendingPathComponent(file))
            }
        }

        // Import main conversations
        for path in jsonlFiles {
            if let thread = parseConversationJSONL(path: path, isSubagent: false) {
                threads.append(thread)
            }
        }

        // Import subagent conversations
        for path in subagentFiles {
            if let thread = parseConversationJSONL(path: path, isSubagent: true) {
                threads.append(thread)
            }
        }

        NSLog("[ClaudeCodeImporter] Imported \(threads.count) threads (\(jsonlFiles.count) main, \(subagentFiles.count) subagent)")
        return threads
    }

    /// Parse a single JSONL conversation file into a Thread.
    private static func parseConversationJSONL(path: String, isSubagent: Bool) -> Thread? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var turns: [Turn] = []
        var pendingUserContent: String?
        var pendingTimestamp: Date?
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var sessionTitle: String?

        let analyzer = TextAnalyzer()

        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            let msgType = msg["type"] as? String ?? ""
            let timestamp = (msg["timestamp"] as? String).flatMap { parseTimestamp($0) }

            if let ts = timestamp {
                if firstTimestamp == nil { firstTimestamp = ts }
                lastTimestamp = ts
            }

            // Extract message content
            let message = msg["message"] as? [String: Any]
            let role = message?["role"] as? String ?? msgType
            let messageContent = extractContent(from: message)

            if role == "user" || msgType == "user" {
                // If we had a pending user message without a response, save it anyway
                if let pending = pendingUserContent {
                    turns.append(Turn(userContent: pending, timestamp: pendingTimestamp))
                }
                pendingUserContent = messageContent
                pendingTimestamp = timestamp

                // Use first user message as title
                if sessionTitle == nil, !messageContent.isEmpty {
                    sessionTitle = String(messageContent.prefix(80))
                }
            } else if role == "assistant" || msgType == "assistant" {
                let userContent = pendingUserContent ?? ""
                var turn = Turn(
                    userContent: userContent,
                    assistantContent: messageContent.isEmpty ? nil : messageContent,
                    timestamp: pendingTimestamp ?? timestamp
                )

                // Extract tool loops from assistant content blocks
                if let contentBlocks = message?["content"] as? [[String: Any]] {
                    turn.toolLoops = extractToolLoops(from: contentBlocks)
                }

                // Auto-detect artifacts
                turn.artifacts = detectArtifacts(userContent: userContent,
                                                  assistantContent: messageContent,
                                                  analyzer: analyzer)

                turns.append(turn)
                pendingUserContent = nil
                pendingTimestamp = nil
            }
        }

        // Save any trailing user message
        if let pending = pendingUserContent {
            turns.append(Turn(userContent: pending, timestamp: pendingTimestamp))
        }

        guard !turns.isEmpty else { return nil }

        // Extract session ID from path for deduplication
        let filename = (path as NSString).lastPathComponent
        let sessionID = filename.replacingOccurrences(of: ".jsonl", with: "")

        // Auto-detect topics from all user messages
        let allUserText = turns.map(\.userContent).joined(separator: " ")
        let keywords = analyzer.extractKeywords(allUserText, topN: 5)
        let topics = keywords.map(\.0)

        return Thread(
            id: UUID(uuidString: sessionID) ?? UUID(),
            source: .claudeCode,
            title: sessionTitle ?? filename,
            createdAt: firstTimestamp ?? Date(),
            updatedAt: lastTimestamp ?? Date(),
            turns: turns,
            status: guessStatus(turns: turns, lastTimestamp: lastTimestamp),
            tags: isSubagent ? ["subagent"] : [],
            topics: topics,
            projectLinks: [],
            color: nil
        )
    }

    // MARK: - Helpers

    private static func extractContent(from message: [String: Any]?) -> String {
        guard let message else { return "" }

        // String content
        if let s = message["content"] as? String { return s }

        // Array of content blocks (Anthropic format)
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        }

        // display field (from history.jsonl)
        if let display = message["display"] as? String { return display }

        return ""
    }

    private static func extractToolLoops(from blocks: [[String: Any]]) -> [ToolLoop] {
        var loops: [ToolLoop] = []
        for block in blocks {
            guard block["type"] as? String == "tool_use" else { continue }
            let toolName = block["name"] as? String ?? "unknown"
            let input = block["input"] as? [String: Any]
            let inputStr = (input?["command"] as? String)
                ?? (input?["pattern"] as? String)
                ?? (input?["file_path"] as? String)
                ?? String(describing: input ?? [:]).prefix(200).description

            loops.append(ToolLoop(
                toolName: toolName,
                input: String(inputStr.prefix(500)),
                output: "", // Tool results are in separate messages
                succeeded: true
            ))
        }
        return loops
    }

    private static func detectArtifacts(userContent: String, assistantContent: String,
                                          analyzer: TextAnalyzer) -> [Artifact] {
        var artifacts: [Artifact] = []

        // Detect code blocks in assistant content
        if let codeRegex = try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: []) {
            let range = NSRange(assistantContent.startIndex..., in: assistantContent)
            for match in codeRegex.matches(in: assistantContent, range: range) {
                if let langRange = Range(match.range(at: 1), in: assistantContent),
                   let codeRange = Range(match.range(at: 2), in: assistantContent) {
                    let lang = String(assistantContent[langRange])
                    let code = String(assistantContent[codeRange])
                    if code.count > 20 {
                        artifacts.append(Artifact(kind: .code, content: code, language: lang.isEmpty ? nil : lang))
                    }
                }
            }
        }

        // Detect if user message is a reusable prompt
        if analyzer.isPrompt(userContent) && userContent.count > 50 {
            artifacts.append(Artifact(kind: .prompt, content: userContent))
        }

        // Detect commands (lines starting with $)
        for line in assistantContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("$ ") {
                let cmd = String(trimmed.dropFirst(2))
                artifacts.append(Artifact(kind: .command, content: cmd))
            }
        }

        return artifacts
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        let formatters = [
            ISO8601DateFormatter(),
            { () -> ISO8601DateFormatter in
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }()
        ]
        for fmt in formatters {
            if let date = fmt.date(from: s) { return date }
        }
        return nil
    }

    private static func guessStatus(turns: [Turn], lastTimestamp: Date?) -> SessionStatus {
        guard let last = lastTimestamp else { return .abandoned }
        let hoursSince = -last.timeIntervalSinceNow / 3600

        // If the last turn has an error artifact, likely crashed
        if let lastTurn = turns.last,
           lastTurn.artifacts.contains(where: { $0.kind == .error }) {
            return .crashed
        }

        // Recent = live or paused
        if hoursSince < 2 { return .live }
        if hoursSince < 48 { return .paused }
        if hoursSince < 168 { return .completed } // within a week, probably done

        return .archived
    }
}
