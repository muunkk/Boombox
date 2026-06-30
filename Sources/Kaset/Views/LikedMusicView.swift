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
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
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
                    if self.viewModel.searchQuery.isEmpty {
                        self.emptyStateView
                    } else {
                        ContentUnavailableView.search(text: self.viewModel.searchQuery)
                            .frame(minHeight: 200)
                    }
                } else {
                    ForEach(Array(self.viewModel.displaySongs.enumerated()), id: \.element.id) { index, song in
                        self.songRow(song, index: index)
                            .task {
                                if index >= self.viewModel.displaySongs.count - 3, self.viewModel.hasMore {
                                    await self.viewModel.loadMore()
                                }
                            }
                        if index < self.viewModel.displaySongs.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }

                    // Loading indicator for pagination
                    if self.viewModel.loadingState == .loadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .padding()
                            Spacer()
                        }
                    }
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

                Text("\(self.viewModel.songs.count) songs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Play all button
            if !self.viewModel.songs.isEmpty {
                Button {
                    Task {
                        await self.playerService.playQueue(self.viewModel.songs, startingAt: 0)
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
                        let shuffled = self.viewModel.songs.shuffled()
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
                if self.viewModel.isLoadingAll {
                    ProgressView().controlSize(.small)
                } else if !self.searchText.isEmpty {
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
        MusicListRow(
            title: song.title,
            subtitle: song.artistsDisplay,
            thumbSize: 48,
            verticalPadding: 8,
            onPlay: {
                Task {
                    await self.playerService.playQueue(self.viewModel.displaySongs, startingAt: index)
                }
            },
            thumbnail: { SongThumbnailView(song: song) },
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

            if let artist = song.artists.first(where: { $0.hasNavigableId }) {
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "person")
                }
            }

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
