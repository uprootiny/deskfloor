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
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))
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

    static func openInITerm(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "iTerm"
            activate
            create window with default profile command "/bin/zsh -l -c \\"\(escaped); exec /bin/zsh\\""
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
            if let repo = p.repo, let url = URL(string: "https://github.com/\(repo)") {
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
            // Create the launcher view with current stores
            let store = self.store ?? ProjectStore()
            let fleet = self.fleet ?? FleetStore()
            let promptStore = self.promptStore ?? PromptStore()
            let historyStore = self.historyStore ?? HistoryStore()
            NSLog("[Deskfloor] Showing launcher with \(store.projects.count) projects, \(fleet.hosts.count) hosts")

            if !fleet.isReachable && fleet.hosts.isEmpty {
                fleet.fetch()
            }

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
}
