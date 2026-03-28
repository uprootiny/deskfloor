import Foundation

/// JSON-backed prompt library at ~/.deskfloor/prompts.json.
@Observable
final class PromptStore {
    struct Prompt: Identifiable, Codable {
        var id: UUID
        var title: String
        var content: String
        var tags: [String]
        var useCount: Int
        var lastUsed: Date?
    }

    var prompts: [Prompt] = []

    private let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".deskfloor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("prompts.json")
    }()

    init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            seedDefaults()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            prompts = try decoder.decode([Prompt].self, from: data)
        } catch {
            NSLog("[PromptStore] Failed to load: \(error)")
            seedDefaults()
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(prompts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[PromptStore] Failed to save: \(error)")
        }
    }

    func recordUse(id: UUID) {
        guard let idx = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[idx].useCount += 1
        prompts[idx].lastUsed = Date()
        save()
    }

    func addPrompt(title: String, content: String, tags: [String]) {
        let prompt = Prompt(id: UUID(), title: title, content: content, tags: tags, useCount: 0, lastUsed: nil)
        prompts.append(prompt)
        save()
    }

    func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        save()
    }

    private func seedDefaults() {
        prompts = [
            Prompt(id: UUID(), title: "Code review — architecture focus",
                   content: "Review this code with an emphasis on architecture: separation of concerns, dependency direction, abstraction boundaries, and extensibility. Flag anything that would make the next developer's life harder.",
                   tags: ["code-review", "architecture"], useCount: 0, lastUsed: nil),
            Prompt(id: UUID(), title: "Explain like I'm switching contexts",
                   content: "I'm context-switching into this area. Give me a concise orientation: what does this do, what are the key abstractions, what are the gotchas, and what should I read first?",
                   tags: ["onboarding", "explain"], useCount: 0, lastUsed: nil),
            Prompt(id: UUID(), title: "Debug session — systematic",
                   content: "Help me debug this systematically. Start by listing hypotheses ranked by likelihood, then for each one suggest a diagnostic step. Let's narrow down before changing anything.",
                   tags: ["debugging"], useCount: 0, lastUsed: nil),
            Prompt(id: UUID(), title: "Fleet digest template",
                   content: "Summarize the current fleet status: which hosts are healthy, any load/disk alerts, active tmux sessions, and recent agent activity. Format as a brief ops digest.",
                   tags: ["fleet", "ops"], useCount: 0, lastUsed: nil),
            Prompt(id: UUID(), title: "Agent system prompt — specialist",
                   content: "Write a system prompt for a specialist agent. Define its role, constraints, output format, and escalation rules. Keep it under 200 words and make it testable.",
                   tags: ["agent", "agentslack"], useCount: 0, lastUsed: nil),
        ]
        save()
    }
}
