import Carbon.HIToolbox

/// Глобальное сочетание ⌥⌘K. Через Carbon: работает без разрешения «Универсальный доступ».
final class HotKey {
    static let display = "⌥⌘K"

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// nil, если сочетание уже занято другим приложением.
    init?(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, info in
            guard let info else { return noErr }
            Unmanaged<HotKey>.fromOpaque(info).takeUnretainedValue().action()
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
                                  Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4B4C444B), id: 1)   // 'KLDK'
        guard RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(optionKey | cmdKey), id,
                                  GetApplicationEventTarget(), 0, &ref) == noErr else {
            RemoveEventHandler(handler)
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
