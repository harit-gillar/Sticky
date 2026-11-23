import AppKit
import Carbon.HIToolbox

/// Registers a global hotkey (⌥⇧S) to show/hide all sticky windows.
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register() {
        let hotKeyID = EventHotKeyID(signature: 0x5354_4B59, id: 1) // "STKY"
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // ⌥⇧S, or ⌃⌥⇧S in Debug so a dev build can run beside the real app
#if DEBUG
        let modifiers = optionKey | shiftKey | controlKey
#else
        let modifiers = optionKey | shiftKey
#endif
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { GlobalHotkeyManager.shared.toggle() }
                return OSStatus(noErr)
            },
            1, &eventSpec, nil, &eventHandlerRef
        )
    }

    private func toggle() {
        let windows = NSApplication.shared.windows.filter { $0.styleMask.contains(.titled) }
        let anyVisible = windows.contains { $0.isVisible }
        if anyVisible {
            windows.forEach { $0.orderOut(nil) }
        } else {
            windows.forEach { $0.orderFrontRegardless() }
        }
    }
}
