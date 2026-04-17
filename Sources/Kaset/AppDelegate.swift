import AppKit
import UserNotifications

// MARK: - AppDelegate

/// App delegate to control application lifecycle behavior.
/// Keeps the app running when windows are closed so audio playback continues.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reference to the PlayerService for dock menu actions.
    /// Set by KasetApp after initialization.
    weak var playerService: PlayerService?

    /// Reference to the main window for reliable reopen behavior.
    /// Using strong reference to prevent deallocation when window is hidden.
    private var mainWindow: NSWindow?

    /// Current SwiftUI player presentation mode, mirrored from KasetApp for Dock menu labels.
    var currentPlayerPresentationMode: PlayerPresentationMode = .standard

    /// Coordinates same-window resizing for player presentation modes.
    private let playerPresentationWindowCoordinator = PlayerPresentationWindowCoordinator()

    func applicationDidFinishLaunching(_: Notification) {
        DiagnosticsLogger.app.info("AppDelegate: applicationDidFinishLaunching")
        // Set up notification center delegate to show notifications in foreground
        if !UITestConfig.isRunningUnitTests {
            UNUserNotificationCenter.current().delegate = self
        }

        // In UI test mode, activate the app to bring window to foreground
        if UITestConfig.isUITestMode {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        // Set up window delegate to intercept close and hide instead
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.setupWindowDelegate()
        }

        // Register for system sleep/wake notifications
        self.registerForSleepWakeNotifications()

        // Restore saved queue if available
        self.playerService?.restoreQueueFromPersistence()
    }

    func applicationWillTerminate(_: Notification) {
        // Save queue for persistence on next launch
        self.playerService?.saveQueueForPersistence()
        DiagnosticsLogger.player.info("Application will terminate - saved queue for persistence")
    }

    /// Registers for system sleep and wake notifications to handle playback appropriately.
    private func registerForSleepWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(self.systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(self.systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Tracks whether audio was playing before system sleep (for resume on wake).
    private var wasPlayingBeforeSleep: Bool = false

    @objc private func systemWillSleep(_: Notification) {
        // Remember playback state and pause before sleep
        self.wasPlayingBeforeSleep = self.playerService?.isPlaying ?? false
        if self.wasPlayingBeforeSleep {
            DiagnosticsLogger.player.info("System going to sleep, pausing playback")
            SingletonPlayerWebView.shared.pause()
        }
    }

    @objc private func systemDidWake(_: Notification) {
        // Optionally resume playback after wake if it was playing before sleep
        // Note: We don't auto-resume by default as it could be surprising
        // Just log the wake event for now
        DiagnosticsLogger.player.info("System woke from sleep, wasPlayingBeforeSleep: \(self.wasPlayingBeforeSleep)")
    }

    func applicationDidBecomeActive(_: Notification) {
        // When app becomes active (e.g., dock icon clicked), ensure main window is visible.
        self.showMainWindowIfNeeded()
    }

    private func setupWindowDelegate() {
        DiagnosticsLogger.app.info("AppDelegate: setupWindowDelegate starting")
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.delegate = self
            // Enable automatic window frame persistence using autosave name
            // This ensures window size/position is restored across app launches
            if window.frameAutosaveName.isEmpty {
                window.setFrameAutosaveName("YTMPrivateMainWindow")
            }
            // Store reference to main window for reliable reopen
            self.mainWindow = window
        }
    }

    /// Applies app-level window sizing for player presentation mode changes.
    func transitionPlayerPresentationMode(from oldMode: PlayerPresentationMode, to newMode: PlayerPresentationMode) {
        self.playerPresentationWindowCoordinator.transition(from: oldMode, to: newMode)
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        self.addNowPlayingHeader(to: menu)
        menu.addItem(.separator())

        let canControlPlayback = self.playerService?.currentTrack != nil || self.playerService?.pendingPlayVideoId != nil
        let hasCurrentTrack = self.playerService?.currentTrack != nil

        self.addDockMenuItem(
            to: menu,
            title: self.playerService?.isPlaying == true ? "Pause" : "Play",
            action: #selector(dockMenuPlayPause),
            enabled: canControlPlayback
        )
        self.addDockMenuItem(
            to: menu,
            title: "Previous Track",
            action: #selector(dockMenuPrevious),
            enabled: canControlPlayback
        )
        self.addDockMenuItem(
            to: menu,
            title: "Next Track",
            action: #selector(dockMenuNext),
            enabled: canControlPlayback
        )

        menu.addItem(.separator())

        self.addDockMenuItem(
            to: menu,
            title: self.playerService?.currentTrackLikeStatus == .like ? "Unlike" : "Like",
            action: #selector(dockMenuToggleLike),
            enabled: hasCurrentTrack,
            state: self.playerService?.currentTrackLikeStatus == .like ? .on : .off
        )
        self.addDockMenuItem(
            to: menu,
            title: self.playerService?.showLyrics == true ? "Hide Lyrics" : "Show Lyrics",
            action: #selector(dockMenuToggleLyrics),
            enabled: hasCurrentTrack || self.playerService?.showLyrics == true,
            state: self.playerService?.showLyrics == true ? .on : .off
        )
        self.addDockMenuItem(
            to: menu,
            title: self.playerService?.showQueue == true ? "Hide Queue" : "Show Queue",
            action: #selector(dockMenuToggleQueue),
            enabled: self.playerService != nil,
            state: self.playerService?.showQueue == true ? .on : .off
        )

        menu.addItem(.separator())

        self.addDockMenuItem(
            to: menu,
            title: self.currentPlayerPresentationMode == .focus ? "Exit Focus Player" : "Focus Player",
            action: #selector(dockMenuToggleFocusPlayer),
            enabled: hasCurrentTrack || self.currentPlayerPresentationMode == .focus,
            state: self.currentPlayerPresentationMode == .focus ? .on : .off
        )
        self.addDockMenuItem(
            to: menu,
            title: self.currentPlayerPresentationMode == .compact ? "Exit Small Player" : "Small Player",
            action: #selector(dockMenuToggleSmallPlayer),
            enabled: hasCurrentTrack || self.currentPlayerPresentationMode == .compact,
            state: self.currentPlayerPresentationMode == .compact ? .on : .off
        )
        self.addDockMenuItem(
            to: menu,
            title: SettingsManager.shared.showSidebarNowPlayingPanel ? "Hide Now Playing Panel" : "Show Now Playing Panel",
            action: #selector(dockMenuToggleNowPlayingPanel),
            state: SettingsManager.shared.showSidebarNowPlayingPanel ? .on : .off
        )

        return menu
    }

    private func addNowPlayingHeader(to menu: NSMenu) {
        guard let track = self.playerService?.currentTrack else {
            self.addDockMenuItem(to: menu, title: "No Track Playing", enabled: false)
            return
        }

        self.addDockMenuItem(to: menu, title: self.truncatedDockMenuTitle(track.title), enabled: false)

        let artistsDisplay = track.artistsDisplay.isEmpty ? "Unknown Artist" : track.artistsDisplay
        self.addDockMenuItem(to: menu, title: self.truncatedDockMenuTitle(artistsDisplay), enabled: false)
    }

    @discardableResult
    private func addDockMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector? = nil,
        enabled: Bool = true,
        state: NSControl.StateValue = .off
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        item.isEnabled = enabled
        item.state = state
        menu.addItem(item)
        return item
    }

    private func truncatedDockMenuTitle(_ title: String, maxLength: Int = 56) -> String {
        guard title.count > maxLength else { return title }
        return "\(title.prefix(maxLength - 3))..."
    }

    @objc private func dockMenuPlayPause() {
        guard let playerService else {
            // Fallback to direct WebView control if PlayerService not available
            SingletonPlayerWebView.shared.playPause()
            return
        }
        Task {
            await playerService.playPause()
        }
    }

    @objc private func dockMenuNext() {
        guard let playerService else {
            // Fallback to direct WebView control if PlayerService not available
            SingletonPlayerWebView.shared.next()
            return
        }
        Task {
            await playerService.next()
        }
    }

    @objc private func dockMenuPrevious() {
        guard let playerService else {
            // Fallback to direct WebView control if PlayerService not available
            SingletonPlayerWebView.shared.previous()
            return
        }
        Task {
            await playerService.previous()
        }
    }

    @objc private func dockMenuToggleLike() {
        self.playerService?.likeCurrentTrack()
    }

    @objc private func dockMenuToggleLyrics() {
        guard let playerService else { return }
        playerService.showLyrics.toggle()
        self.showMainWindowAndActivate()
    }

    @objc private func dockMenuToggleQueue() {
        guard let playerService else { return }
        playerService.showQueue.toggle()
        self.showMainWindowAndActivate()
    }

    @objc private func dockMenuToggleFocusPlayer() {
        let requestedMode: PlayerPresentationMode = self.currentPlayerPresentationMode == .focus ? .standard : .focus
        guard requestedMode == .standard || self.playerService?.currentTrack != nil else { return }
        self.requestPlayerPresentationMode(requestedMode)
    }

    @objc private func dockMenuToggleSmallPlayer() {
        let requestedMode: PlayerPresentationMode = self.currentPlayerPresentationMode == .compact ? .standard : .compact
        guard requestedMode == .standard || self.playerService?.currentTrack != nil else { return }
        self.requestPlayerPresentationMode(requestedMode)
    }

    @objc private func dockMenuToggleNowPlayingPanel() {
        SettingsManager.shared.showSidebarNowPlayingPanel.toggle()
        self.showMainWindowAndActivate()
    }

    private func requestPlayerPresentationMode(_ mode: PlayerPresentationMode) {
        self.currentPlayerPresentationMode = mode
        self.showMainWindowAndActivate()
        NotificationCenter.default.post(
            name: .playerPresentationModeRequested,
            object: self,
            userInfo: [PlayerPresentationMode.requestNotificationModeKey: mode.rawValue]
        )
    }

    private func showMainWindowAndActivate() {
        self.showMainWindowIfNeeded()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Keep app running when the window is closed (for background audio).
    /// Use Cmd+Q to fully quit.
    /// In UI test mode, terminate normally to avoid process conflicts.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        UITestConfig.isUITestMode
    }

    /// Handle reopen (clicking dock icon) when all windows are closed.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Show main window when dock icon is clicked
        self.showMainWindowIfNeeded()
        return true
    }

    /// Shows the main window if it's not visible.
    private func showMainWindowIfNeeded() {
        DiagnosticsLogger.app.info("AppDelegate: showMainWindowIfNeeded")
        // Try stored reference first
        if let mainWindow {
            if !mainWindow.isVisible {
                mainWindow.makeKeyAndOrderFront(nil)
            }
            return
        }

        // Fallback: find main window by frameAutosaveName
        for window in NSApplication.shared.windows where window.frameAutosaveName == "YTMPrivateMainWindow" {
            self.mainWindow = window
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        // Last resort: find any main-capable window.
        for window in NSApplication.shared.windows where window.canBecomeMain {
            self.mainWindow = window
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
    }
}

// MARK: NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    /// Intercept window close and hide instead, keeping WebView alive for background audio.
    /// In UI test mode, close normally to avoid process conflicts.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // In UI test mode, allow normal close behavior
        if UITestConfig.isUITestMode {
            return true
        }

        // Hide the window instead of closing it
        sender.orderOut(nil)
        return false // Don't actually close
    }
}

// MARK: UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound (if any) even when app is in foreground
        completionHandler([.banner])
    }
}
