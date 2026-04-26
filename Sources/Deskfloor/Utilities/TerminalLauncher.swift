import AppKit
import Foundation

/// Spawns a new terminal window and runs a shell command inside it.
///
/// Detection order: Ghostty → iTerm → Terminal.app.
/// The window stays open after the command exits (drops into an interactive zsh).
enum TerminalLauncher {
    enum Backend: String {
        case ghostty, iterm, terminal
    }

    /// Run `command` in a new terminal window. If `workDir` is given, `cd` into it first.
    /// `claudePATH` is prepended so resumed Claude sessions find the right binary.
    static func run(_ command: String, in workDir: String? = nil) {
        let script = makeScript(command: command, workDir: workDir)
        let url = writeTempScript(script)

        switch detectBackend() {
        case .ghostty: launchGhostty(scriptURL: url)
        case .iterm:   launchITerm(scriptPath: url.path)
        case .terminal: launchTerminal(scriptPath: url.path)
        }
    }

    static func detectBackend() -> Backend {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Applications/Ghostty.app") { return .ghostty }
        if fm.fileExists(atPath: "/Applications/iTerm.app") { return .iterm }
        return .terminal
    }

    // MARK: - Script

    private static func makeScript(command: String, workDir: String?) -> String {
        // The trailing `exec /bin/zsh -i` keeps the window alive after the command exits,
        // so the user can read errors / re-run / pivot.
        var lines: [String] = [
            "#!/bin/zsh",
            "source ~/.zshrc 2>/dev/null",
            // Ensure claude / gh / nix are on PATH even if .zshrc didn't run cleanly.
            "export PATH=\"$HOME/.nix-profile/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\""
        ]
        if let workDir, !workDir.isEmpty {
            lines.append("cd \(shellEscape(workDir)) || { echo \"cd failed: \(workDir)\"; exec /bin/zsh -i; }")
        }
        lines.append(command)
        lines.append("exec /bin/zsh -i")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeTempScript(_ contents: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("dskl-\(UUID().uuidString.prefix(8)).sh")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.path
        )
        return url
    }

    // MARK: - Backends

    private static func launchGhostty(scriptURL: URL) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-na", "Ghostty.app", "--args", "-e", scriptURL.path]
        try? task.run()
    }

    private static func launchITerm(scriptPath: String) {
        let escaped = scriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "iTerm"
            activate
            create window with default profile command "/bin/zsh \\"\(escaped)\\""
        end tell
        """
        runAppleScript(source)
    }

    private static func launchTerminal(scriptPath: String) {
        let escaped = scriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "/bin/zsh \\"\(escaped)\\""
        end tell
        """
        runAppleScript(source)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let s = NSAppleScript(source: source) {
            s.executeAndReturnError(&error)
            if let error {
                NSLog("[TerminalLauncher] AppleScript error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Single-quote a string for safe shell embedding. Embedded single quotes
    /// are escaped via the close-quote/escaped-quote/open-quote idiom.
    static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Top-level alias so callsites read tersely: `Sh.q(host)`.
enum Sh {
    static func q(_ s: String) -> String { TerminalLauncher.shellEscape(s) }
}
