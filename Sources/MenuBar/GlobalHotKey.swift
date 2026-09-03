import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon `RegisterEventHotKey`: deprecated, still the only public API
/// that works without the Accessibility permission a `CGEventTap` would require.
@MainActor
final class GlobalHotKey {
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?   // touched in deinit only after main-actor setup
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Default ⌃⌥S. Carbon modifiers, not NSEvent ones.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_S), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers on the main thread; assumeIsolated makes the compiler agree.
            MainActor.assumeIsolated { Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x5352_4343) /* "SRCC" */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
