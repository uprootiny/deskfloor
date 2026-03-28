import AppKit
import SwiftUI

/// Floating NSPanel that hosts the launcher search UI.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages showing/hiding the launcher panel.
final class LauncherWindowController {
    private var panel: LauncherPanel?
    private var clickMonitor: Any?
    private var escapeMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle<V: View>(with rootView: V) {
        if isVisible {
            hide()
        } else {
            show(with: rootView)
        }
    }

    func show<V: View>(with rootView: V) {
        if panel == nil {
            let p = LauncherPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            panel = p
        }

        panel?.contentView = NSHostingView(rootView: rootView)

        // Center horizontally, upper third vertically
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 600) / 2
            let y = screen.frame.height * 0.6
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Fade in
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        // Click-outside dismisses
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                self.hide()
            }
        }
    }

    func hide() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        })
    }
}
