import Foundation

/// Reads ~/.zsh_history, parses extended format, ranks by frecency.
@Observable
final class HistoryStore {
    struct HistoryCommand: Identifiable {
        let id: String
        var command: String
        var count: Int
        var lastUsed: Date?

        var frecencyScore: Double {
            let recency = recencyWeight(lastUsed)
            return Double(count) * recency
        }

        private func recencyWeight(_ date: Date?) -> Double {
            guard let date else { return 10 }
            let hours = -date.timeIntervalSinceNow / 3600
            switch hours {
            case ..<6: return 100
            case ..<24: return 80
            case ..<72: return 60
            case ..<168: return 40
            case ..<720: return 20
            default: return 10
            }
        }
    }

    var commands: [HistoryCommand] = []

    private static let noise: Set<String> = ["ls", "cd", "pwd", "clear", "exit", "ll", "la"]
    private static let minLength = 10

    init() {
        load()
    }

    func load() {
        let historyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zsh_history").path

        guard FileManager.default.fileExists(atPath: historyPath) else { return }

        do {
            // zsh_history can contain invalid UTF-8; read as data and lossy-convert
            let data = try Data(contentsOf: URL(fileURLWithPath: historyPath))
            let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? ""

            let lines = content.components(separatedBy: "\n")
            let tail = lines.suffix(5000)

            // Aggregate: command -> (count, mostRecentTimestamp)
            var freq: [String: (count: Int, latest: Date?)] = [:]

            for line in tail {
                guard let parsed = parseLine(line) else { continue }
                let cmd = parsed.command.trimmingCharacters(in: .whitespaces)

                // Filter noise
                let baseCmd = cmd.split(separator: " ").first.map(String.init) ?? cmd
                if Self.noise.contains(baseCmd) { continue }
                if cmd.count < Self.minLength { continue }

                let existing = freq[cmd] ?? (count: 0, latest: nil)
                let newer: Date?
                if let a = existing.latest, let b = parsed.date {
                    newer = a > b ? a : b
                } else {
                    newer = existing.latest ?? parsed.date
                }
                freq[cmd] = (count: existing.count + 1, latest: newer)
            }

            // Build HistoryCommand list, sort by frecency, take top 200
            commands = freq.map { (cmd, info) in
                HistoryCommand(id: cmd, command: cmd, count: info.count, lastUsed: info.latest)
            }
            .sorted { $0.frecencyScore > $1.frecencyScore }
            .prefix(200)
            .map { $0 }

        } catch {
            NSLog("[HistoryStore] Failed to read zsh_history: \(error)")
        }
    }

    /// Parse zsh extended history format: `: timestamp:0;command`
    private func parseLine(_ line: String) -> (command: String, date: Date?)? {
        // Extended format: ": 1234567890:0;actual command here"
        if line.hasPrefix(": ") {
            let rest = line.dropFirst(2) // drop ": "
            if let semicolonIdx = rest.firstIndex(of: ";") {
                let command = String(rest[rest.index(after: semicolonIdx)...])
                // Parse timestamp from "1234567890:0"
                let meta = rest[rest.startIndex..<semicolonIdx]
                let timestamp = meta.split(separator: ":").first.flatMap { Double($0) }
                let date = timestamp.map { Date(timeIntervalSince1970: $0) }
                return (command: command, date: date)
            }
        }
        // Plain format (no timestamp)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return (command: trimmed, date: nil)
    }
}
