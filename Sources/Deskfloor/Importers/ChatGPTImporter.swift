import Foundation
import NLPEngine

/// Imports conversations from ChatGPT data export (conversations.json).
enum ChatGPTImporter {

    /// Import from a ChatGPT data export file.
    static func importFile(at path: String) -> [Thread] {
        guard let data = FileManager.default.contents(atPath: path) else {
            NSLog("[ChatGPTImporter] File not found: \(path)")
            return []
        }

        guard let conversations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            NSLog("[ChatGPTImporter] Failed to parse JSON")
            return []
        }

        let analyzer = TextAnalyzer()
        var threads: [Thread] = []

        for convo in conversations {
            if let thread = parseConversation(convo, analyzer: analyzer) {
                threads.append(thread)
            }
        }

        NSLog("[ChatGPTImporter] Imported \(threads.count) threads from \(path)")
        return threads
    }

    private static func parseConversation(_ convo: [String: Any], analyzer: TextAnalyzer) -> Thread? {
        let title = convo["title"] as? String ?? "Untitled"
        let createTime = (convo["create_time"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let updateTime = (convo["update_time"] as? Double).map { Date(timeIntervalSince1970: $0) }

        // ChatGPT stores messages in a tree structure via "mapping"
        guard let mapping = convo["mapping"] as? [String: [String: Any]] else { return nil }

        // Reconstruct linear message order by following parent→children
        let orderedMessages = linearizeMapping(mapping)
        guard !orderedMessages.isEmpty else { return nil }

        var turns: [Turn] = []
        var pendingUser: (content: String, time: Date?)?

        for msg in orderedMessages {
            guard let message = msg["message"] as? [String: Any],
                  let author = message["author"] as? [String: Any],
                  let role = author["role"] as? String else { continue }

            let content = extractContent(from: message)
            guard !content.isEmpty else { continue }

            let timestamp = (message["create_time"] as? Double).map { Date(timeIntervalSince1970: $0) }

            if role == "user" {
                if let pending = pendingUser {
                    turns.append(Turn(userContent: pending.content, timestamp: pending.time))
                }
                pendingUser = (content, timestamp)
            } else if role == "assistant" {
                let userContent = pendingUser?.content ?? ""
                var turn = Turn(
                    userContent: userContent,
                    assistantContent: content,
                    timestamp: pendingUser?.time ?? timestamp
                )

                // Detect artifacts in assistant response
                if analyzer.isPrompt(userContent) && userContent.count > 50 {
                    turn.artifacts.append(Artifact(kind: .prompt, content: userContent))
                }

                turns.append(turn)
                pendingUser = nil
            }
        }

        // Save trailing user message
        if let pending = pendingUser {
            turns.append(Turn(userContent: pending.content, timestamp: pending.time))
        }

        guard !turns.isEmpty else { return nil }

        let allUserText = turns.map(\.userContent).joined(separator: " ")
        let topics = analyzer.extractKeywords(allUserText, topN: 5).map(\.0)

        return Thread(
            id: UUID(),
            source: .chatGPT,
            title: title,
            createdAt: createTime ?? Date(),
            updatedAt: updateTime ?? Date(),
            turns: turns,
            status: .archived, // imported conversations default to archived
            tags: ["imported"],
            topics: topics,
            projectLinks: [],
            color: nil
        )
    }

    /// Reconstruct linear message order from ChatGPT's tree mapping.
    private static func linearizeMapping(_ mapping: [String: [String: Any]]) -> [[String: Any]] {
        // Find root node (no parent or parent is nil)
        var parentToChildren: [String: [String]] = [:]
        var roots: [String] = []

        for (id, node) in mapping {
            let parent = node["parent"] as? String
            if parent == nil || parent?.isEmpty == true {
                roots.append(id)
            } else if let p = parent {
                parentToChildren[p, default: []].append(id)
            }
        }

        // Walk the tree depth-first, following the last child at each branch
        var ordered: [[String: Any]] = []
        var stack = roots

        while let current = stack.popLast() {
            if let node = mapping[current] {
                ordered.append(node)
                // Follow children in order
                if let children = parentToChildren[current] {
                    stack.append(contentsOf: children.reversed())
                }
            }
        }

        return ordered
    }

    private static func extractContent(from message: [String: Any]) -> String {
        guard let content = message["content"] as? [String: Any],
              let parts = content["parts"] as? [Any] else { return "" }
        return parts.compactMap { $0 as? String }.joined(separator: "\n")
    }
}
