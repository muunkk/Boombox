import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var searchFocusTrigger: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    @Entry var navigationSelection: Binding<NavigationItem?> = .constant(nil)
}

extension EnvironmentValues {
    @Entry var showCommandBar: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    @Entry var playerPresentationMode: Binding<PlayerPresentationMode> = .constant(.standard)
}

// MARK: - KasetApp

/// Main entry point for the Boombox macOS application.
@available(macOS 26.0, *)
@main
struct KasetApp: App {
    /// App delegate for lifecycle management (background playback).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var authService = AuthService()
    @State private var webKitManager = WebKitManager.shared
    @State private var playerService = PlayerService()
    @State private var sharedClient: any YTMusicClientProtocol
    @State private var notificationService: NotificationService?
    @State private var favoritesManager = FavoritesManager.shared
    @State private var likeStatusManager = SongLikeStatusManager.shared
    @State private var accountService: AccountService?
    @State private var syncedLyricsService: SyncedLyricsService
    @State private var settings = SettingsManager.shared

    /// Triggers search field focus when set to true.
    @State private var searchFocusTrigger = false

    /// Current navigation selection for keyboard navigation.
    @State private var navigationSelection: NavigationItem? = SettingsManager.shared.launchNavigationItem

    /// Whether the command bar is visible.
    @State private var showCommandBar = false

    /// Current player presentation mode.
    @State private var playerPresentationMode: PlayerPresentationMode = .standard

    init() {
        Bundle.enableAppLocalizationOverride()

        let auth = AuthService()
        let webkit = WebKitManager.shared
        let player = PlayerService()

        // Use mock client in UI test mode, real client otherwise
        let realClient = YTMusicClient(authService: auth, webKitManager: webkit)
        let client: YTMusicClientProtocol = if UITestConfig.isUITestMode {
            MockUITestYTMusicClient()
        } else {
            realClient
        }

        // Wire up dependencies
        player.setYTMusicClient(client)
        SongLikeStatusManager.shared.setClient(client)

        // Create account service
        let account = AccountService(ytMusicClient: client, authService: auth)

        // Wire up brand account provider so API requests use the correct account
        realClient.brandIdProvider = { [weak account] in
            account?.currentBrandId
        }

        _authService = State(initialValue: auth)
        _webKitManager = State(initialValue: webkit)
        _playerService = State(initialValue: player)
        _sharedClient = State(initialValue: client)
        _syncedLyricsService = State(initialValue: SyncedLyricsService(providers: [
            YTMusicSyncedProvider(client: client),
            LRCLibProvider(),
        ]))
        _notificationService = State(initialValue: NotificationService(playerService: player))
        _accountService = State(initialValue: account)

        // Wire up PlayerService to AppDelegate immediately (not in onAppear)
        // This ensures playerService is available for lifecycle events like queue restoration
        self.appDelegate.playerService = player

        if UITestConfig.isUITestMode {
            DiagnosticsLogger.ui.info("App launched in UI Test mode")
        }
    }

    var body: some Scene {
        Window("Boombox", id: "main") {
            // Skip UI during unit tests to prevent window spam
            if UITestConfig.isRunningUnitTests, !UITestConfig.isUITestMode {
                Color.clear
                    .frame(width: 1, height: 1)
            } else {
                MainWindow(navigationSelection: self.$navigationSelection, client: self.sharedClient)
                    .id(self.settings.contentLanguage)
                    .environment(\.locale, self.settings.contentLanguage.locale)
                    .environment(self.authService)
                    .environment(self.webKitManager)
                    .environment(self.playerService)
                    .environment(self.favoritesManager)
                    .environment(self.likeStatusManager)
                    .environment(self.accountService)
                    .environment(self.syncedLyricsService)
                    .environment(\.searchFocusTrigger, self.$searchFocusTrigger)
                    .environment(\.navigationSelection, self.$navigationSelection)
                    .environment(\.showCommandBar, self.$showCommandBar)
                    .environment(\.playerPresentationMode, self.$playerPresentationMode)
                    .onAppear {
                        DiagnosticsLogger.app.info("KasetApp: App content appeared")
                        // Wire up PlayerService to AppDelegate for dock menu actions
                        self.appDelegate.playerService = self.playerService
                        self.appDelegate.currentPlayerPresentationMode = self.playerPresentationMode
                        // Reference notificationService to keep SwiftUI from deallocating it
                        _ = self.notificationService
                    }
                    .task {
                        DiagnosticsLogger.app.info("KasetApp: Root task started")
                        // Check if user is already logged in from previous session
                        await self.authService.checkLoginStatus()
                        DiagnosticsLogger.app.info("KasetApp: Login status check complete")

                        // Fetch accounts after login check (for account switcher)
                        await self.accountService?.fetchAccounts()
                    }
                    .onChange(of: self.playerPresentationMode) { oldMode, newMode in
                        self.appDelegate.currentPlayerPresentationMode = newMode
                        self.appDelegate.transitionPlayerPresentationMode(from: oldMode, to: newMode)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .playerPresentationModeRequested)) { notification in
                        guard let rawMode = notification.userInfo?[PlayerPresentationMode.requestNotificationModeKey] as? String,
                              let mode = PlayerPresentationMode(rawValue: rawMode)
                        else {
                            return
                        }

                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.playerPresentationMode = mode
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(\.locale, self.settings.contentLanguage.locale)
                .environment(self.authService)
        }
        .commands {
            // Playback commands
            CommandMenu("Playback") {
                // Play/Pause - Space
                Button(self.playerService.isPlaying ? "Pause" : "Play") {
                    Task {
                        await self.playerService.playPause()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(self.playerService.currentTrack == nil && self.playerService.pendingPlayVideoId == nil)

                Divider()

                // Next Track - ⌘→
                Button("Next") {
                    Task {
                        await self.playerService.next()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                // Previous Track - ⌘←
                Button("Previous") {
                    Task {
                        await self.playerService.previous()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                // Volume Up - ⌘↑
                Button("Volume Up") {
                    Task {
                        await self.playerService.setVolume(
                            VolumeCurve.steppedOutputVolume(
                                fromOutputVolume: self.playerService.volume,
                                bySliderStep: 0.1
                            )
                        )
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                // Volume Down - ⌘↓
                Button("Volume Down") {
                    Task {
                        await self.playerService.setVolume(
                            VolumeCurve.steppedOutputVolume(
                                fromOutputVolume: self.playerService.volume,
                                bySliderStep: -0.1
                            )
                        )
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                // Mute
                Button(self.playerService.isMuted ? "Unmute" : "Mute") {
                    Task {
                        await self.playerService.toggleMute()
                    }
                }

                Divider()

                // Shuffle - ⌘S
                Button(self.playerService.shuffleEnabled ? "Shuffle Off" : "Shuffle On") {
                    self.playerService.toggleShuffle()
                }
                .keyboardShortcut("s", modifiers: .command)

                // Repeat - ⌘R
                Button(self.repeatModeLabel) {
                    self.playerService.cycleRepeatMode()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                // Lyrics - ⌘Y
                Button(self.playerService.showLyrics ? "Hide Lyrics" : "Show Lyrics") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerService.showLyrics.toggle()
                    }
                }
                .keyboardShortcut("y", modifiers: .command)

                Divider()

                Button(self.playerPresentationMode == .focus ? "Exit Focus Player" : "Focus Player") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerPresentationMode = self.playerPresentationMode == .focus ? .standard : .focus
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(self.playerService.currentTrack == nil)

                Button(self.playerPresentationMode == .compact ? "Exit Small Player" : "Small Player") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerPresentationMode = self.playerPresentationMode == .compact ? .standard : .compact
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(self.playerService.currentTrack == nil && self.playerPresentationMode != .compact)
            }

            // Navigation commands - replace default sidebar toggle
            CommandGroup(replacing: .sidebar) {
                // Home - ⌘1
                Button("Home") {
                    self.navigationSelection = .home
                }
                .keyboardShortcut("1", modifiers: .command)

                // Explore - ⌘2
                Button("Explore") {
                    self.navigationSelection = .explore
                }
                .keyboardShortcut("2", modifiers: .command)

                // Library - ⌘3
                Button("Library") {
                    self.navigationSelection = .library
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                // Search - ⌘F
                Button("Search") {
                    self.navigationSelection = .search
                    // Trigger focus after a brief delay to allow view to appear
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        self.searchFocusTrigger = true
                    }
                }
                .keyboardShortcut("f", modifiers: .command)

                // Command Bar - ⌘L
                Button("Command Bar") {
                    self.showCommandBar = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            // Window menu - show main window
            CommandGroup(after: .windowArrangement) {
                Button("Boombox") {
                    self.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

        }
    }

    /// Shows the main window.
    private func showMainWindow() {
        // Find and show the main window
        for window in NSApplication.shared.windows where window.frameAutosaveName == "BoomboxMainWindow" {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // Fallback: find any main-capable window.
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
    }

    /// Label for repeat mode menu item.
    private var repeatModeLabel: String {
        switch self.playerService.repeatMode {
        case .off:
            "Repeat All"
        case .all:
            "Repeat One"
        case .one:
            "Repeat Off"
        }
    }

}

// MARK: - SettingsView

/// Main settings view with tabbed navigation.
@available(macOS 26.0, *)
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 460, height: 420)
    }
}
