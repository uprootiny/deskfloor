import Carbon.HIToolbox
import Foundation

/// Registers a global hotkey via Carbon API. Works without accessibility permissions.
final class HotkeyManager {
    // Modifier-mask constants exposed so callers don't need to import Carbon.HIToolbox
    // (which pollutes the namespace and triggers SwiftUI type-check timeouts).
    static let modControl: UInt32 = UInt32(controlKey)
    static let modCommand: UInt32 = UInt32(cmdKey)
    static let modOption: UInt32  = UInt32(optionKey)
    static let modShift: UInt32   = UInt32(shiftKey)

    // Common key codes
    static let kcSpace: UInt32 = 49
    static let kcL: UInt32 = 37

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var ownID: UInt32 = 0           // which Carbon hotkey id this manager owns
    var onTrigger: (() -> Void)?

    /// Register a global hotkey. Default: Control+Space (keyCode 49, controlKey).
    /// Option+Space conflicts with macOS input source switching on some setups.
    /// `id` lets multiple HotkeyManager instances coexist without colliding on the
    /// (signature, id) tuple Carbon keys hotkeys by — and the handler filters by
    /// id at dispatch time, since one EventHandler on GetApplicationEventTarget()
    /// fires for *every* kEventHotKeyPressed regardless of which hotkey caused it.
    func register(keyCode: UInt32 = 49, modifiers: UInt32 = UInt32(controlKey), id: UInt32 = 1) {
        unregister()
        self.ownID = id

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, eventRef: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
                var firedID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &firedID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Only fire for our own hotkey id; let other managers handle theirs.
                guard firedID.id == mgr.ownID else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { mgr.onTrigger?() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x44464C52), // "DFLR"
            id: id
        )

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
