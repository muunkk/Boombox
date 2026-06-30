import SwiftUI

/// View displaying the user's liked songs.
@available(macOS 26.0, *)
struct LikedMusicView: View {
    @State var viewModel: LikedMusicViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @State private var networkMonitor = NetworkMonitor.shared

    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    /// Liked-tab-local density override (independent of the global setting).
    @AppStorage("settings.likedMusicCompact") private var likedCompact = false

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: String(localized: "No Connection"),
                        message: String(localized: "Please check your internet connection and try again.")
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        LoadingView(String(localized: "Loading liked songs..."))
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.refresh() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .localizedNavigationTitle("Liked Music")
            .navigationDestinations(client: self.viewModel.client)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.LikedMusic.container)
        .navigationSwipeGestures(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .background {
            // ⌘F focuses the search field (scoped to the Liked Music tab).
            Button("") { self.searchFieldFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
        .onDisappear {
            self.viewModel.cancelDeepSearch()
        }
        .refreshable {
            await self.viewModel.refresh()
        }
    }

    // MARK: - Views

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header with play all button
                self.headerView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                self.searchAndSortBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // Songs list
                if self.viewModel.displaySongs.isEmpty {
                    self.emptyContent
                } else {
                    ForEach(Array(self.viewModel.displaySongs.enumerated()), id: \.element.id) { index, song in
                        self.songRow(song, index: index)
                        if index < self.viewModel.displaySongs.count - 1 {
                            Divider()
                                .padding(.leading, self.likedCompact ? 60 : 72)
                        }
                    }

                    self.listFooter
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            // Liked music icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.red, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Liked Music")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(self.viewModel.displaySongs.count) songs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Play all button
            if !self.viewModel.displaySongs.isEmpty {
                Button {
                    Task {
                        await self.playerService.playQueue(self.viewModel.displaySongs, startingAt: 0)
                    }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                // Shuffle button
                Button {
                    Task {
                        let shuffled = self.viewModel.displaySongs.shuffled()
                        await self.playerService.playQueue(shuffled, startingAt: 0)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var searchAndSortBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search liked songs"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .focused(self.$searchFieldFocused)
                if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            .frame(maxWidth: 320)

            Spacer()

            // Liked-tab-local density toggle (independent of global density).
            Button {
                self.likedCompact.toggle()
            } label: {
                Image(systemName: self.likedCompact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
            .help(self.likedCompact
                ? String(localized: "Switch to comfortable rows")
                : String(localized: "Switch to compact rows"))

            Menu {
                Picker(String(localized: "Sort By"), selection: self.$viewModel.sortOrder) {
                    ForEach(LikedMusicViewModel.SortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Label(self.viewModel.sortOrder.label, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .onChange(of: self.searchText) { _, newValue in
            self.viewModel.setSearchQuery(newValue)
        }
    }

    /// Content shown when no songs are visible — either the empty library state,
    /// a deep-search prompt/progress, or a true "no matches" state.
    @ViewBuilder
    private var emptyContent: some View {
        if self.viewModel.searchQuery.isEmpty {
            self.emptyStateView
        } else if self.viewModel.isSearchingDeeper {
            self.deepSearchProgress
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if self.viewModel.hasMore {
            self.deepSearchPrompt
        } else {
            ContentUnavailableView.search(text: self.viewModel.searchQuery)
                .frame(minHeight: 200)
        }
    }

    /// Footer below the list: a Load More button while browsing, or a
    /// "search deeper for more" affordance / progress while searching.
    @ViewBuilder
    private var listFooter: some View {
        if self.viewModel.isSearchingDeeper {
            self.deepSearchProgress.padding()
        } else if self.viewModel.hasMore {
            if self.viewModel.searchQuery.isEmpty {
                if self.viewModel.loadingState == .loadingMore {
                    ProgressView().controlSize(.small).padding()
                } else {
                    Button {
                        Task { await self.viewModel.loadMore() }
                    } label: {
                        Label("Load More", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            } else {
                Button {
                    self.viewModel.startDeepSearch()
                } label: {
                    Label("Search deeper for more", systemImage: "magnifyingglass.circle")
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }

    /// Progress ring + loaded count shown while a deep search runs.
    private var deepSearchProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Searching… \(self.viewModel.loadedCount) songs loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "Stop")) {
                self.viewModel.cancelDeepSearch()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity)
    }

    /// Prompt shown when a search has no matches in loaded songs but more pages
    /// remain — offers to load deeper.
    private var deepSearchPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No matches in loaded songs")
                .font(.headline)

            Text("This song may not be loaded yet — search deeper to look through the rest of your liked music.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button {
                self.viewModel.startDeepSearch()
            } label: {
                Label("Search deeper", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No liked songs yet")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Songs you like will appear here", comment: "Liked music empty state")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func songRow(_ song: Song, index: Int) -> some View {
        let thumb: CGFloat = self.likedCompact ? 40 : 48
        return MusicListRow(
            title: song.title,
            subtitle: song.artistsDisplay,
            thumbSize: thumb,
            verticalPadding: self.likedCompact ? 4 : 8,
            onPlay: {
                Task {
                    await self.playerService.playQueue(self.viewModel.displaySongs, startingAt: index)
                }
            },
            thumbnail: { SongThumbnailView(song: song, size: thumb) },
            trailing: {
                Text(song.durationDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        )
        .contextMenu {
            AddToQueueContextMenu(song: song, playerService: self.playerService)

            Divider()

            Button {
                Task { await self.playerService.play(song: song) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: song, manager: self.favoritesManager)

            Divider()

            Button {
                SongActionsHelper.unlikeSong(song, likeStatusManager: self.likeStatusManager)
            } label: {
                Label("Unlike", systemImage: "hand.thumbsup.fill")
            }

            Divider()

            StartRadioContextMenu.menuItem(for: song, playerService: self.playerService)

            Divider()

            ShareContextMenu.menuItem(for: song)

            Divider()

            // Go to Artist - show first artist with valid ID
            if let artist = song.artists.first(where: { $0.hasNavigableId }) {
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "person")
                }
            }

            // Go to Album - show if album has valid browse ID
            if let album = song.album, album.hasNavigableId {
                let playlist = Playlist(
                    id: album.id,
                    title: album.title,
                    description: nil,
                    thumbnailURL: album.thumbnailURL ?? song.thumbnailURL,
                    trackCount: album.trackCount,
                    author: album.artistsDisplay
                )
                NavigationLink(value: playlist) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var navigationPath = NavigationPath()
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    LikedMusicView(viewModel: LikedMusicViewModel(client: client), navigationPath: $navigationPath)
        .environment(PlayerService())
        .environment(FavoritesManager.shared)
}
