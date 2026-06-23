import AppKit
import Carbon.HIToolbox

// MARK: - GlobalHotkeyService

/// Registers a single global keyboard shortcut via Carbon's
/// `RegisterEventHotKey`. Calls `onTrigger` on the main actor whenever
/// the registered combo is pressed system-wide.
///
/// Multiple instances can coexist — each instance gets its own hot-key ID
/// and the shared event handler dispatches to whichever instance's ID
/// matches the fired event.
@MainActor
final class GlobalHotkeyService {
    /// Invoked on the main actor when the hotkey fires.
    var onTrigger: (() -> Void)?

    // swiftformat:disable modifierOrder
    /// Carbon refs: accessed on the main actor during normal operation and from
    /// the `nonisolated` deinit at teardown (which has exclusive access). Marked
    /// `nonisolated(unsafe)` so strict concurrency permits the deinit to read
    /// these non-Sendable `OpaquePointer`s; there is no real concurrent access.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    // swiftformat:enable modifierOrder
    private var currentShortcut: HotkeyShortcut?
    private let instanceId: UInt32

    /// Counter for generating unique hot-key IDs across instances.
    private static var nextInstanceId: UInt32 = 0

    /// Carbon four-char signature for our hotkey IDs.
    private static let signature: OSType = {
        let chars = Array("BBHK".utf8)
        return chars.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    init() {
        Self.nextInstanceId += 1
        self.instanceId = Self.nextInstanceId
    }

    /// Registers the given shortcut. Replaces any existing registration.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        self.unregister()
        self.installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: self.instanceId)
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
        DiagnosticsLogger.app.info("GlobalHotkeyService[\(self.instanceId)]: registered \(shortcut.displayString)")
        return true
    }

    /// Unregisters the current shortcut, if any, and tears down the installed
    /// Carbon event handler so this instance never outlives its handler (which
    /// would leave a dangling `Unmanaged` pointer for the next hot-key press).
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            self.currentShortcut = nil
            DiagnosticsLogger.app.info("GlobalHotkeyService[\(self.instanceId)]: unregistered")
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Removes the Carbon hot-key and event handler when the service is
    /// deallocated. `deinit` on a `@MainActor` class is `nonisolated` in
    /// Swift 6; reading the instance's own stored Carbon refs and passing them
    /// to these plain C calls is permitted here and needs no actor hop. We do
    /// NOT call the MainActor-isolated `unregister()` from `deinit`.
    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
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
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }

                // Filter by instance ID: a single application-level event
                // handler is fired for ALL hot-key presses, not just ours.
                var firedID = EventHotKeyID()
                let getStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &firedID
                )
                guard getStatus == noErr else { return noErr }

                // Carbon hot-key events are dispatched on the main thread by
                // the AppKit event loop, so we can safely assume MainActor
                // isolation to call the (MainActor-bound) trigger closure.
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    guard firedID.id == service.instanceId else { return }
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
