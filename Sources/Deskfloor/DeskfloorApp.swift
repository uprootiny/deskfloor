import SwiftUI
import AppKit

@main
struct DeskfloorApp: App {
    @State private var store = ProjectStore()
    @State private var fleet = FleetStore()
    @State private var promptStore = PromptStore()
    @State private var historyStore = HistoryStore()
    @State private var frecency = FrecencyTracker()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main dashboard window
        WindowGroup("Deskfloor", id: "dashboard") {
            ContentView(store: store, fleet: fleet)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    // Wire stores to AppDelegate for launcher access
                    appDelegate.store = store
                    appDelegate.fleet = fleet
                    appDelegate.promptStore = promptStore
                    appDelegate.historyStore = historyStore
                    appDelegate.frecency = frecency
                    fleet.startPolling()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import from GitHub") {
                    NotificationCenter.default.post(name: .importFromGitHub, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import Harvested Prompts") {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Nissan/harvested-prompts.json")
                    if let count = try? PromptImporter.importHarvested(from: url, into: promptStore) {
                        NSLog("[Deskfloor] Imported \(count) prompts from harvest")
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        // Menu bar presence
        MenuBarExtra("Deskfloor", systemImage: "square.grid.3x3.topleft.filled") {
            Button("Open Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Open Launcher (Option+Space)") {
                appDelegate.toggleLauncher()
            }
            .keyboardShortcut(" ", modifiers: [.option])

            Divider()

            if fleet.isReachable {
                ForEach(fleet.hosts) { host in
                    Button("\(host.sigil) \(host.name) — load \(String(format: "%.1f", host.load)), disk \(host.diskPercent)%") {
                        Self.sshJump(host: host.name)
                    }
                }
            } else {
                Text("Fleet unreachable")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Actions

    static func sshJump(host: String, session: String? = nil) {
        let cmd: String
        if let session, session != "main" {
            cmd = "ssh -o RemoteCommand=none -t \(host) tmux attach-session -t \(session)"
        } else {
            cmd = "ssh \(host)"
        }
        openInITerm(cmd)
    }

    /// Dispatch context to a new Claude Code session.
    /// Writes context to a temp file, passes as initial prompt to claude CLI.
    static func dispatchToAgent(context: String, workDir: String? = nil) {
        // Write context to temp file that claude can read
        let tempDir = FileManager.default.temporaryDirectory
        let contextFile = tempDir.appendingPathComponent("deskfloor-dispatch-\(UUID().uuidString.prefix(8)).md")
        try? context.write(to: contextFile, atomically: true, encoding: .utf8)

        // Also copy to clipboard as backup
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context, forType: .string)

        // claude takes a positional prompt argument
        // Escape single quotes in context for shell
        let escaped = context
            .replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Truncate if too long for command line (use file for long contexts)
        var cmd = ""
        if let dir = workDir {
            cmd += "cd \(dir) && "
        }

        if context.count > 4000 {
            // Long context: tell claude to read the file
            cmd += "claude 'Read \(contextFile.path) and proceed with the tasks described there.'"
        } else {
            // Short context: pass directly as prompt
            cmd += "claude '\(escaped)'"
        }

        openInITerm(cmd)
    }

    static func openInITerm(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Source profile to get nix, claude, gh, etc. on PATH
        let fullCmd = "source ~/.zshrc 2>/dev/null; export PATH=\\\"$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH\\\"; \(escaped)"

        let script = """
        tell application "iTerm"
            activate
            create window with default profile command "/bin/zsh -l -c \\"\(fullCmd); exec /bin/zsh\\""
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    static func executeAction(_ item: LauncherItem, promptStore: PromptStore? = nil, frecency: FrecencyTracker? = nil) {
        frecency?.recordAccess(itemID: item.id)
        switch item {
        case .host(let h):
            sshJump(host: h.name)
        case .session(let h, let s):
            sshJump(host: h.name, session: s.name)
        case .project(let p):
            if let localPath = p.localPath {
                // Launch Claude Code session in the project directory
                openInITerm("cd \(localPath) && claude")
            } else if let repo = p.repo, let url = URL(string: "https://github.com/\(repo)") {
                NSWorkspace.shared.open(url)
            }
        case .command(_, let cmd):
            openInITerm(cmd)
        case .prompt(let p):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(p.content, forType: .string)
            promptStore?.recordUse(id: p.id)
        case .historyCommand(let h):
            openInITerm(h.command)
        }
    }
}

// MARK: - AppDelegate (hotkey + panel lifecycle)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private let panelController = LauncherWindowController()

    // These are set by the App struct via onAppear or similar
    var store: ProjectStore?
    var fleet: FleetStore?
    var promptStore: PromptStore?
    var historyStore: HistoryStore?
    var frecency: FrecencyTracker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't hide from Dock yet — keep visible during development
        // NSApp.setActivationPolicy(.accessory)

        // Initialize fleet eagerly
        if fleet == nil {
            fleet = FleetStore()
        }
        fleet?.startPolling()

        // Register global hotkey: Option+Space
        hotkeyManager.onTrigger = { [weak self] in
            self?.toggleLauncher()
        }
        hotkeyManager.register()
        NSLog("[Deskfloor] Hotkey registered: Control+Space")
    }

    func toggleLauncher() {
        NSLog("[Deskfloor] toggleLauncher called, visible=\(panelController.isVisible)")
        if panelController.isVisible {
            panelController.hide()
        } else {
            // Use wired stores — if not yet wired (window hasn't appeared), use defaults
            if store == nil {
                NSLog("[Deskfloor] WARNING: stores not yet wired from ContentView — using defaults")
                store = ProjectStore()
                fleet = FleetStore()
                promptStore = PromptStore()
                historyStore = HistoryStore()
                fleet?.startPolling()
            }

            let store = self.store!
            let fleet = self.fleet!
            let promptStore = self.promptStore!
            let historyStore = self.historyStore!
            NSLog("[Deskfloor] Showing launcher with \(store.projects.count) projects, \(fleet.hosts.count) hosts")

            let launcherView = LauncherPanelView(
                store: store,
                fleet: fleet,
                promptStore: promptStore,
                historyStore: historyStore,
                onDismiss: { [weak self] in
                    self?.panelController.hide()
                },
                onAction: { [weak self] item in
                    DeskfloorApp.executeAction(item, promptStore: self?.promptStore, frecency: self?.frecency)
                    self?.panelController.hide()
                }
            )

            panelController.show(with: launcherView)
        }
    }
}

extension Notification.Name {
    static let importFromGitHub = Notification.Name("importFromGitHub")
    static let projectStatusChange = Notification.Name("projectStatusChange")
}
