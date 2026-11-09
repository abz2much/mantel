import Carbon

/// A system-wide keyboard shortcut through macOS's hot-key registration, which needs no permission.
@MainActor
final class GlobalHotKey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    convenience init(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.init(keyCode: UInt32(shortcut.keyCode), modifiers: shortcut.carbonModifiers, action: action)
    }

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    var isRegistered: Bool { hotKey != nil }

    /// Whether `shortcut` can be registered right now (no other app owns it). Leaves nothing registered.
    static func isAvailable(_ shortcut: Shortcut) -> Bool {
        let probe = GlobalHotKey(shortcut) {}
        probe.register()
        defer { probe.unregister() }
        return probe.isRegistered
    }
    var hasHandler: Bool { handler != nil }

    /// Does nothing if already registered. If another app owns the shortcut, nothing is left installed.
    func register() {
        guard hotKey == nil, handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
            return noErr
        }, 1, &type, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x4D4E544C), id: 1)   // "MNTL"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil
            if let handler { RemoveEventHandler(handler) }
            handler = nil
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
