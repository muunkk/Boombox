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

    init(playerService: PlayerService, webKitManager: WebKitManager) {
        self.playerService = playerService
        self.webKitManager = webKitManager
        super.init()
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
        }
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

        let rootView = MenuBarPlayerView()
            .environment(playerService)
            .environment(webKitManager)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rootView)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        // Dismiss on outside click without relying solely on .transient (which
        // can stay open if the user clicks back into our own app).
        self.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPopover()
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
    }
}
