import AppKit
import SwiftUI

// MARK: - MenuBarController

/// Owns the optional menu bar status item and its popover-hosted player.
/// Created lazily; only allocates an `NSStatusItem` when enabled so users
/// who don't opt in pay zero menu-bar real-estate cost.
@MainActor
final class MenuBarController: NSObject {
    private weak var playerService: PlayerService?
    private weak var webKitManager: WebKitManager?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    /// Local scrollWheel monitor active only while the popover is visible.
    /// Routes scrolls inside the popover to volume changes.
    private var scrollMonitor: Any?

    /// Running slider target accumulated synchronously across scroll events so
    /// a burst of trackpad scroll events accumulates off the in-progress value
    /// rather than the async-lagged `player.volume`. Reset when the popover
    /// closes. See P2F001 (lost-update race).
    private var pendingSliderTarget: Double?

    private let hotkeyService = GlobalHotkeyService()

    init(playerService: PlayerService, webKitManager: WebKitManager) {
        self.playerService = playerService
        self.webKitManager = webKitManager
        super.init()
        self.hotkeyService.onTrigger = { [weak self] in
            self?.togglePopover()
        }
    }

    // No deinit cleanup: NSStatusItem and the global event monitor are torn
    // down explicitly via `setEnabled(false)`. The controller itself lives
    // for the duration of the app.

    // MARK: - Public API

    /// Enables or disables the menu bar item.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            self.installStatusItem()
        } else {
            self.removeStatusItem()
            self.hotkeyService.unregister()
        }
    }

    /// Registers (or unregisters) the global toggle hotkey. The hotkey only
    /// works while the menu bar item is enabled, since the popover is anchored
    /// to its status item.
    func applyHotkey(_ shortcut: HotkeyShortcut?, menuBarEnabled: Bool) {
        guard menuBarEnabled, let shortcut else {
            self.hotkeyService.unregister()
            return
        }
        self.hotkeyService.register(shortcut)
    }

    /// Toggles the popover; used by the hotkey trigger.
    func togglePopover() {
        // Without a status item we have nothing to anchor to.
        guard self.statusItem != nil else { return }
        self.statusItemClicked(nil)
    }

    // MARK: - Status Item Lifecycle

    private func installStatusItem() {
        guard self.statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "radio.fill", accessibilityDescription: "Boombox")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(self.statusItemClicked(_:))
            button.toolTip = String(localized: "Boombox")
        }
        self.statusItem = item

        DiagnosticsLogger.app.info("MenuBarController: installed status item")
    }

    private func removeStatusItem() {
        self.dismissPopover()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            DiagnosticsLogger.app.info("MenuBarController: removed status item")
        }
        self.statusItem = nil
    }

    // MARK: - Popover Lifecycle

    @objc private func statusItemClicked(_: Any?) {
        if let popover = self.popover, popover.isShown {
            self.dismissPopover()
        } else {
            self.presentPopover()
        }
    }

    private func presentPopover() {
        guard let button = self.statusItem?.button,
              let playerService = self.playerService,
              let webKitManager = self.webKitManager
        else {
            return
        }

        // Defensively remove any monitors left over from a previous popover that
        // closed via a path bypassing dismissPopover() (e.g. Esc, Cmd-Tab, or
        // app deactivation while .transient auto-closes). Without this, a second
        // present would overwrite the monitor references and leak the old pair.
        self.removeEventMonitors()

        let rootView = MenuBarPlayerView(openApp: { [weak self] in
            self?.openMainAppWindow()
        })
        .scrollIndicators(.hidden)
        .environment(playerService)
        .environment(webKitManager)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // Clean up monitors promptly when .transient closes the popover via a
        // path that doesn't route through dismissPopover() (Esc, Cmd-Tab, etc.).
        popover.delegate = self

        let hostingController = NSHostingController(rootView: rootView)
        // Track SwiftUI's intrinsic content size so the popover grows when the
        // queue list expands.
        hostingController.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        popover.contentViewController = hostingController

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        // Dismiss on outside click without relying solely on .transient (which
        // can stay open if the user clicks back into our own app).
        self.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPopover()
            }
        }

        // Volume-on-scroll: any scroll inside the popover adjusts volume.
        self.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let popoverWindow = self.popover?.contentViewController?.view.window,
                  event.window === popoverWindow
            else {
                return event
            }
            Task { @MainActor in
                self.handleVolumeScroll(event)
            }
            return event
        }
    }

    /// Adjusts volume continuously based on a scroll wheel event delivered
    /// to the popover window.
    private func handleVolumeScroll(_ event: NSEvent) {
        guard let player = self.playerService else { return }
        let delta: CGFloat = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return }

        let sensitivity = 0.01
        // Accumulate off the running target (updated synchronously below) so a
        // burst of scroll events does not all read the same async-lagged
        // `player.volume`. Falls back to the committed volume for the first
        // event of a gesture. See P2F001.
        let currentSlider = self.pendingSliderTarget ?? VolumeCurve.sliderValue(forOutputVolume: player.volume)
        let proposed = currentSlider + Double(delta) * sensitivity
        let clamped = max(0, min(1, proposed))
        guard abs(clamped - currentSlider) > 0.001 else { return }

        let hitBoundary = (currentSlider > 0 && clamped == 0)
            || (currentSlider < 1 && clamped == 1)

        // Commit the new target synchronously before deferring the write so the
        // next event in the burst reads this value, not the lagging volume.
        self.pendingSliderTarget = clamped

        Task { @MainActor in
            await player.setVolume(VolumeCurve.outputVolume(forSliderValue: clamped))
            if hitBoundary {
                HapticService.sliderBoundary()
            }
        }
    }

    private func dismissPopover() {
        self.popover?.performClose(nil)
        self.popover = nil
        self.removeEventMonitors()
    }

    /// Removes the popover's global mouse-down and local scroll monitors if
    /// installed. Safe to call repeatedly.
    private func removeEventMonitors() {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
        if let monitor = self.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            self.scrollMonitor = nil
        }
        // Drop the running scroll target so the next popover session starts
        // accumulating from the actual committed volume. See P2F001.
        self.pendingSliderTarget = nil
    }

    /// Brings the Boombox main window forward and dismisses the popover.
    private func openMainAppWindow() {
        self.dismissPopover()
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Prefer the autosaved main window; fall back to any main-capable window.
        let windows = NSApplication.shared.windows
        if let main = windows.first(where: { $0.frameAutosaveName == "BoomboxMainWindow" }) {
            main.makeKeyAndOrderFront(nil)
            return
        }
        if let any = windows.first(where: { $0.canBecomeMain }) {
            any.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {
    /// Fired whenever the popover closes, including the .transient auto-close
    /// paths (Esc, app deactivation) that bypass dismissPopover(). Ensures the
    /// event monitors are always torn down so they can't accumulate.
    func popoverDidClose(_: Notification) {
        self.popover = nil
        self.removeEventMonitors()
    }
}
