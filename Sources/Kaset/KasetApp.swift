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

extension EnvironmentValues {
    @Entry var isSidebarCollapsed: Bool = false
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
    @State private var notificationService: NotificationService
    @State private var favoritesManager = FavoritesManager.shared
    @State private var likeStatusManager = SongLikeStatusManager.shared
    @State private var accountService: AccountService
    @State private var syncedLyricsService: SyncedLyricsService
    @State private var settings = SettingsManager.shared

    @State private var globalNavigation = GlobalNavigationCoordinator()

    @State private var shortcuts = KeyboardShortcutsManager.shared

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

        let services = AppServices.make()

        _authService = State(initialValue: services.authService)
        _webKitManager = State(initialValue: services.webKitManager)
        _playerService = State(initialValue: services.playerService)
        _sharedClient = State(initialValue: services.sharedClient)
        _notificationService = State(initialValue: services.notificationService)
        _favoritesManager = State(initialValue: services.favoritesManager)
        _likeStatusManager = State(initialValue: services.likeStatusManager)
        _accountService = State(initialValue: services.accountService)
        _syncedLyricsService = State(initialValue: services.syncedLyricsService)

        // Wire up PlayerService to AppDelegate immediately (not in onAppear)
        // This ensures playerService is available for lifecycle events like queue restoration
        self.appDelegate.playerService = services.playerService

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
                    .scrollIndicators(.hidden)
                    .environment(\.locale, self.settings.contentLanguage.locale)
                    .environment(self.authService)
                    .environment(self.webKitManager)
                    .environment(self.playerService)
                    .environment(self.favoritesManager)
                    .environment(self.likeStatusManager)
                    .environment(self.accountService)
                    .environment(self.syncedLyricsService)
                    .environment(self.globalNavigation)
                    .environment(\.searchFocusTrigger, self.$searchFocusTrigger)
                    .environment(\.navigationSelection, self.$navigationSelection)
                    .environment(\.showCommandBar, self.$showCommandBar)
                    .environment(\.playerPresentationMode, self.$playerPresentationMode)
                    .toolbar(self.playerPresentationMode == .standard ? .automatic : .hidden, for: .windowToolbar)
                    .toolbarBackgroundVisibility(self.playerPresentationMode == .standard ? .automatic : .hidden, for: .windowToolbar)
                    .onAppear {
                        DiagnosticsLogger.app.info("KasetApp: App content appeared")
                        // Wire up PlayerService to AppDelegate for dock menu actions
                        self.appDelegate.playerService = self.playerService
                        self.appDelegate.currentPlayerPresentationMode = self.playerPresentationMode
                        // Reference notificationService to keep SwiftUI from deallocating it
                        _ = self.notificationService

                        // Lazily create the menu bar controller and sync its visibility.
                        if !UITestConfig.isRunningUnitTests {
                            if self.appDelegate.menuBarController == nil {
                                self.appDelegate.menuBarController = MenuBarController(
                                    playerService: self.playerService,
                                    webKitManager: self.webKitManager
                                )
                            }
                            self.appDelegate.menuBarController?.setEnabled(self.settings.menuBarItemEnabled)
                            self.appDelegate.menuBarController?.applyHotkey(
                                self.settings.menuBarHotkey,
                                menuBarEnabled: self.settings.menuBarItemEnabled
                            )
                        }
                    }
                    .task {
                        DiagnosticsLogger.app.info("KasetApp: Root task started")
                        // Check if user is already logged in from previous session
                        await self.authService.checkLoginStatus()
                        DiagnosticsLogger.app.info("KasetApp: Login status check complete")

                        // Fetch accounts after login check (for account switcher)
                        await self.accountService.fetchAccounts()
                    }
                    .onChange(of: self.playerPresentationMode) { oldMode, newMode in
                        self.appDelegate.currentPlayerPresentationMode = newMode
                        self.appDelegate.transitionPlayerPresentationMode(from: oldMode, to: newMode)
                    }
                    .onChange(of: self.settings.menuBarItemEnabled) { _, newValue in
                        self.appDelegate.menuBarController?.setEnabled(newValue)
                        self.appDelegate.menuBarController?.applyHotkey(
                            self.settings.menuBarHotkey,
                            menuBarEnabled: newValue
                        )
                    }
                    .onChange(of: self.settings.menuBarHotkey) { _, newValue in
                        self.appDelegate.menuBarController?.applyHotkey(
                            newValue,
                            menuBarEnabled: self.settings.menuBarItemEnabled
                        )
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
                .keyboardShortcut(for: .playPause)
                .disabled(self.playerService.currentTrack == nil && self.playerService.pendingPlayVideoId == nil)

                Divider()

                // Next Track - ⌘→
                Button("Next") {
                    Task {
                        await self.playerService.next()
                    }
                }
                .keyboardShortcut(for: .nextTrack)

                // Previous Track
                Button("Previous") {
                    Task {
                        await self.playerService.previous()
                    }
                }
                .keyboardShortcut(for: .previousTrack)

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
                .keyboardShortcut(for: .volumeUp)

                // Volume Down
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
                .keyboardShortcut(for: .volumeDown)

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
                .keyboardShortcut(for: .toggleShuffle)

                // Repeat (default ⌥⌘R since ⌘R is page refresh)
                Button(self.repeatModeLabel) {
                    self.playerService.cycleRepeatMode()
                }
                .keyboardShortcut(for: .cycleRepeat)

                Divider()

                // Lyrics
                Button(self.playerService.showLyrics ? "Hide Lyrics" : "Show Lyrics") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerService.showLyrics.toggle()
                    }
                }
                .keyboardShortcut(for: .toggleLyrics)

                Divider()

                Button(self.playerPresentationMode == .focus ? "Exit Focus Player" : "Focus Player") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerPresentationMode = self.playerPresentationMode == .focus ? .standard : .focus
                    }
                }
                .keyboardShortcut(for: .toggleFocusPlayer)
                .disabled(self.playerService.currentTrack == nil)

                Button(self.playerPresentationMode == .compact ? "Exit Small Player" : "Small Player") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerPresentationMode = self.playerPresentationMode == .compact ? .standard : .compact
                    }
                }
                .keyboardShortcut(for: .toggleSmallPlayer)
                .disabled(self.playerService.currentTrack == nil && self.playerPresentationMode != .compact)
            }

            // Navigation commands - replace default sidebar toggle.
            // Cmd+1..N follows Sidebar.cmdOrder; keep both lists in sync.
            CommandGroup(replacing: .sidebar) {
                Button("Search") {
                    self.navigationSelection = .search
                }
                .keyboardShortcut(for: .goToSearch)

                Button("Home") {
                    self.navigationSelection = .home
                }
                .keyboardShortcut(for: .goToHome)

                Button("Library") {
                    self.navigationSelection = .library
                }
                .keyboardShortcut(for: .goToLibrary)

                Button("Liked Music") {
                    self.navigationSelection = .likedMusic
                }
                .keyboardShortcut(for: .goToLikedMusic)

                Button("Explore") {
                    self.navigationSelection = .explore
                }
                .keyboardShortcut(for: .goToExplore)

                Button("New Releases") {
                    self.navigationSelection = .newReleases
                }
                .keyboardShortcut(for: .goToNewReleases)

                Button("History") {
                    self.navigationSelection = .history
                }
                .keyboardShortcut(for: .goToHistory)

                Divider()

                // Search field focus
                Button("Find") {
                    self.navigationSelection = .search
                    // Same reasoning as the command bar: if the user is deep inside
                    // a pushed detail page on the Search tab, focusing the search
                    // field is meaningless until we pop back to the search root.
                    self.globalNavigation.popSearchToRoot()
                    // Trigger focus after a brief delay to allow view to appear
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        self.searchFocusTrigger = true
                    }
                }
                .keyboardShortcut(for: .focusSearchField)

                // Command Bar
                Button("Command Bar") {
                    self.showCommandBar = true
                }
                .keyboardShortcut(for: .openCommandBar)
            }

            // Window menu - show main window
            CommandGroup(after: .windowArrangement) {
                Button("Boombox") {
                    self.showMainWindow()
                }
                .keyboardShortcut(for: .showMainWindow)
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

            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 460, minHeight: 480)
    }
}
