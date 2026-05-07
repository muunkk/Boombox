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
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Boombox")
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

        let rootView = MenuBarPlayerView(openApp: { [weak self] in
            self?.openMainAppWindow()
        })
        .scrollIndicators(.hidden)
        .environment(playerService)
        .environment(webKitManager)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

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
        let currentSlider = VolumeCurve.sliderValue(forOutputVolume: player.volume)
        let proposed = currentSlider + Double(delta) * sensitivity
        let clamped = max(0, min(1, proposed))
        guard abs(clamped - currentSlider) > 0.001 else { return }

        let hitBoundary = (currentSlider > 0 && clamped == 0)
            || (currentSlider < 1 && clamped == 1)

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
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
        if let monitor = self.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            self.scrollMonitor = nil
        }
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
