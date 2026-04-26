import AppKit
import ApplicationServices

/// Move/resize the foreground window of any app via the Accessibility API.
///
/// Requires Accessibility permission (System Settings → Privacy → Accessibility →
/// Deskfloor). The first call triggers the permission prompt.
enum WindowTiling {

    /// Each preset describes a fraction of the active screen's visible frame.
    /// (x, y, w, h) where x/y are 0…1 origin from the screen's bottom-left and
    /// w/h are 0…1 of the screen's visible width/height.
    enum Preset: String, CaseIterable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case leftThird, middleThird, rightThird
        case leftTwoThirds, rightTwoThirds
        case topLeft, topRight, bottomLeft, bottomRight
        case center, fill, almostFill

        var label: String {
            switch self {
            case .leftHalf:        return "Tile · Left Half"
            case .rightHalf:       return "Tile · Right Half"
            case .topHalf:         return "Tile · Top Half"
            case .bottomHalf:      return "Tile · Bottom Half"
            case .leftThird:       return "Tile · Left Third"
            case .middleThird:     return "Tile · Middle Third"
            case .rightThird:      return "Tile · Right Third"
            case .leftTwoThirds:   return "Tile · Left Two-Thirds"
            case .rightTwoThirds:  return "Tile · Right Two-Thirds"
            case .topLeft:         return "Tile · Top-Left Quarter"
            case .topRight:        return "Tile · Top-Right Quarter"
            case .bottomLeft:      return "Tile · Bottom-Left Quarter"
            case .bottomRight:     return "Tile · Bottom-Right Quarter"
            case .center:          return "Tile · Center (60% × 60%)"
            case .fill:            return "Tile · Fill"
            case .almostFill:      return "Tile · Almost Fill (96%)"
            }
        }

        /// Origin and size as fractions of the screen's visible frame, with origin
        /// at bottom-left of the visible frame (Cocoa convention).
        var fraction: (x: Double, y: Double, w: Double, h: Double) {
            switch self {
            case .leftHalf:        return (0, 0, 0.5, 1)
            case .rightHalf:       return (0.5, 0, 0.5, 1)
            case .topHalf:         return (0, 0.5, 1, 0.5)
            case .bottomHalf:      return (0, 0, 1, 0.5)
            case .leftThird:       return (0, 0, 1.0/3, 1)
            case .middleThird:     return (1.0/3, 0, 1.0/3, 1)
            case .rightThird:      return (2.0/3, 0, 1.0/3, 1)
            case .leftTwoThirds:   return (0, 0, 2.0/3, 1)
            case .rightTwoThirds:  return (1.0/3, 0, 2.0/3, 1)
            case .topLeft:         return (0, 0.5, 0.5, 0.5)
            case .topRight:        return (0.5, 0.5, 0.5, 0.5)
            case .bottomLeft:      return (0, 0, 0.5, 0.5)
            case .bottomRight:     return (0.5, 0, 0.5, 0.5)
            case .center:          return (0.2, 0.2, 0.6, 0.6)
            case .fill:            return (0, 0, 1, 1)
            case .almostFill:      return (0.02, 0.02, 0.96, 0.96)
            }
        }
    }

    // MARK: - Permission

    /// Returns whether Deskfloor currently has Accessibility permission.
    /// If `prompt` is true and we don't have it, the OS shows the permission dialog.
    @discardableResult
    static func ensurePermission(prompt: Bool = true) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Apply

    /// Apply a preset to the foreground window of the foreground app.
    /// Returns true on success.
    @discardableResult
    static func apply(_ preset: Preset) -> Bool {
        guard ensurePermission(prompt: true) else {
            NSLog("[WindowTiling] no accessibility permission yet — open System Settings → Privacy & Security → Accessibility → enable Deskfloor")
            return false
        }
        guard let window = focusedWindow() else {
            NSLog("[WindowTiling] no focused window")
            return false
        }
        guard let frame = targetFrame(for: window, preset: preset) else {
            NSLog("[WindowTiling] couldn't determine target frame")
            return false
        }
        return setFrame(window: window, frame: frame)
    }

    /// Tile a list of bundle ids' visible windows into N equal columns on the
    /// active screen, in order. Used by "tile-current-terminals" sweep.
    @discardableResult
    static func tileColumns(bundleIDs: [String]) -> Int {
        guard ensurePermission(prompt: true) else { return 0 }
        guard let screen = NSScreen.main else { return 0 }
        let visible = screen.visibleFrame

        var windows: [AXUIElement] = []
        for bid in bundleIDs {
            for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bid {
                let appEl = AXUIElementCreateApplication(app.processIdentifier)
                if let ws = copyAttribute(appEl, kAXWindowsAttribute) as? [AXUIElement] {
                    windows.append(contentsOf: ws.filter { isStandardWindow($0) })
                }
            }
        }

        guard !windows.isEmpty else { return 0 }
        let count = windows.count
        let colW = visible.width / CGFloat(count)
        for (i, w) in windows.enumerated() {
            // AX uses top-left origin in screen coordinates with Y growing down.
            let x = visible.minX + CGFloat(i) * colW
            // Convert Cocoa visibleFrame (bottom-left origin in screen coords) to AX's top-left.
            let screenHeightPlusOriginY = (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
            let yTopLeft = screenHeightPlusOriginY - visible.maxY
            let target = CGRect(x: x, y: yTopLeft, width: colW, height: visible.height)
            _ = setFrameAX(window: w, frame: target)
        }
        return count
    }

    // MARK: - AX plumbing

    private static func focusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let app = copyAttribute(systemWide, kAXFocusedApplicationAttribute) else { return nil }
        let appEl = app as! AXUIElement
        return copyAttribute(appEl, kAXFocusedWindowAttribute) as! AXUIElement?
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        // Reject sheets, modals, palettes by checking AXSubrole or AXRole.
        let role = copyAttribute(window, kAXRoleAttribute) as? String
        return role == kAXWindowRole as String || role == "AXWindow"
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    /// Compute the target frame in AX coordinates (screen top-left origin, Y grows down).
    private static func targetFrame(for window: AXUIElement, preset: Preset) -> CGRect? {
        let screen = screenForWindow(window) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }

        let f = preset.fraction
        // Cocoa: visible has origin at bottom-left. We want target rect in Cocoa first,
        // then convert to AX top-left coords.
        let cocoaOriginX = visible.minX + visible.width * CGFloat(f.x)
        let cocoaOriginY = visible.minY + visible.height * CGFloat(f.y)
        let w = visible.width * CGFloat(f.w)
        let h = visible.height * CGFloat(f.h)

        // Convert Cocoa (bottom-left, primary screen 0,0) to AX (top-left of the
        // entire display arrangement). On a single display, this collapses to:
        //   yTopLeft = primaryScreenHeight - (cocoaOriginY + h)
        // For multi-monitor, we use the highest screen's maxY as the global top.
        let globalTop = (NSScreen.screens.map { $0.frame.maxY }.max() ?? (screen?.frame.maxY ?? 0))
        let yTopLeft = globalTop - (cocoaOriginY + h)
        return CGRect(x: cocoaOriginX, y: yTopLeft, width: w, height: h)
    }

    private static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let pos = readPoint(window, kAXPositionAttribute),
              let size = readSize(window, kAXSizeAttribute) else { return nil }
        let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        // AX center is in top-left coords; convert to Cocoa bottom-left for matching.
        let globalTop = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        let cocoaCenter = CGPoint(x: center.x, y: globalTop - center.y)
        return NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) ?? NSScreen.main
    }

    private static func readPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = copyAttribute(el, attr) else { return nil }
        var pt = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &pt)
        return pt
    }

    private static func readSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = copyAttribute(el, attr) else { return nil }
        var sz = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &sz)
        return sz
    }

    @discardableResult
    private static func setFrame(window: AXUIElement, frame: CGRect) -> Bool {
        return setFrameAX(window: window, frame: frame)
    }

    @discardableResult
    private static func setFrameAX(window: AXUIElement, frame: CGRect) -> Bool {
        var pos = frame.origin
        var size = frame.size
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return false }
        let r1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        let r2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        return r1 == .success && r2 == .success
    }
}
