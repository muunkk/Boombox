import AppKit
import Carbon.HIToolbox

// MARK: - GlobalHotkeyService

/// Registers a single global keyboard shortcut via Carbon's
/// `RegisterEventHotKey`. Calls `onTrigger` on the main actor whenever
/// the registered combo is pressed system-wide.
@MainActor
final class GlobalHotkeyService {
    /// Invoked on the main actor when the hotkey fires.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentShortcut: HotkeyShortcut?

    /// Carbon four-char signature for our hotkey IDs.
    private static let signature: OSType = {
        let chars = Array("BBHK".utf8)
        return chars.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    /// Registers the given shortcut. Replaces any existing registration.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        self.unregister()
        self.installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            DiagnosticsLogger.app.error("GlobalHotkeyService: register failed status=\(status)")
            return false
        }

        self.hotKeyRef = ref
        self.currentShortcut = shortcut
        DiagnosticsLogger.app.info("GlobalHotkeyService: registered \(shortcut.displayString)")
        return true
    }

    /// Unregisters the current shortcut, if any.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            self.currentShortcut = nil
            DiagnosticsLogger.app.info("GlobalHotkeyService: unregistered")
        }
    }

    private func installEventHandlerIfNeeded() {
        guard self.eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                // Carbon hot-key events are dispatched on the main thread by
                // the AppKit event loop, so we can safely assume MainActor
                // isolation to call the (MainActor-bound) trigger closure.
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    service.onTrigger?()
                }
                return noErr
            },
            1,
            &spec,
            userInfo,
            &handlerRef
        )

        if status == noErr {
            self.eventHandler = handlerRef
        } else {
            DiagnosticsLogger.app.error("GlobalHotkeyService: InstallEventHandler failed status=\(status)")
        }
    }
}
