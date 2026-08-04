import AppKit
import Carbon

/// System-wide hotkey via Carbon (no Accessibility permission required).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void

    /// - Parameters:
    ///   - keyCode: virtual key (e.g. `kVK_ANSI_E`)
    ///   - modifiers: Carbon modifiers (`optionKey`, `cmdKey`, …)
    ///   - handler: invoked on the main queue when pressed
    init(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.handler = handler
        install(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func install(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: 0x54554B55 /* 'TUKU' */, id: 1)

        // Keep self alive for the C callback via unmanaged retain; released in deinit path via handler removal.
        let boxed = Unmanaged.passRetained(CallbackBox(handler: handler))

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { box.handler() }
                return noErr
            },
            1,
            &eventType,
            boxed.toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            boxed.release()
            return
        }

        let reg = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if reg != noErr {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            boxed.release()
        }
        // On success, boxed is retained until process exit (menu bar app lifetime).
        // We intentionally leak one retain for process lifetime — fine for a singleton hotkey.
    }

    private final class CallbackBox {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}
