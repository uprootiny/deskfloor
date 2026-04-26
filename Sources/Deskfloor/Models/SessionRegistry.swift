import Foundation
import Observation

/// Indexes Claude Code session transcripts under ~/.claude/projects/, keyed by the
/// project's working directory (so Project.localPath resolves to a list of sessions).
///
/// Claude Code maps a cwd to a directory name by replacing every "/" with "-". We
/// invert that *forward* (cwd → dir name) to avoid ambiguity for projects whose
/// names contain hyphens (e.g., "mathematical-consciousness-dsl").
@Observable
final class SessionRegistry {

    struct Session: Identifiable, Hashable {
        var id: String { uuid }
        let uuid: String                // session UUID (filename minus .jsonl)
        let path: URL                   // .jsonl on disk
        let projectDirName: String      // e.g. "-Users-uprootiny-Nissan-deskfloor"
        let cwd: String                 // accurate cwd from JSONL header (or fallback)
        let lastModified: Date
        let byteSize: Int64
        let summary: String?            // first user prompt or stored summary, ~120 chars
        let gitBranch: String?

        /// Heuristic: is this a substantial session worth resuming?
        var isSubstantial: Bool { byteSize > 4_000 }

        /// Display label for menus — short, informative.
        var displayLabel: String {
            let age = Self.relativeAge(lastModified)
            let kb = byteSize / 1024
            if let s = summary, !s.isEmpty {
                let trimmed = s.count > 70 ? String(s.prefix(70)) + "…" : s
                return "\(trimmed) · \(age) · \(kb) KB"
            }
            return "\(uuid.prefix(8)) · \(age) · \(kb) KB"
        }

        private static func relativeAge(_ d: Date) -> String {
            let s = -d.timeIntervalSinceNow
            switch s {
            case ..<60: return "just now"
            case ..<3600: return "\(Int(s / 60))m"
            case ..<86400: return "\(Int(s / 3600))h"
            case ..<604800: return "\(Int(s / 86400))d"
            default: return "\(Int(s / 604800))w"
            }
        }
    }

    /// Indexed by directory name (the on-disk form), populated by refresh().
    private(set) var byDirName: [String: [Session]] = [:]

    /// When the index was last rebuilt.
    private(set) var lastRefresh: Date = .distantPast

    init() {
        refresh()
    }

    /// Convert a cwd to the on-disk directory name Claude Code uses.
    /// "/Users/uprootiny/Nissan/deskfloor" → "-Users-uprootiny-Nissan-deskfloor"
    static func dirName(for cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    /// All sessions known for a given local-path project, sorted recent-first.
    func sessions(for project: Project) -> [Session] {
        guard let path = project.localPath else { return [] }
        return sessions(forCwd: path)
    }

    func sessions(forCwd cwd: String) -> [Session] {
        byDirName[Self.dirName(for: cwd)] ?? []
    }

    /// Most-recently-modified session for a project, if any.
    func mostRecent(for project: Project) -> Session? {
        sessions(for: project).first
    }

    func mostRecent(forCwd cwd: String) -> Session? {
        sessions(forCwd: cwd).first
    }

    /// Rebuild the index. Cheap — only stats files, doesn't read JSONL bodies.
    func refresh() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        var byDir: [String: [Session]] = [:]
        let projectDirs = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for projDir in projectDirs {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: projDir.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let dirName = projDir.lastPathComponent
            // Reverse-map for the cwd field — naive, but only used for display/cd.
            // For lookup we always go cwd→dirName forward, which is unambiguous.
            let cwd = "/" + dirName.dropFirst().replacingOccurrences(of: "-", with: "/")

            let entries = (try? FileManager.default.contentsOfDirectory(
                at: projDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            var sessions: [Session] = []
            for url in entries where url.pathExtension == "jsonl" {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let modDate = (attrs?[.modificationDate] as? Date) ?? .distantPast
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let uuid = url.deletingPathExtension().lastPathComponent
                let header = Self.parseHeader(at: url)
                sessions.append(Session(
                    uuid: uuid,
                    path: url,
                    projectDirName: dirName,
                    cwd: header.cwd ?? cwd,
                    lastModified: modDate,
                    byteSize: size,
                    summary: header.summary,
                    gitBranch: header.gitBranch
                ))
            }
            sessions.sort { $0.lastModified > $1.lastModified }
            if !sessions.isEmpty {
                byDir[dirName] = sessions
            }
        }

        self.byDirName = byDir
        self.lastRefresh = Date()
        NSLog("[SessionRegistry] indexed \(byDir.count) project dirs, \(byDir.values.map(\.count).reduce(0, +)) sessions total")
    }

    /// Snapshot for diagnostics — used by the menu-bar item.
    func diagnosticSummary() -> String {
        var lines = ["SessionRegistry — refreshed \(lastRefresh)"]
        let total = byDirName.values.map(\.count).reduce(0, +)
        let totalBytes = byDirName.values.flatMap { $0 }.map { $0.byteSize }.reduce(0, +)
        lines.append("  \(byDirName.count) project dirs, \(total) sessions, \(totalBytes / 1024) KB")
        let topDirs = byDirName.sorted { ($0.value.first?.lastModified ?? .distantPast) > ($1.value.first?.lastModified ?? .distantPast) }.prefix(8)
        for (dir, sessions) in topDirs {
            let cwd = sessions.first?.cwd ?? "?"
            let mostRecent = sessions.first.map { Self.shortAge($0.lastModified) } ?? "?"
            lines.append("  \(sessions.count)× \(cwd) [\(mostRecent)] (\(dir))")
        }
        return lines.joined(separator: "\n")
    }

    private static func shortAge(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        switch s {
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        default: return "\(Int(s / 86400))d"
        }
    }

    // MARK: - JSONL header parsing

    struct Header {
        var cwd: String?
        var summary: String?
        var gitBranch: String?
    }

    /// Read the first ~5 lines of a JSONL transcript and pick out cwd, gitBranch, and a
    /// short summary (first stored summary or first user prompt). Cheap — bounded by 5
    /// `readLine`-equivalents per file.
    static func parseHeader(at url: URL) -> Header {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Header() }
        defer { try? handle.close() }

        // Read first 16 KB — enough for several JSONL records, including any summary blob.
        let blob = handle.readData(ofLength: 16 * 1024)
        guard let str = String(data: blob, encoding: .utf8) else { return Header() }

        var header = Header()
        var lineCount = 0
        for rawLine in str.split(separator: "\n", omittingEmptySubsequences: true) {
            lineCount += 1
            if lineCount > 8 { break }
            let line = String(rawLine)
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if header.cwd == nil, let cwd = obj["cwd"] as? String { header.cwd = cwd }
            if header.gitBranch == nil, let b = obj["gitBranch"] as? String, !b.isEmpty { header.gitBranch = b }

            if header.summary == nil, let stored = obj["summary"] as? String, !stored.isEmpty {
                header.summary = stored
            }

            // Fallback summary: first user prompt text
            if header.summary == nil,
               (obj["type"] as? String) == "user",
               let msg = obj["message"] as? [String: Any],
               (msg["role"] as? String) == "user" {
                if let text = msg["content"] as? String {
                    header.summary = condense(text)
                } else if let parts = msg["content"] as? [[String: Any]] {
                    for part in parts where (part["type"] as? String) == "text" {
                        if let t = part["text"] as? String, !t.isEmpty {
                            header.summary = condense(t); break
                        }
                    }
                }
            }

            if header.cwd != nil && header.summary != nil && header.gitBranch != nil { break }
        }
        return header
    }

    private static func condense(_ s: String) -> String {
        let cleaned = s
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 200 ? String(cleaned.prefix(200)) + "…" : cleaned
    }
}
