import SwiftUI

// MARK: - LibraryFilter

/// Filter options for the Library view.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case playlists = "Playlists"
    case artists = "Artists"
    case podcasts = "Podcasts"

    var id: String {
        self.rawValue
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .playlists: "music.note.list"
        case .artists: "person.fill"
        case .podcasts: "mic.fill"
        }
    }

    var displayName: String {
        switch self {
        case .all:
            String(localized: "All")
        case .playlists:
            String(localized: "Playlists")
        case .artists:
            String(localized: "Artists")
        case .podcasts:
            String(localized: "Podcasts")
        }
    }
}

// MARK: - LibraryView

/// Library view displaying user's playlists and podcast shows.
@available(macOS 26.0, *)
struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(GlobalNavigationCoordinator.self) private var globalNavigation
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var settings = SettingsManager.shared

    @Binding var navigationPath: NavigationPath
    @State private var selectedFilter: LibraryFilter = .all

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
                        LoadingView(String(localized: "Loading your library..."))
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
            .localizedNavigationTitle("Library")
            .navigationDestinations(client: self.viewModel.client)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Library.container)
        .environment(self.viewModel)
        .navigationSwipeGestures(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
            await self.viewModel.reloadIfNeededOnActivation()
        }
        .onAppear {
            self.consumePendingNavigation()
        }
        .onChange(of: self.globalNavigation.pendingArtist) { _, _ in
            self.consumePendingNavigation()
        }
        .onChange(of: self.globalNavigation.pendingPlaylist) { _, _ in
            self.consumePendingNavigation()
        }
        .task(id: "\(self.navigationPath.count)-\(self.viewModel.activationReloadGeneration)") {
            guard self.navigationPath.isEmpty else { return }
            await self.viewModel.reloadIfNeededOnActivation()
        }
        .refreshable {
            await self.viewModel.refresh()
        }
    }

    /// Drains any cross-tab navigation requests posted to the global
    /// coordinator (e.g. clicks on the sidebar now-playing card).
    private func consumePendingNavigation() {
        if let artist = self.globalNavigation.pendingArtist {
            self.navigationPath.append(artist)
            self.globalNavigation.pendingArtist = nil
        }
        if let playlist = self.globalNavigation.pendingPlaylist {
            self.navigationPath.append(playlist)
            self.globalNavigation.pendingPlaylist = nil
        }
    }

    // MARK: - Views

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Filter chips
                self.filterChips

                // Combined grid with filtered content
                self.libraryGrid
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { filter in
                self.filterChip(filter)
            }
            Spacer()
        }
    }

    private func filterChip(_ filter: LibraryFilter) -> some View {
        let isSelected = self.selectedFilter == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.selectedFilter = filter
            }
        } label: {
            Text(filter.displayName)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    /// All library items combined and filtered.
    private var filteredItems: [LibraryItem] {
        var items: [LibraryItem] = []

        switch self.selectedFilter {
        case .all:
            items = self.viewModel.playlists.map { .playlist($0) }
                + self.viewModel.artists.map { .artist($0) }
                + self.viewModel.podcastShows.map { .podcast($0) }
        case .playlists:
            items = self.viewModel.playlists.map { .playlist($0) }
        case .artists:
            items = self.viewModel.artists.map { .artist($0) }
        case .podcasts:
            items = self.viewModel.podcastShows.map { .podcast($0) }
        }

        return items
    }

    private var libraryGrid: some View {
        Group {
            if self.filteredItems.isEmpty {
                self.emptyStateView
            } else if self.settings.displayMode == .list {
                self.libraryList
            } else {
                self.libraryGridContent
            }
        }
    }

    private var libraryGridContent: some View {
        let isCompact = self.settings.displayDensity == .compact
        let minSize: CGFloat = isCompact ? 120 : 160
        let maxSize: CGFloat = isCompact ? 150 : 200
        let spacing: CGFloat = isCompact ? 10 : 16

        return LazyVGrid(columns: [
            GridItem(.adaptive(minimum: minSize, maximum: maxSize), spacing: spacing),
        ], spacing: spacing) {
            ForEach(self.filteredItems) { item in
                switch item {
                case let .playlist(playlist):
                    self.playlistCard(playlist)
                case let .artist(artist):
                    self.artistCard(artist)
                case let .podcast(show):
                    self.podcastCard(show)
                }
            }
        }
    }

    private var libraryList: some View {
        let isCompact = self.settings.displayDensity == .compact
        let thumbSize: CGFloat = isCompact ? 36 : 48
        let rowVPadding: CGFloat = isCompact ? 4 : 8

        return LazyVStack(spacing: 0) {
            ForEach(self.filteredItems) { item in
                self.listRow(item, thumbSize: thumbSize, vPadding: rowVPadding)
                Divider().padding(.leading, thumbSize + 28)
            }
        }
    }

    private func listRow(_ item: LibraryItem, thumbSize: CGFloat, vPadding: CGFloat) -> some View {
        Button {
            switch item {
            case let .playlist(p): self.navigationPath.append(p)
            case let .artist(a): self.navigationPath.append(a)
            case let .podcast(s): self.navigationPath.append(s)
            }
        } label: {
            HStack(spacing: 12) {
                self.listThumbnail(for: item, size: thumbSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.listTitle(for: item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = self.listSubtitle(for: item) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: self.listKindIcon(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, vPadding)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow(cornerRadius: 6))
    }

    @ViewBuilder
    private func listThumbnail(for item: LibraryItem, size: CGFloat) -> some View {
        let url: URL? = switch item {
        case let .playlist(p): p.thumbnailURL?.highQualityThumbnailURL
        case let .artist(a): a.thumbnailURL?.highQualityThumbnailURL
        case let .podcast(s): s.thumbnailURL
        }
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

    private func listTitle(for item: LibraryItem) -> String {
        switch item {
        case let .playlist(p): p.title
        case let .artist(a): a.name
        case let .podcast(s): s.title
        }
    }

    private func listSubtitle(for item: LibraryItem) -> String? {
        switch item {
        case let .playlist(p):
            p.author ?? (p.trackCount.map { "\($0) tracks" })
        case .artist:
            String(localized: "Artist")
        case let .podcast(s):
            s.author
        }
    }

    private func listKindIcon(for item: LibraryItem) -> String {
        switch item {
        case .playlist: "music.note.list"
        case .artist: "person.fill"
        case .podcast: "mic.fill"
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: self.selectedFilter.icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(self.emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(self.emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateTitle: String {
        switch self.selectedFilter {
        case .all:
            String(localized: "Your library is empty")
        case .playlists:
            String(localized: "No playlists yet")
        case .artists:
            String(localized: "No artists yet")
        case .podcasts:
            String(localized: "No podcasts yet")
        }
    }

    private var emptyStateMessage: String {
        switch self.selectedFilter {
        case .all:
            String(localized: "Save playlists, follow artists, and subscribe to podcasts on YouTube Music to see them here.")
        case .playlists:
            String(localized: "Create or save playlists on YouTube Music to see them here.")
        case .artists:
            String(localized: "Follow artists on YouTube Music to see them here.")
        case .podcasts:
            String(localized: "Subscribe to podcasts on YouTube Music to see them here.")
        }
    }

    private func playlistCard(_ playlist: Playlist) -> some View {
        Button {
            self.navigationPath.append(playlist)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                CachedAsyncImage(url: playlist.thumbnailURL?.highQualityThumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 160, height: 160)
                .clipShape(.rect(cornerRadius: 8))

                // Title
                Text(playlist.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 160, alignment: .leading)

                // Track count
                if let count = playlist.trackCount {
                    Text("\(count) songs", comment: "Playlist track count")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func podcastCard(_ show: PodcastShow) -> some View {
        Button {
            self.navigationPath.append(show)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                CachedAsyncImage(url: show.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 160, height: 160)
                .clipShape(.rect(cornerRadius: 8))

                // Title
                Text(show.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 160, alignment: .leading)

                // Author
                if let author = show.author {
                    Text(author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            FavoritesContextMenu.menuItem(for: show, manager: self.favoritesManager)
        }
    }

    private func artistCard(_ artist: Artist) -> some View {
        Button {
            self.navigationPath.append(artist)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CachedAsyncImage(url: artist.thumbnailURL?.highQualityThumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 128, height: 128)
                .clipShape(Circle())
                .frame(width: 160)

                Text(artist.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 160)

                Text(String(localized: "Artist"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 160)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            FavoritesContextMenu.menuItem(for: artist, manager: self.favoritesManager)
            ShareContextMenu.menuItem(for: artist)
        }
    }
}

// MARK: - LibraryItem

/// Represents a library item that can be a playlist, artist, or podcast show.
enum LibraryItem: Identifiable {
    case playlist(Playlist)
    case artist(Artist)
    case podcast(PodcastShow)

    var id: String {
        switch self {
        case let .playlist(playlist):
            "playlist-\(playlist.id)"
        case let .artist(artist):
            "artist-\(artist.id)"
        case let .podcast(show):
            "podcast-\(show.id)"
        }
    }
}

#Preview {
    @Previewable @State var navigationPath = NavigationPath()
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    LibraryView(viewModel: LibraryViewModel(client: client), navigationPath: $navigationPath)
        .environment(PlayerService())
        .environment(FavoritesManager.shared)
}
