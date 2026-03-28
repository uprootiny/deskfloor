import Foundation
import NLPEngine

/// Every item the launcher can search and act on.
enum LauncherItem: Identifiable {
    case host(FleetStore.FleetHost)
    case session(FleetStore.FleetHost, FleetStore.TmuxSession)
    case project(Project)
    case command(String, String) // label, command

    var id: String {
        switch self {
        case .host(let h): return "host:\(h.name)"
        case .session(let h, let s): return "tmux:\(h.name):\(s.name)"
        case .project(let p): return "project:\(p.id)"
        case .command(let label, _): return "cmd:\(label)"
        }
    }

    var title: String {
        switch self {
        case .host(let h): return "\(h.sigil) \(h.name)"
        case .session(let h, let s): return "\(h.sigil) \(s.name)"
        case .project(let p): return p.name
        case .command(let label, _): return label
        }
    }

    var subtitle: String {
        switch self {
        case .host(let h):
            return "load \(String(format: "%.1f", h.load)) · disk \(h.diskPercent)% · \(h.claudeCount) claude"
        case .session(let h, let s):
            return "\(h.name) · \(s.windows) win · \(s.attached ? "attached" : "detached")"
        case .project(let p):
            return p.description
        case .command(_, let cmd):
            return cmd
        }
    }

    var category: String {
        switch self {
        case .host: return "Hosts"
        case .session: return "Sessions"
        case .project: return "Projects"
        case .command: return "Commands"
        }
    }

    var keywords: [String] {
        switch self {
        case .host(let h): return [h.name, "ssh", "server"]
        case .session(let h, let s): return [h.name, s.name, "tmux"]
        case .project(let p): return [p.name] + p.tags
        case .command(let label, _): return label.split(separator: " ").map(String.init)
        }
    }
}

/// Fuzzy search with frecency scoring.
struct LauncherSearch {
    private let analyzer = TextAnalyzer()

    func search(query: String, items: [LauncherItem], limit: Int = 20) -> [LauncherItem] {
        guard !query.isEmpty else {
            return Array(items.prefix(limit))
        }

        let queryLower = query.lowercased()
        let queryTokens = Set(analyzer.tokenize(query))

        return items
            .map { item -> (LauncherItem, Double) in
                var score = 0.0
                let titleLower = item.title.lowercased()

                // Exact prefix match (highest signal)
                if titleLower.hasPrefix(queryLower) {
                    score += 10.0
                } else if titleLower.contains(queryLower) {
                    score += 5.0
                }

                // Token overlap
                let itemTokens = Set(analyzer.tokenize(
                    item.title + " " + item.keywords.joined(separator: " ")
                ))
                let overlap = queryTokens.intersection(itemTokens)
                if !queryTokens.isEmpty {
                    score += Double(overlap.count) / Double(queryTokens.count) * 3.0
                }

                // Subtitle match
                if item.subtitle.lowercased().contains(queryLower) {
                    score += 1.0
                }

                return (item, score)
            }
            .filter { $0.1 > 0.01 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
