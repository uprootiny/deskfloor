import SwiftUI
import AppKit

@main
struct DeskfloorApp: App {
    @State private var store = ProjectStore()
    @State private var fleet = FleetStore()
    @State private var promptStore = PromptStore()
    @State private var historyStore = HistoryStore()
    @State private var frecency = FrecencyTracker()
    @State private var sessionRegistry = SessionRegistry()
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
                    appDelegate.sessionRegistry = sessionRegistry
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

            Button("Open Launcher (⌃Space)") {
                appDelegate.toggleLauncher()
            }
            .keyboardShortcut(" ", modifiers: [.control])

            Divider()

            // Punch-through: open Claude Code on this app's own repo, ready to take direction.
            Button("Engineer this Launcher (⌥⌘L)") {
                Self.engineerThisLauncher(registry: sessionRegistry)
            }
            .keyboardShortcut("l", modifiers: [.option, .command])

            Button("Refresh Session Index") {
                sessionRegistry.refresh()
            }

            Button("Diagnostics → Console") {
                NSLog("[Deskfloor]\n\(sessionRegistry.diagnosticSummary())")
                NSLog("[Deskfloor] Toggle hotkey: ⌃Space (kc 49 + controlKey)")
                NSLog("[Deskfloor] Engineer hotkey: ⌥⌘L (kc 37 + cmdKey|optionKey)")
                NSLog("[Deskfloor] Terminal backend: \(TerminalLauncher.detectBackend().rawValue)")
            }

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
            cmd = "ssh -o RemoteCommand=none -t \(Sh.q(host)) tmux attach-session -t \(Sh.q(session))"
        } else {
            cmd = "ssh \(Sh.q(host))"
        }
        TerminalLauncher.run(cmd)
    }

    /// Punch-through: open Claude Code on the deskfloor repo itself, resuming the
    /// most-recent session if one exists. Walks up parent dirs (most engineering
    /// context lives in ~/Nissan, not the deskfloor subdir) and falls back to fresh.
    static func engineerThisLauncher(registry: SessionRegistry) {
        let target = NSString(string: "~/Nissan/deskfloor").expandingTildeInPath
        let candidates = [
            target,
            NSString(string: "~/Nissan").expandingTildeInPath,
            NSString(string: "~").expandingTildeInPath
        ]
        for candidate in candidates {
            if let session = registry.mostRecent(forCwd: candidate) {
                NSLog("[Deskfloor] Engineer-this resuming \(session.uuid.prefix(8)) from \(candidate) (\(session.byteSize / 1024) KB)")
                TerminalLauncher.run("claude --resume \(session.uuid)", in: target)
                return
            }
        }
        NSLog("[Deskfloor] Engineer-this opening fresh claude session in \(target)")
        TerminalLauncher.run("claude", in: target)
    }

    /// Open Claude Code in a project, preferring to resume its most-recent session.
    static func openClaudeForProject(_ project: Project, registry: SessionRegistry?, mode: ClaudeOpenMode = .resumeRecent) {
        guard let path = project.localPath else {
            if let repo = project.repo, let url = URL(string: "https://github.com/\(repo)") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let cmd: String
        switch mode {
        case .resumeRecent:
            if let session = registry?.mostRecent(forCwd: path) {
                cmd = "claude --resume \(session.uuid)"
            } else {
                cmd = "claude"
            }
        case .resumeSpecific(let uuid):
            cmd = "claude --resume \(uuid)"
        case .fresh:
            cmd = "claude"
        case .freshWithPrimer(let primerPath):
            // Single-quote the path inside the prompt; escape embedded single quotes.
            let safePath = primerPath.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "claude 'Read '\\''\(safePath)'\\'' and orient yourself, then ask what to do next.'"
        }
        TerminalLauncher.run(cmd, in: path)
    }

    enum ClaudeOpenMode {
        case resumeRecent
        case resumeSpecific(uuid: String)
        case fresh
        case freshWithPrimer(path: String)
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

        let cmd: String
        if context.count > 4000 {
            // Long context: tell claude to read the file
            cmd = "claude 'Read \(contextFile.path) and proceed with the tasks described there.'"
        } else {
            // Short context: pass directly as prompt
            let escaped = context.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "claude '\(escaped)'"
        }

        TerminalLauncher.run(cmd, in: workDir)
    }

    /// Back-compat shim — older callsites pass a single shell command and expect
    /// it to run in a terminal. Routed through TerminalLauncher.
    static func openInITerm(_ command: String) {
        TerminalLauncher.run(command)
    }

    static func executeAction(_ item: LauncherItem, promptStore: PromptStore? = nil, frecency: FrecencyTracker? = nil, sessionRegistry: SessionRegistry? = nil) {
        frecency?.recordAccess(itemID: item.id)
        switch item {
        case .host(let h):
            sshJump(host: h.name)
        case .session(let h, let s):
            sshJump(host: h.name, session: s.name)
        case .project(let p):
            openClaudeForProject(p, registry: sessionRegistry, mode: .resumeRecent)
        case .command(_, let cmd):
            TerminalLauncher.run(cmd)
        case .prompt(let p):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(p.content, forType: .string)
            promptStore?.recordUse(id: p.id)
        case .historyCommand(let h):
            TerminalLauncher.run(h.command)
        }
    }
}

// MARK: - AppDelegate (hotkey + panel lifecycle)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let toggleHotkey = HotkeyManager()
    private let engineerHotkey = HotkeyManager()
    private let panelController = LauncherWindowController()

    // These are set by the App struct via onAppear or similar
    var store: ProjectStore?
    var fleet: FleetStore?
    var promptStore: PromptStore?
    var historyStore: HistoryStore?
    var frecency: FrecencyTracker?
    var sessionRegistry: SessionRegistry?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't hide from Dock yet — keep visible during development
        // NSApp.setActivationPolicy(.accessory)

        // Initialize fleet eagerly
        if fleet == nil {
            fleet = FleetStore()
        }
        fleet?.startPolling()

        // Toggle launcher: ⌃Space
        toggleHotkey.onTrigger = { [weak self] in
            self?.toggleLauncher()
        }
        toggleHotkey.register(keyCode: HotkeyManager.kcSpace, modifiers: HotkeyManager.modControl, id: 1)
        NSLog("[Deskfloor] Hotkey registered: ⌃Space → toggle launcher")

        // Engineer this Launcher: ⌥⌘L
        engineerHotkey.onTrigger = { [weak self] in
            let registry = self?.sessionRegistry ?? SessionRegistry()
            DeskfloorApp.engineerThisLauncher(registry: registry)
        }
        engineerHotkey.register(
            keyCode: HotkeyManager.kcL,
            modifiers: HotkeyManager.modCommand | HotkeyManager.modOption,
            id: 2
        )
        NSLog("[Deskfloor] Hotkey registered: ⌥⌘L → engineer this launcher")
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

            let registry = self.sessionRegistry ?? SessionRegistry()
            self.sessionRegistry = registry
            registry.refresh()

            let launcherView = LauncherPanelView(
                store: store,
                fleet: fleet,
                promptStore: promptStore,
                historyStore: historyStore,
                sessionRegistry: registry,
                onDismiss: { [weak self] in
                    self?.panelController.hide()
                },
                onAction: { [weak self] item in
                    DeskfloorApp.executeAction(
                        item,
                        promptStore: self?.promptStore,
                        frecency: self?.frecency,
                        sessionRegistry: self?.sessionRegistry
                    )
                    self?.panelController.hide()
                },
                onProjectAction: { [weak self] project, mode in
                    DeskfloorApp.openClaudeForProject(project, registry: self?.sessionRegistry, mode: mode)
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
    static let navigateToProject = Notification.Name("navigateToProject")
}
