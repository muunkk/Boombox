import SwiftUI

// MARK: - MainWindow

/// Main application window with sidebar navigation and player bar.
@available(macOS 26.0, *)
struct MainWindow: View {
    private enum Layout {
        static let commandBarTopPadding: CGFloat = 72
    }

    @Environment(AuthService.self) private var authService
    @Environment(PlayerService.self) private var playerService
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(AccountService.self) private var accountService
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @Environment(\.searchFocusTrigger) private var searchFocusTrigger
    @Environment(\.showCommandBar) private var showCommandBar
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    /// Binding to navigation selection for keyboard shortcut control from parent.
    @Binding var navigationSelection: NavigationItem?

    /// Shared API client used by all views and services.
    let client: any YTMusicClientProtocol

    @State private var showLoginSheet = false
    @State private var isCommandBarPresented = false

    // MARK: - Cached ViewModels (persist across tab switches)

    @State private var homeViewModel: HomeViewModel?
    @State private var exploreViewModel: ExploreViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var newReleasesViewModel: NewReleasesViewModel?
    @State private var likedMusicViewModel: LikedMusicViewModel?
    @State private var libraryViewModel: LibraryViewModel?
    @State private var historyViewModel: HistoryViewModel?

    /// Column visibility state for NavigationSplitView - persisted to fix restoration from dock.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var settings = SettingsManager.shared

    /// Whether the sidebar's leading column is currently hidden.
    private var isSidebarCollapsed: Bool {
        self.columnVisibility != .all
    }

    init(navigationSelection: Binding<NavigationItem?>, client: any YTMusicClientProtocol) {
        self._navigationSelection = navigationSelection
        self.client = client
        _homeViewModel = State(initialValue: HomeViewModel(client: client))
        _exploreViewModel = State(initialValue: ExploreViewModel(client: client))
        _searchViewModel = State(initialValue: SearchViewModel(client: client))
        _newReleasesViewModel = State(initialValue: NewReleasesViewModel(client: client))
        _likedMusicViewModel = State(initialValue: LikedMusicViewModel(client: client))
        _libraryViewModel = State(initialValue: LibraryViewModel(client: client))
        _historyViewModel = State(initialValue: HistoryViewModel(client: client))
    }

    /// Access to the app delegate for persistent WebView.
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    var body: some View {
        @Bindable var player = self.playerService

        ZStack(alignment: .bottomTrailing) {
            Group {
                if self.authService.state.isInitializing {
                    // Show loading while checking login status to avoid onboarding flash
                    self.initializingView
                } else if self.authService.state.isLoggedIn {
                    self.authenticatedContent
                } else {
                    OnboardingView()
                }
            }
            .onAppear {
                DiagnosticsLogger.app.info("MainWindow: UI appeared")
            }
            .task {
                DiagnosticsLogger.app.info("MainWindow: Starting login check check...")
                await self.authService.checkLoginStatus()
                DiagnosticsLogger.app.info("MainWindow: Login check complete")
            }

            // Persistent WebView - always present once a video has been requested
            // Uses a SINGLETON WebView instance that persists for the app lifetime
            // Compact size (120x68) for first-time interaction, then hidden (1x1)
            if let videoId = playerService.pendingPlayVideoId {
                ZStack(alignment: .topTrailing) {
                    PersistentPlayerView(videoId: videoId, isExpanded: self.playerService.showMiniPlayer)
                        .frame(
                            width: self.playerService.showMiniPlayer ? 120 : 1,
                            height: self.playerService.showMiniPlayer ? 68 : 1
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(self.playerService.showMiniPlayer ? 0.95 : 0)

                    if self.playerService.showMiniPlayer {
                        Button {
                            self.playerService.confirmPlaybackStarted()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Close"))
                        .padding(3)
                    }
                }
                .shadow(color: self.playerService.showMiniPlayer ? .black.opacity(0.2) : .clear, radius: 6, y: 3)
                .padding(.trailing, self.playerService.showMiniPlayer ? 12 : 0)
                .padding(.bottom, self.playerService.showMiniPlayer ? 76 : 0)
                .allowsHitTesting(self.playerService.showMiniPlayer)
                // Hiding must not interpolate frame/opacity (no “shrink”); showing can ease in.
                .transaction { transaction in
                    if !self.playerService.showMiniPlayer {
                        transaction.animation = nil
                    } else {
                        transaction.animation = .easeInOut(duration: 0.2)
                    }
                }
            }
        }
        .sheet(isPresented: self.$showLoginSheet) {
            LoginSheet()
        }
        .overlay {
            // Command bar overlay - dismisses when clicking outside
            if self.isCommandBarPresented {
                ZStack {
                    // Background tap area to dismiss
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .accessibilityIdentifier(AccessibilityID.MainWindow.commandBarOverlay)
                        .onTapGesture {
                            self.isCommandBarPresented = false
                        }

                    VStack(spacing: 0) {
                        self.commandBar
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, Self.Layout.commandBarTopPadding)
                }
                .animation(.easeInOut(duration: 0.15), value: self.isCommandBarPresented)
            }
        }
        .overlay(alignment: .top) {
            // Error toast for account switching failures
            AccountErrorToast()
                .padding(.top, 60)
        }
        .onChange(of: self.showCommandBar.wrappedValue) { _, newValue in
            if newValue {
                self.isCommandBarPresented = true
                self.showCommandBar.wrappedValue = false
            }
        }
        .onChange(of: self.authService.state) { oldState, newState in
            self.handleAuthStateChange(oldState: oldState, newState: newState)
        }
        .onChange(of: self.authService.needsReauth) { _, needsReauth in
            if needsReauth {
                self.showLoginSheet = true
            }
        }
        .onChange(of: self.playerService.isPlaying) { _, isPlaying in
            // Open the session autoplay gate once the hidden WebView confirms playback.
            if isPlaying,
               self.playerService.showMiniPlayer || !self.playerService.hasUserInteractedThisSession
            {
                self.playerService.confirmPlaybackStarted()
            }
        }
        .onChange(of: self.accountService.currentAccount?.id) { _, newAccountId in
            self.playerService.resetTrackStatus()

            Task { @MainActor in
                APICache.shared.invalidateAll()
                URLCache.shared.removeAllCachedResponses()

                guard newAccountId != nil else { return }

                self.historyViewModel?.reset()

                DiagnosticsLogger.auth.info("Account switched, refreshing content and current track metadata...")

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await self.refreshAllContent()
                    }

                    if let currentVideoId = self.playerService.currentTrack?.videoId {
                        group.addTask {
                            await self.playerService.fetchSongMetadata(videoId: currentVideoId)
                        }
                    }
                }
            }
        }
        .task {
            NowPlayingManager.shared.configure(playerService: self.playerService)
        }
        .onChange(of: self.likeStatusManager.lastLikeEvent) { _, event in
            guard let event else { return }

            // Global sync 1: keep PlayerService.currentTrackLikeStatus in sync
            if let currentVideoId = self.playerService.currentTrack?.videoId,
               event.videoId == currentVideoId
            {
                self.playerService.currentTrackLikeStatus = event.status
            }

            // Global sync 2: keep Liked Music list in sync regardless of which tab is active
            self.likedMusicViewModel?.handleLikeStatusChange(event)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var authenticatedContent: some View {
        switch self.playerPresentationMode.wrappedValue {
        case .standard:
            self.mainContent
        case .focus:
            FocusPlayerView(client: self.client)
        case .compact:
            CompactPlayerView(client: self.client)
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .trailing) {
            // Main navigation content
            NavigationSplitView(columnVisibility: self.$columnVisibility) {
                Sidebar(selection: self.$navigationSelection)
            } detail: {
                self.detailView(for: self.navigationSelection, client: self.client)
                    .overlay(alignment: .bottomLeading) {
                        // When the sidebar collapses, the inline now-playing
                        // card disappears with it. Render a floating copy
                        // anchored where the original sat. The overlay region
                        // is clipped to end at the PlayerBar's top edge, so
                        // the slide-up / slide-down animation appears to come
                        // from behind the PlayerBar.
                        ZStack(alignment: .bottomLeading) {
                            if self.isSidebarCollapsed, self.settings.showSidebarNowPlayingPanel {
                                NowPlayingSidebarPanel()
                                    .frame(width: 200)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 4)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.bottom, 76) // clear PlayerBar
                        .clipped()
                        .allowsHitTesting(self.isSidebarCollapsed && self.settings.showSidebarNowPlayingPanel)
                    }
                    .animation(.easeInOut(duration: 0.2), value: self.isSidebarCollapsed)
                    .animation(.easeInOut(duration: 0.2), value: self.settings.showSidebarNowPlayingPanel)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task { await self.refreshCurrentPage() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .keyboardShortcut("r", modifiers: .command)
                            .disabled(!self.currentPageSupportsRefresh)
                            .help(String(localized: "Refresh"))
                            .accessibilityLabel(String(localized: "Refresh"))
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                // Ensure the sidebar returns when the app is re-activated from the Dock or app switcher.
                if self.columnVisibility != .all {
                    self.columnVisibility = .all
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sidebarToggleRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.columnVisibility = self.columnVisibility == .all ? .detailOnly : .all
                }
            }

            // Right sidebar overlay - either lyrics or queue (mutually exclusive)
            self.rightSidebarOverlay(client: self.client)
        }
        .animation(.easeInOut(duration: 0.25), value: self.playerService.showLyrics)
        .animation(.easeInOut(duration: 0.25), value: self.playerService.showQueue)
        .frame(minWidth: 900, minHeight: 600)
        .environment(\.isSidebarCollapsed, self.isSidebarCollapsed)
        .background {
            // Hidden Esc shortcut — closes the lyrics or queue panel when shown.
            if self.playerService.showLyrics || self.playerService.showQueue {
                Button("") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if self.playerService.showLyrics {
                            self.playerService.showLyrics = false
                        }
                        if self.playerService.showQueue {
                            self.playerService.showQueue = false
                        }
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }

    /// Right sidebar overlay showing either lyrics or queue as glass panels (mutually exclusive).
    @ViewBuilder
    private func rightSidebarOverlay(client: any YTMusicClientProtocol) -> some View {
        let showRightSidebar = self.playerService.showLyrics || self.playerService.showQueue

        if showRightSidebar {
            VStack {
                Spacer()

                Group {
                    if self.playerService.showLyrics {
                        LyricsView(client: client)
                    } else if self.playerService.showQueue {
                        if self.playerService.queueDisplayMode == .sidepanel {
                            QueueSidePanelView()
                        } else {
                            QueueView()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 76) // Space for PlayerBar
                .transition(.move(edge: .trailing).combined(with: .opacity))

                Spacer()
            }
            .padding(.trailing, 16)
        }
    }

    private func detailView(for item: NavigationItem?, client _: any YTMusicClientProtocol) -> some View {
        Group {
            if let item {
                self.viewForNavigationItem(item)
            } else {
                Text("Select an item from the sidebar", comment: "Placeholder shown when no sidebar item is selected")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commandBar: some View {
        CommandBarView(
            client: self.client,
            isPresented: self.$isCommandBarPresented,
            searchViewModel: self.searchViewModel
        )
    }

    /// Returns the view for a specific navigation item.
    private func viewForNavigationItem(_ item: NavigationItem) -> some View {
        Group {
            switch item {
            case .home:
                if let vm = homeViewModel { HomeView(viewModel: vm) }
            case .explore:
                if let vm = exploreViewModel { ExploreView(viewModel: vm) }
            case .search:
                if let vm = searchViewModel {
                    SearchView(viewModel: vm, focusTrigger: self.searchFocusTrigger)
                }
            case .newReleases:
                if let vm = newReleasesViewModel { NewReleasesView(viewModel: vm) }
            case .likedMusic:
                if let vm = likedMusicViewModel { LikedMusicView(viewModel: vm) }
            case .library:
                if let vm = libraryViewModel { LibraryView(viewModel: vm) }
            case .history:
                if let vm = historyViewModel { HistoryView(viewModel: vm) }
            }
        }
        .environment(self.libraryViewModel)
    }

    /// View shown while checking initial login status.
    private var initializingView: some View {
        VStack(spacing: 16) {
            CassetteIcon(size: 60)
                .foregroundStyle(.tint)
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func handleAuthStateChange(oldState: AuthService.State, newState: AuthService.State) {
        switch newState {
        case .initializing:
            // Still checking login status, do nothing
            break
        case .loggedOut:
            // Onboarding view handles login, no need to auto-show sheet
            self.accountService.clearAccounts()
        case .loggingIn:
            self.showLoginSheet = true
        case .loggedIn:
            self.showLoginSheet = false
            Task {
                await self.accountService.fetchAccounts()
            }
            // If we just completed login (transitioning from loggingIn), refresh content
            // This handles the case where cookies weren't ready during initial load
            if case .loggingIn = oldState {
                Task {
                    // Brief delay to ensure cookies are fully propagated in WebKit
                    try? await Task.sleep(for: .milliseconds(500))

                    // Parallel initial data fetch for ~40% faster app launch
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await self.homeViewModel?.refresh() }
                        group.addTask { await self.exploreViewModel?.refresh() }
                        group.addTask { await self.libraryViewModel?.load() }
                    }
                }
            }
        }
    }

    /// Refreshes all content when switching accounts.
    ///
    /// This method is called when the user switches between their primary account
    /// and brand accounts, ensuring all views display content for the new account.
    private func refreshAllContent() async {
        // Parallel refresh of all content views
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.homeViewModel?.refresh() }
            group.addTask { await self.exploreViewModel?.refresh() }
            group.addTask { await self.newReleasesViewModel?.refresh() }
            group.addTask { await self.likedMusicViewModel?.refresh() }
            group.addTask { await self.historyViewModel?.load() }
            group.addTask { await self.libraryViewModel?.refresh() }
        }
    }

    /// Whether the current navigation page supports refreshing.
    fileprivate var currentPageSupportsRefresh: Bool {
        switch self.navigationSelection {
        case .home, .explore, .newReleases, .likedMusic, .library, .history:
            true
        case .search, .none:
            false
        }
    }

    /// Refreshes the currently visible page's data.
    fileprivate func refreshCurrentPage() async {
        switch self.navigationSelection {
        case .home: await self.homeViewModel?.refresh()
        case .explore: await self.exploreViewModel?.refresh()
        case .newReleases: await self.newReleasesViewModel?.refresh()
        case .likedMusic: await self.likedMusicViewModel?.refresh()
        case .library: await self.libraryViewModel?.refresh()
        case .history: _ = await self.historyViewModel?.refresh()
        case .search, .none: break
        }
    }
}

// MARK: - NavigationItem

enum NavigationItem: String, Hashable, CaseIterable, Identifiable {
    case search = "Search"
    case home = "Home"
    case library = "Library"
    case likedMusic = "Liked Music"
    case explore = "Explore"
    case newReleases = "New Releases"
    case history = "History"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .search:
            String(localized: "Search")
        case .home:
            String(localized: "Home")
        case .library:
            String(localized: "Library")
        case .likedMusic:
            String(localized: "Liked Music")
        case .explore:
            String(localized: "Explore")
        case .newReleases:
            String(localized: "New Releases")
        case .history:
            String(localized: "History")
        }
    }

    var icon: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .home:
            "house"
        case .library:
            "square.stack.fill"
        case .likedMusic:
            "heart.fill"
        case .explore:
            "globe"
        case .newReleases:
            "sparkles"
        case .history:
            "clock.arrow.circlepath"
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    @Previewable @State var navSelection: NavigationItem? = .home
    let authService = AuthService()
    let ytMusicClient = YTMusicClient(authService: authService)
    let accountService = AccountService(ytMusicClient: ytMusicClient, authService: authService)
    MainWindow(navigationSelection: $navSelection, client: ytMusicClient)
        .environment(authService)
        .environment(PlayerService())
        .environment(WebKitManager.shared)
        .environment(accountService)
}
