import Foundation
import os

@Observable
final class SurfaceStore {
    var discoveredSurfaces: [Surface] = []
    var isScanning = false

    private var timer: Timer?
    private weak var projectStore: ProjectStore?

    init(projectStore: ProjectStore? = nil) {
        self.projectStore = projectStore
    }

    // MARK: - Public API

    var allSurfaces: [Surface] { discoveredSurfaces }

    func surfaces(for projectID: UUID) -> [Surface] {
        discoveredSurfaces.filter { $0.projectID == projectID }
    }

    func surfaceCounts(for projectID: UUID) -> [SurfaceKind: Int] {
        var counts: [SurfaceKind: Int] = [:]
        for s in discoveredSurfaces where s.projectID == projectID {
            counts[s.kind, default: 0] += 1
        }
        return counts
    }

    func startPolling(projectStore: ProjectStore) {
        self.projectStore = projectStore
        scan()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var surfaces: [Surface] = []

            // Run all discovery in parallel
            async let terminals = self.discoverTerminals()
            async let tmuxPanes = self.discoverTmux()
            async let ports = self.discoverPorts()
            async let claude = self.discoverClaudeSessions()
            async let tabs = self.discoverBrowserTabs()

            surfaces.append(contentsOf: await terminals)
            surfaces.append(contentsOf: await tmuxPanes)
            surfaces.append(contentsOf: await ports)
            surfaces.append(contentsOf: await claude)
            surfaces.append(contentsOf: await tabs)

            // Associate with projects
            let projects = await MainActor.run { self.projectStore?.projects ?? [] }
            for i in surfaces.indices {
                surfaces[i].projectID = self.matchProject(surface: surfaces[i], projects: projects)
            }

            await MainActor.run {
                self.discoveredSurfaces = surfaces
                self.isScanning = false
            }
        }
    }

    // MARK: - Project Matching

    private func matchProject(surface: Surface, projects: [Project]) -> UUID? {
        // Path-based matching
        if let surfacePath = surface.path, !surfacePath.isEmpty {
            let normalized = surfacePath.hasSuffix("/") ? String(surfacePath.dropLast()) : surfacePath
            for project in projects {
                guard let localPath = project.localPath else { continue }
                let projNorm = localPath.hasSuffix("/") ? String(localPath.dropLast()) : localPath
                if normalized == projNorm || normalized.hasPrefix(projNorm + "/") || projNorm.hasPrefix(normalized + "/") {
                    return project.id
                }
            }
        }

        // URL-based matching for browser tabs
        if surface.kind == .browserTab {
            let detail = surface.detail.lowercased()
            for project in projects {
                guard let repo = project.repo else { continue }
                let repoLower = repo.lowercased()
                if detail.contains("github.com/\(repoLower)") || detail.contains("github.com/\(repoLower)/") {
                    return project.id
                }
            }
        }

        return nil
    }

    // MARK: - Terminal Discovery (iTerm2)

    private func discoverTerminals() -> [Surface] {
        let script = """
        set output to ""
        tell application "System Events"
            if not (exists process "iTerm2") then return ""
        end tell
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionName to name of s
                        set sessionDir to ""
                        try
                            set sessionDir to variable named "user.currentDirectory" of s
                        on error
                            try
                                set theTTY to tty of s
                            end try
                        end try
                        set output to output & sessionName & "|||" & sessionDir & linefeed
                    end repeat
                end repeat
            end repeat
        end tell
        return output
        """

        let raw = runAppleScript(script)
        guard !raw.isEmpty else { return [] }

        var surfaces: [Surface] = []
        let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
        for (idx, line) in lines.enumerated() {
            let parts = line.components(separatedBy: "|||")
            let name = parts.first?.trimmingCharacters(in: .whitespaces) ?? "iTerm Session"
            let dir = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            let surface = Surface(
                id: "terminal:iterm:\(idx)",
                kind: .terminal,
                label: name,
                detail: dir.isEmpty ? "iTerm2 session" : dir,
                projectID: nil,
                pid: nil,
                path: dir.isEmpty ? nil : dir
            )
            surfaces.append(surface)
        }
        return surfaces
    }

    // MARK: - Tmux Discovery

    private func discoverTmux() -> [Surface] {
        let output = runShell("/usr/bin/env", arguments: [
            "tmux", "list-panes", "-a",
            "-F", "#{session_name}:#{window_name}:#{pane_index} #{pane_current_path} #{pane_pid}"
        ])
        guard !output.isEmpty else { return [] }

        var surfaces: [Surface] = []
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            // Format: "session:window:pane /path/to/dir pid"
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count >= 2 else { continue }
            let paneKey = parts[0]
            let dir = parts[1]
            let pidStr = parts.count > 2 ? parts[2] : nil
            let pid = pidStr.flatMap { Int($0) }

            let surface = Surface(
                id: "tmux:\(paneKey)",
                kind: .tmux,
                label: paneKey,
                detail: dir,
                projectID: nil,
                pid: pid,
                path: dir
            )
            surfaces.append(surface)
        }
        return surfaces
    }

    // MARK: - Listening Port Discovery

    private func discoverPorts() -> [Surface] {
        let output = runShell("/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        guard !output.isEmpty else { return [] }

        var seen = Set<String>()
        var surfaces: [Surface] = []
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines.dropFirst() { // skip header
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 9 else { continue }
            let command = cols[0]
            let pidStr = cols[1]
            guard let pid = Int(pidStr) else { continue }

            // Extract port from the NAME column (last column), e.g. "*:8080" or "127.0.0.1:3000"
            let nameCol = cols[8]
            let portStr: String
            if let colonIdx = nameCol.lastIndex(of: ":") {
                portStr = String(nameCol[nameCol.index(after: colonIdx)...])
            } else {
                portStr = nameCol
            }

            let key = "\(pid):\(portStr)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // Get working directory for this PID
            let cwdOutput = runShell("/usr/sbin/lsof", arguments: ["-a", "-p", pidStr, "-d", "cwd", "-Fn"])
            var cwd: String? = nil
            for cwdLine in cwdOutput.components(separatedBy: "\n") {
                if cwdLine.hasPrefix("n") {
                    cwd = String(cwdLine.dropFirst())
                    break
                }
            }

            let surface = Surface(
                id: "port:\(portStr):\(pid)",
                kind: .port,
                label: "\(command) :\(portStr)",
                detail: "localhost:\(portStr)",
                projectID: nil,
                pid: pid,
                path: cwd
            )
            surfaces.append(surface)
        }
        return surfaces
    }

    // MARK: - Claude Code Session Discovery

    private func discoverClaudeSessions() -> [Surface] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeProjectsDir = home.appendingPathComponent(".claude/projects")
        let fm = FileManager.default

        guard fm.fileExists(atPath: claudeProjectsDir.path) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(atPath: claudeProjectsDir.path) else { return [] }

        var surfaces: [Surface] = []
        for entry in entries {
            guard !entry.hasPrefix(".") else { continue }
            // Claude Code encodes paths like: -Users-uprootiny-Nissan-deskfloor
            // Decode: replace leading dash, then dashes become /
            var decoded = entry
            if decoded.hasPrefix("-") {
                decoded = "/" + String(decoded.dropFirst())
            }
            decoded = decoded.replacingOccurrences(of: "-", with: "/")

            // Check if this looks like a real path
            let isRealPath = decoded.hasPrefix("/Users/") || decoded.hasPrefix("/home/")

            let surface = Surface(
                id: "claude:\(entry)",
                kind: .claudeCode,
                label: isRealPath ? (decoded as NSString).lastPathComponent : entry,
                detail: decoded,
                projectID: nil,
                pid: nil,
                path: isRealPath ? decoded : nil
            )
            surfaces.append(surface)
        }
        return surfaces
    }

    // MARK: - Browser Tab Discovery

    private func discoverBrowserTabs() -> [Surface] {
        var surfaces: [Surface] = []

        // Safari
        let safariScript = """
        set output to ""
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabName to name of t
                    set tabURL to URL of t
                    set output to output & tabName & "|||" & tabURL & linefeed
                end repeat
            end repeat
        end tell
        return output
        """
        let safariTabs = parseTabOutput(runAppleScript(safariScript), browser: "Safari")
        surfaces.append(contentsOf: safariTabs)

        // Chrome
        let chromeScript = """
        set output to ""
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabName to title of t
                    set tabURL to URL of t
                    set output to output & tabName & "|||" & tabURL & linefeed
                end repeat
            end repeat
        end tell
        return output
        """
        let chromeTabs = parseTabOutput(runAppleScript(chromeScript), browser: "Chrome")
        surfaces.append(contentsOf: chromeTabs)

        // Arc
        let arcScript = """
        set output to ""
        tell application "System Events"
            if not (exists process "Arc") then return ""
        end tell
        tell application "Arc"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabName to title of t
                    set tabURL to URL of t
                    set output to output & tabName & "|||" & tabURL & linefeed
                end repeat
            end repeat
        end tell
        return output
        """
        let arcTabs = parseTabOutput(runAppleScript(arcScript), browser: "Arc")
        surfaces.append(contentsOf: arcTabs)

        return surfaces
    }

    private func parseTabOutput(_ raw: String, browser: String) -> [Surface] {
        guard !raw.isEmpty else { return [] }
        var surfaces: [Surface] = []
        let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
        for (idx, line) in lines.enumerated() {
            let parts = line.components(separatedBy: "|||")
            let title = parts.first?.trimmingCharacters(in: .whitespaces) ?? "Tab"
            let url = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

            let surface = Surface(
                id: "browser:\(browser.lowercased()):\(idx)",
                kind: .browserTab,
                label: String(title.prefix(60)),
                detail: url,
                projectID: nil,
                pid: nil,
                path: nil
            )
            surfaces.append(surface)
        }
        return surfaces
    }

    // MARK: - Shell Helpers

    private func runShell(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            Logger.deskfloor.error("Shell command failed: \(error)")
            return ""
        }
    }

    private func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "" }
        let result = script.executeAndReturnError(&error)
        if error != nil { return "" }
        return result.stringValue ?? ""
    }
}
