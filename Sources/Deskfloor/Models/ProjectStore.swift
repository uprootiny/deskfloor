import Foundation
import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case name, lastActivity, startDate, commitCount, status
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .lastActivity: "Recent"
        case .startDate: "Started"
        case .commitCount: "Commits"
        case .status: "Status"
        }
    }
}

@Observable
final class ProjectStore {
    var projects: [Project] = []
    var sortOrder: SortOrder = .lastActivity
    var isScanning = false
    var scanProgress: (done: Int, total: Int) = (0, 0)

    private let fileURL: URL
    private let scanRoot: URL

    /// Project manifest files we recognize, mapped to a human-readable type.
    private static let projectMarkers: [(file: String, type: String)] = [
        ("Package.swift", "Swift"),
        ("package.json", "Node"),
        ("Cargo.toml", "Rust"),
        ("CMakeLists.txt", "C++"),
        ("pyproject.toml", "Python"),
        ("setup.py", "Python"),
        ("Makefile", "Make"),
        ("flake.nix", "Nix"),
        ("mix.exs", "Elixir"),
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".deskfloor", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("projects.json")
        self.scanRoot = home.appendingPathComponent("Nissan", isDirectory: true)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()

        // If no saved projects, scan the filesystem
        if projects.isEmpty {
            scanLocalProjects()
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([Project].self, from: data)
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    // MARK: - Filesystem Scanner

    /// Scan ~/Nissan/ for local projects and merge them into the store.
    func scanLocalProjects() {
        isScanning = true
        let fm = FileManager.default
        let rootPath = scanRoot.path

        guard fm.fileExists(atPath: rootPath) else {
            isScanning = false
            return
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: rootPath) else {
            isScanning = false
            return
        }

        let existingPaths = Set(projects.compactMap(\.localPath))
        let existingNames = Set(projects.map(\.name))

        for entry in entries {
            let entryPath = scanRoot.appendingPathComponent(entry).path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Skip hidden directories and non-project directories
            if entry.hasPrefix(".") { continue }

            // Already tracked by path or name
            if existingPaths.contains(entryPath) || existingNames.contains(entry) { continue }

            // Check for project markers
            var projectType: String? = nil
            for marker in Self.projectMarkers {
                let markerPath = scanRoot.appendingPathComponent(entry).appendingPathComponent(marker.file).path
                if fm.fileExists(atPath: markerPath) {
                    projectType = marker.type
                    break
                }
            }

            // Also accept any directory with a .git folder
            let hasGit = fm.fileExists(atPath: scanRoot.appendingPathComponent(entry).appendingPathComponent(".git").path)

            guard projectType != nil || hasGit else { continue }

            // Build a Project from filesystem data
            let dirURL = scanRoot.appendingPathComponent(entry)
            let gitInfo = Self.readGitInfo(at: dirURL)
            let perspective = GitHubImporter.guessPerspectiveForLocal(
                name: entry,
                language: projectType,
                path: entryPath
            )

            let daysSinceActivity = gitInfo.lastCommitDate.map { -$0.timeIntervalSinceNow / 86400 } ?? 999
            let status: Status
            if daysSinceActivity > 180 {
                status = .archived
            } else if daysSinceActivity > 90 {
                status = .paused
            } else {
                status = .active
            }

            let project = Project(
                name: entry,
                repo: gitInfo.remoteRepo,
                localPath: entryPath,
                description: Self.readDescription(at: dirURL, type: projectType),
                why: "",
                status: status,
                perspective: perspective,
                tags: [projectType].compactMap { $0 },
                startDate: gitInfo.firstCommitDate,
                lastActivity: gitInfo.lastCommitDate ?? Self.modificationDate(of: dirURL),
                commitCount: gitInfo.commitCount,
                encumbrances: [],
                connections: [],
                progressNotes: [],
                handoffReady: false,
                handoffNotes: "",
                lastCommitMessage: gitInfo.lastMessage,
                lastCommitAuthor: gitInfo.lastAuthor,
                gitBranch: gitInfo.branch,
                dirtyFiles: gitInfo.dirtyCount,
                projectType: projectType
            )

            projects.append(project)
        }

        // Auto-detect connections between local projects
        autoDetectConnections()

        isScanning = false
        save()
    }

    /// Refresh git info for all projects that have a local path.
    /// Runs asynchronously — updates projects one at a time so UI stays responsive.
    func refreshGitInfo() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [self] in
            let localProjects = await MainActor.run { projects.enumerated().filter { $0.element.localPath != nil } }

            await MainActor.run { scanProgress = (0, localProjects.count) }

            for (idx, (i, project)) in localProjects.enumerated() {
                guard let path = project.localPath else { continue }
                let dirURL = URL(fileURLWithPath: path)
                let gitInfo = Self.readGitInfo(at: dirURL)

                await MainActor.run {
                    scanProgress = (idx + 1, localProjects.count)
                    projects[i].lastActivity = gitInfo.lastCommitDate ?? projects[i].lastActivity
                    projects[i].commitCount = gitInfo.commitCount > 0 ? gitInfo.commitCount : projects[i].commitCount
                    projects[i].lastCommitMessage = gitInfo.lastMessage ?? projects[i].lastCommitMessage
                    projects[i].lastCommitAuthor = gitInfo.lastAuthor ?? projects[i].lastCommitAuthor
                    projects[i].gitBranch = gitInfo.branch ?? projects[i].gitBranch
                    projects[i].dirtyFiles = gitInfo.dirtyCount
                    if let remote = gitInfo.remoteRepo, projects[i].repo == nil {
                        projects[i].repo = remote
                    }
                }
            }

            await MainActor.run {
                save()
                isScanning = false
                NSLog("[ProjectStore] Git refresh complete for \(localProjects.count) projects")
            }
        }
    }

    // MARK: - Git Helpers

    struct GitInfo {
        var commitCount: Int = 0
        var lastCommitDate: Date? = nil
        var firstCommitDate: Date? = nil
        var lastMessage: String? = nil
        var lastAuthor: String? = nil
        var branch: String? = nil
        var dirtyCount: Int? = nil
        var remoteRepo: String? = nil
    }

    static func readGitInfo(at dir: URL) -> GitInfo {
        var info = GitInfo()

        let gitDir = dir.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitDir) else { return info }

        // Branch
        info.branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: dir)

        // Commit count
        if let countStr = runGit(["rev-list", "--count", "HEAD"], in: dir),
           let count = Int(countStr) {
            info.commitCount = count
        }

        // Last commit info
        if let logLine = runGit(["log", "-1", "--format=%aI|||%an|||%s"], in: dir) {
            let parts = logLine.components(separatedBy: "|||")
            if parts.count >= 3 {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime]
                info.lastCommitDate = isoFormatter.date(from: parts[0])
                info.lastAuthor = parts[1]
                info.lastMessage = parts[2]
            }
        }

        // First commit date
        if let firstLine = runGit(["log", "--reverse", "--format=%aI", "--max-count=1"], in: dir) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            info.firstCommitDate = isoFormatter.date(from: firstLine)
        }

        // Dirty file count
        if let statusOutput = runGit(["status", "--porcelain"], in: dir) {
            let lines = statusOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
            info.dirtyCount = lines.count
        } else {
            info.dirtyCount = 0
        }

        // Remote repo (extract owner/name from origin URL)
        if let remote = runGit(["remote", "get-url", "origin"], in: dir) {
            info.remoteRepo = Self.parseGitHubRepo(from: remote)
        }

        return info
    }

    private static func runGit(_ args: [String], in dir: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func parseGitHubRepo(from remote: String) -> String? {
        // Handles: git@github.com:owner/repo.git, https://github.com/owner/repo.git
        let cleaned = remote
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it looks like owner/repo
        let parts = cleaned.split(separator: "/")
        if parts.count == 2 {
            return cleaned
        }
        return nil
    }

    private static func readDescription(at dir: URL, type: String?) -> String {
        let fm = FileManager.default

        // Try reading description from Package.swift (look for comment or name)
        if type == "Swift" {
            let pkgPath = dir.appendingPathComponent("Package.swift").path
            if let content = try? String(contentsOfFile: pkgPath, encoding: .utf8) {
                // Extract package name
                if let range = content.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression) {
                    let match = content[range]
                    if let nameRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                        let name = match[nameRange].dropFirst().dropLast()
                        return "Swift package: \(name)"
                    }
                }
            }
        }

        // Try reading from package.json
        if type == "Node" {
            let pkgPath = dir.appendingPathComponent("package.json").path
            if let data = fm.contents(atPath: pkgPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let desc = json["description"] as? String, !desc.isEmpty {
                return desc
            }
        }

        // Try reading from Cargo.toml (simple grep)
        if type == "Rust" {
            let cargoPath = dir.appendingPathComponent("Cargo.toml").path
            if let content = try? String(contentsOfFile: cargoPath, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                    if line.hasPrefix("description") {
                        let value = line.split(separator: "=", maxSplits: 1).last?
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if let value, !value.isEmpty { return value }
                    }
                }
            }
        }

        // Fallback: check for README first line
        for readme in ["README.md", "README", "readme.md"] {
            let readmePath = dir.appendingPathComponent(readme).path
            if let content = try? String(contentsOfFile: readmePath, encoding: .utf8) {
                let firstLine = content.components(separatedBy: "\n")
                    .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                if let firstLine, !firstLine.isEmpty {
                    return String(firstLine.prefix(120))
                }
            }
        }

        return type.map { "\($0) project" } ?? "Local project"
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func autoDetectConnections() {
        for i in projects.indices {
            var connections = projects[i].connections
            let p = projects[i]
            for j in projects.indices where i != j {
                let q = projects[j]
                if connections.contains(q.name) { continue }

                // Same perspective + same language
                if p.perspective == q.perspective,
                   let pLang = p.tags.first, let qLang = q.tags.first,
                   pLang == qLang, !pLang.isEmpty {
                    connections.append(q.name)
                }

                // Name prefix match
                let prefix = String(p.name.prefix(6))
                if prefix.count >= 5, q.name.hasPrefix(prefix), p.name != q.name {
                    if !connections.contains(q.name) {
                        connections.append(q.name)
                    }
                }
            }
            projects[i].connections = Array(connections.prefix(8))
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }

    func addProject(_ project: Project) {
        projects.append(project)
        save()
    }

    func updateProject(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            save()
        }
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func moveProject(id: UUID, toStatus status: Status) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].status = status
            projects[idx].lastActivity = Date()
            save()
        }
    }

    func moveProject(id: UUID, toPerspective perspective: Perspective) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].perspective = perspective
            projects[idx].lastActivity = Date()
            save()
        }
    }

    func projectsForStatus(_ status: Status) -> [Project] {
        projects.filter { $0.status == status }
    }

    func projectsForPerspective(_ perspective: Perspective) -> [Project] {
        projects.filter { $0.perspective == perspective }
    }

    func filtered(
        searchText: String,
        perspectives: Set<Perspective>,
        statuses: Set<Status>,
        encumbranceKinds: Set<EncumbranceKind>,
        handoffOnly: Bool,
        encumberedOnly: Bool
    ) -> [Project] {
        projects.filter { project in
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let match = project.name.lowercased().contains(query)
                    || project.description.lowercased().contains(query)
                    || project.why.lowercased().contains(query)
                    || (project.repo?.lowercased().contains(query) ?? false)
                    || project.tags.contains(where: { $0.lowercased().contains(query) })
                    || project.handoffNotes.lowercased().contains(query)
                if !match { return false }
            }
            if !perspectives.isEmpty && !perspectives.contains(project.perspective) {
                return false
            }
            if !statuses.isEmpty && !statuses.contains(project.status) {
                return false
            }
            if !encumbranceKinds.isEmpty {
                let projectKinds = Set(project.encumbrances.map(\.kind))
                if projectKinds.isDisjoint(with: encumbranceKinds) { return false }
            }
            if handoffOnly && !project.handoffReady { return false }
            if encumberedOnly && project.encumbrances.isEmpty { return false }
            return true
        }
        .sorted { a, b in
            switch sortOrder {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .lastActivity:
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            case .startDate:
                return (a.startDate ?? .distantPast) > (b.startDate ?? .distantPast)
            case .commitCount:
                return a.commitCount > b.commitCount
            case .status:
                return a.status.rawValue < b.status.rawValue
            }
        }
    }
}
