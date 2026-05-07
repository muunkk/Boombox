import SwiftUI

/// Home view displaying personalized content sections.
@available(macOS 26.0, *)
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var settings = SettingsManager.shared

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
                        HomeLoadingView()
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
            .localizedNavigationTitle("Home")
            .navigationDestinations(client: self.viewModel.client)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Home.container)
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
            LazyVStack(alignment: .leading, spacing: 32) {
                // Favorites section (hidden when empty)
                if self.favoritesManager.isVisible {
                    FavoritesSection(onNavigate: { destination in
                        if let playlist = destination as? Playlist {
                            self.navigationPath.append(playlist)
                        } else if let artist = destination as? Artist {
                            self.navigationPath.append(artist)
                        } else if let podcastShow = destination as? PodcastShow {
                            self.navigationPath.append(podcastShow)
                        }
                    })
                    .staggeredAppearance(index: 0)
                }

                // API sections - Quick Picks pinned first, rest in API order
                ForEach(self.viewModel.displaySections) { section in
                    self.sectionView(section)
                        .task {
                            await self.prefetchImagesAsync(for: section)
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        if self.settings.displayMode == .list {
            self.sectionListView(section)
        } else {
            self.sectionGridView(section)
        }
    }

    private func sectionGridView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            self.sectionHeader(section)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    // Use stable ID from items, avoid enumeration for non-chart sections
                    if section.isChart {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            HomeSectionItemCard(item: item, rank: index + 1) {
                                self.playItem(item, in: section, at: index)
                            }
                            .contextMenu {
                                self.contextMenuItems(for: item, in: section, at: index)
                            }
                        }
                    } else {
                        ForEach(section.items) { item in
                            HomeSectionItemCard(item: item) {
                                self.playItem(item, in: section, at: 0)
                            }
                            .contextMenu {
                                self.contextMenuItems(for: item, in: section, at: 0)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func sectionListView(_ section: HomeSection) -> some View {
        let isCompact = self.settings.displayDensity == .compact
        let thumbSize: CGFloat = isCompact ? 36 : 48
        let columnMin: CGFloat = isCompact ? 240 : 300

        return VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader(section)

            // Stacked columns: adaptive grid lays items out in 1+ columns
            // depending on window width, keeping section context tidy.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: columnMin), spacing: 6)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    self.sectionListRow(
                        item: item,
                        rank: section.isChart ? index + 1 : nil,
                        thumbSize: thumbSize,
                        verticalPadding: isCompact ? 4 : 6,
                        action: { self.playItem(item, in: section, at: index) }
                    )
                    .contextMenu {
                        self.contextMenuItems(for: item, in: section, at: index)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: HomeSection) -> some View {
        Text(section.title)
            .font(.title2)
            .fontWeight(.semibold)
    }

    private func sectionListRow(
        item: HomeSectionItem,
        rank: Int?,
        thumbSize: CGFloat,
        verticalPadding: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                        .monospacedDigit()
                }

                self.listThumbnail(for: item, size: thumbSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: self.listKindIcon(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow(cornerRadius: 6))
    }

    @ViewBuilder
    private func listThumbnail(for item: HomeSectionItem, size: CGFloat) -> some View {
        let url = item.thumbnailURL?.highQualityThumbnailURL
        let cornerRadius: CGFloat = {
            if case .artist = item { return size / 2 }
            return 6
        }()

        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: self.listKindIcon(for: item))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private func listKindIcon(for item: HomeSectionItem) -> String {
        switch item {
        case .song: "music.note"
        case .album: "square.stack.fill"
        case .playlist: "music.note.list"
        case .artist: "person.fill"
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: HomeSectionItem, in _: HomeSection, at _: Int) -> some View {
        switch item {
        case let .song(song):
            Button {
                Task { await self.playerService.play(song: song) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: song, manager: self.favoritesManager)

            Divider()

            LikeDislikeContextMenu(song: song, likeStatusManager: self.likeStatusManager)

            Divider()

            StartRadioContextMenu.menuItem(for: song, playerService: self.playerService)

            Divider()

            ShareContextMenu.menuItem(for: song)

            Divider()

            AddToQueueContextMenu(song: song, playerService: self.playerService)

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

        case let .album(album):
            Button {
                self.playItem(item, in: HomeSection(id: "", title: "", items: []), at: 0)
            } label: {
                Label("View Album", systemImage: "square.stack")
            }

            Divider()

            // Play / Play Next / Add to Queue for albums
            Button {
                SongActionsHelper.playAlbum(
                    album,
                    client: self.viewModel.client,
                    playerService: self.playerService
                )
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                SongActionsHelper.addAlbumToQueueNext(
                    album,
                    client: self.viewModel.client,
                    playerService: self.playerService
                )
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }

            Button {
                SongActionsHelper.addAlbumToQueueLast(
                    album,
                    client: self.viewModel.client,
                    playerService: self.playerService
                )
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: album, manager: self.favoritesManager)

            Divider()

            ShareContextMenu.menuItem(for: album)

        case let .playlist(playlist):
            Button {
                self.navigationPath.append(playlist)
            } label: {
                Label("View Playlist", systemImage: "music.note.list")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: playlist, manager: self.favoritesManager)

            Divider()

            ShareContextMenu.menuItem(for: playlist)

        case let .artist(artist):
            Button {
                self.navigationPath.append(artist)
            } label: {
                Label("View Artist", systemImage: "person")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: artist, manager: self.favoritesManager)

            ShareContextMenu.menuItem(for: artist)
        }
    }

    // MARK: - Image Prefetching

    private static let thumbnailDisplaySize = CGSize(width: 160, height: 160)

    private func prefetchImagesAsync(for section: HomeSection) async {
        // Early exit if task is cancelled
        guard !Task.isCancelled else { return }

        let urls = section.items.prefix(10).compactMap { $0.thumbnailURL?.highQualityThumbnailURL }
        guard !urls.isEmpty else { return }

        await ImageCache.shared.prefetch(
            urls: urls,
            targetSize: Self.thumbnailDisplaySize,
            maxConcurrent: 4
        )
    }

    // MARK: - Actions

    private func playItem(_ item: HomeSectionItem, in _: HomeSection, at _: Int) {
        switch item {
        case let .song(song):
            // Play the song and fetch similar songs (radio queue) in the background
            Task {
                await self.playerService.playWithRadio(song: song)
            }
        case let .playlist(playlist):
            // Navigate to playlist detail
            self.navigationPath.append(playlist)
        case let .album(album):
            // For now, we'll create a playlist-like navigation for albums
            // In a full implementation, we'd have an AlbumDetailView
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            self.navigationPath.append(playlist)
        case let .artist(artist):
            // Navigate to artist detail
            self.navigationPath.append(artist)
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    HomeView(viewModel: HomeViewModel(client: client))
        .environment(PlayerService())
        .environment(FavoritesManager.shared)
}
