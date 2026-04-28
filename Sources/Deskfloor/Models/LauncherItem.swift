import Foundation
import NLPEngine

/// Every item the launcher can search and act on.
enum LauncherItem: Identifiable {
    case host(FleetStore.FleetHost)
    case session(FleetStore.FleetHost, FleetStore.TmuxSession)
    case project(Project)
    case command(String, String) // label, command
    case prompt(PromptStore.Prompt)
    case historyCommand(HistoryStore.HistoryCommand)
    case tile(WindowTiling.Preset)

    var id: String {
        switch self {
        case .host(let h): return "host:\(h.name)"
        case .session(let h, let s): return "tmux:\(h.name):\(s.name)"
        case .project(let p): return "project:\(p.id)"
        case .command(let label, _): return "cmd:\(label)"
        case .prompt(let p): return "prompt:\(p.id.uuidString)"
        case .historyCommand(let h): return "history:\(h.id)"
        case .tile(let preset): return "tile:\(preset.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .host(let h): return "\(h.sigil) \(h.name)"
        case .session(let h, let s): return "\(h.sigil) \(s.name)"
        case .project(let p): return p.name
        case .command(let label, _): return label
        case .prompt(let p): return p.title
        case .historyCommand(let h):
            return h.command.count > 60 ? String(h.command.prefix(60)) + "..." : h.command
        case .tile(let preset): return preset.label
        }
    }

    var subtitle: String {
        switch self {
        case .host(let h):
            return "load \(String(format: "%.1f", h.load)) · disk \(h.diskPercent)% · \(h.claudeCount) claude"
        case .session(let h, let s):
            return "\(h.name) · \(s.windows) win · \(s.attached ? "attached" : "detached")"
        case .project(let p):
            var parts: [String] = []
            if let type = p.projectType { parts.append(type) }
            if let branch = p.gitBranch { parts.append(branch) }
            if let dirty = p.dirtyFiles, dirty > 0 { parts.append("\(dirty) changed") }
            if p.commitCount > 0 { parts.append("\(p.commitCount)★") }
            // Activity recency
            if let last = p.lastActivity {
                let days = Int(-last.timeIntervalSinceNow / 86400)
                if days == 0 { parts.append("today") }
                else if days == 1 { parts.append("yesterday") }
                else if days < 30 { parts.append("\(days)d ago") }
                else { parts.append("\(days/30)mo ago") }
            }
            // Where it lives
            if p.localPath != nil { parts.append("local") }
            else if p.repo != nil { parts.append("github") }
            if parts.isEmpty { return p.description }
            return parts.joined(separator: " · ")
        case .command(_, let cmd):
            return cmd
        case .prompt(let p):
            let truncated = p.content.prefix(80)
            return truncated.count < p.content.count ? truncated + "..." : String(truncated)
        case .historyCommand(let h):
            let timeAgo = Self.relativeTime(h.lastUsed)
            return "used \(h.count)x, \(timeAgo)"
        case .tile(let preset):
            let f = preset.fraction
            return String(format: "x %.0f%% · y %.0f%% · w %.0f%% · h %.0f%%",
                          f.x * 100, f.y * 100, f.w * 100, f.h * 100)
        }
    }

    var category: String {
        switch self {
        case .host: return "Hosts"
        case .session: return "Sessions"
        case .project: return "Projects"
        case .command: return "Commands"
        case .prompt: return "Prompts"
        case .historyCommand: return "History"
        case .tile: return "Tile"
        }
    }

    var keywords: [String] {
        switch self {
        case .host(let h): return [h.name, "ssh", "server"]
        case .session(let h, let s): return [h.name, s.name, "tmux"]
        case .project(let p):
            return [p.name, p.description, p.repo, p.projectType, p.gitBranch].compactMap { $0 } + p.tags + p.connections
        case .command(let label, _): return label.split(separator: " ").map(String.init)
        case .prompt(let p): return p.tags
        case .historyCommand(let h):
            return h.command.split(separator: " ").map(String.init)
        case .tile(let preset):
            return ["tile", "window", "arrange", preset.rawValue.lowercased()]
        }
    }

    private static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let seconds = -date.timeIntervalSinceNow
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        case ..<604800: return "\(Int(seconds / 86400))d ago"
        default: return "\(Int(seconds / 604800))w ago"
        }
    }
}

/// Composite scorer: prefix + contains + abbreviation + fuzzy(trigram) + keyword
/// overlap + subtitle + frecency + recency + type bias. Transparent weights.
struct LauncherSearch {
    private let analyzer = TextAnalyzer()

    func search(query: String, items: [LauncherItem], frecency: FrecencyTracker? = nil, limit: Int = 50) -> [LauncherItem] {
        guard !query.isEmpty else {
            if let frecency {
                return items
                    .sorted { lhs, rhs in
                        let lf = frecency.score(itemID: lhs.id)
                        let rf = frecency.score(itemID: rhs.id)
                        if lf != rf { return lf > rf }
                        return Self.recencyScore(lhs) > Self.recencyScore(rhs)
                    }
                    .prefix(limit).map { $0 }
            }
            return items
                .sorted { Self.recencyScore($0) > Self.recencyScore($1) }
                .prefix(limit).map { $0 }
        }

        let q = query.lowercased()
        let queryTokens = Set(analyzer.tokenize(query))
        let queryTrigrams = Self.trigrams(of: q)

        return items
            .map { item -> (LauncherItem, Double) in
                let title = item.title.lowercased()
                let initials = Self.initials(of: item.title)
                var score = 0.0

                // 1. prefix
                if title.hasPrefix(q) { score += 10 }
                else if title.contains(q) { score += 5 }

                // 2. abbreviation — "df" → "Deskfloor"
                if initials.hasPrefix(q) { score += 8 }

                // 3. fuzzy via trigram Jaccard
                if !queryTrigrams.isEmpty {
                    let t = Self.trigrams(of: title + " " + item.keywords.joined(separator: " ").lowercased())
                    let inter = queryTrigrams.intersection(t).count
                    let union = queryTrigrams.union(t).count
                    if union > 0 {
                        score += (Double(inter) / Double(union)) * 3
                    }
                }

                // 4. keyword token overlap
                let itemTokens = Set(analyzer.tokenize(
                    item.title + " " + item.keywords.joined(separator: " ")
                ))
                if !queryTokens.isEmpty {
                    let overlap = queryTokens.intersection(itemTokens)
                    score += Double(overlap.count) / Double(queryTokens.count) * 3
                }

                // 5. subtitle weak signal
                if item.subtitle.lowercased().contains(q) { score += 1 }

                // 6. frecency — log₂(use+1) so power-users don't dominate runaway
                if let frecency {
                    let f = frecency.score(itemID: item.id)
                    if f > 0 { score += log2(f + 1) }
                }

                // 7. recency — within 30 days, smoothly decays
                score += Self.recencyScore(item) * 1.5

                // 8. type bias — favor concrete things over commands when ambiguous
                score *= Self.typeBias(item)

                return (item, score)
            }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Letter sequence formed by uppercase initials and post-separator letters.
    /// "Deskfloor" → "d", "raindesk-app" → "ra", "agent slack" → "as".
    static func initials(of s: String) -> String {
        var out: [Character] = []
        var atBoundary = true
        for ch in s {
            if ch.isLetter && atBoundary {
                out.append(Character(ch.lowercased()))
                atBoundary = false
            } else if !ch.isLetter && !ch.isNumber {
                atBoundary = true
            } else if ch.isUppercase {
                out.append(Character(ch.lowercased()))
            } else {
                atBoundary = false
            }
        }
        return String(out)
    }

    /// Padded trigrams of a string. Cheap and good enough for fuzzy ranking.
    static func trigrams(of s: String) -> Set<String> {
        guard !s.isEmpty else { return [] }
        let padded = "  " + s + "  "
        var out = Set<String>()
        let chars = Array(padded)
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                out.insert(String(chars[i...i+2]))
            }
        }
        return out
    }

    /// 0.0 (years old) → 1.0 (right now). Linear within 30 days, capped.
    static func recencyScore(_ item: LauncherItem) -> Double {
        guard let last = recencyAnchor(item) else { return 0 }
        let age = -last.timeIntervalSinceNow
        if age <= 0 { return 1 }
        let days = age / 86400
        return max(0, 1 - days / 30)
    }

    private static func recencyAnchor(_ item: LauncherItem) -> Date? {
        switch item {
        case .project(let p): return p.lastActivity
        case .historyCommand(let h): return h.lastUsed
        case .prompt(let p): return p.lastUsed
        case .session(_, _): return nil
        case .host(_): return nil
        case .command(_, _): return nil
        case .tile(_): return nil
        }
    }

    /// Per-type ergonomic bias. Projects and sessions outrank fillers when scores tie.
    static func typeBias(_ item: LauncherItem) -> Double {
        switch item {
        case .project: return 1.00
        case .host: return 0.95
        case .session: return 0.90
        case .prompt: return 0.80
        case .historyCommand: return 0.65
        case .tile: return 0.55
        case .command: return 0.50
        }
    }
}
