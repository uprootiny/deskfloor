import AppKit
import Foundation

/// Reusable action helpers for the launcher and app.
/// Absorbed from the launcher project's LauncherKit/Actions.swift,
/// extended with clipboard, paste, URL, and clone operations.
struct Actions {

    /// Copy text to the system clipboard.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Paste text into the frontmost app by writing to clipboard then simulating Cmd+V.
    static func paste(_ text: String) {
        copyToClipboard(text)
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Open a URL in the default browser.
    static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Clone a GitHub repo into ~/Nissan/ via iTerm.
    static func cloneRepo(name: String, owner: String = "uprootiny") {
        DeskfloorApp.openInITerm("cd ~/Nissan && gh repo clone \(owner)/\(name)")
    }
}
