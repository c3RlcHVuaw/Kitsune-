#if os(macOS)
import Carbon.HIToolbox

/// System-wide ⌥⌘K. Carbon's hot-key API needs no accessibility permission.
@MainActor enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    static var action: () -> Void = {}

    static func set(enabled: Bool) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard enabled else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in Hotkey.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x4B545355, id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}
#endif
