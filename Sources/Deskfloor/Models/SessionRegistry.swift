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
        let cwd: String                 // resolved cwd, e.g. "/Users/uprootiny/Nissan/deskfloor"
        let lastModified: Date
        let byteSize: Int64

        /// Heuristic: is this a substantial session worth resuming?
        var isSubstantial: Bool { byteSize > 4_000 }
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
                sessions.append(Session(
                    uuid: uuid,
                    path: url,
                    projectDirName: dirName,
                    cwd: cwd,
                    lastModified: modDate,
                    byteSize: size
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
}
