import SwiftUI

// MARK: - PlaylistDetailView

/// Detail view for a playlist showing its tracks.
@available(macOS 26.0, *)
struct PlaylistDetailView: View {
    let playlist: Playlist
    @State var viewModel: PlaylistDetailViewModel
    /// videoId of the currently hovered track row, used to swap the index column
    /// for a play icon and to render the row's background highlight. Keyed by id
    /// rather than index so list mutations (pagination, removal) don't briefly
    /// re-attach the hover to a different track.
    @State private var hoveredTrackId: String?
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?

    /// Tracks whether this playlist has been added to library in this session.
    @State private var isAddedToLibrary: Bool = false

    /// Computed property to check if playlist is in library.
    private var isInLibrary: Bool {
        self.libraryViewModel?.isInLibrary(playlistId: self.playlist.id) ?? false
    }

    init(playlist: Playlist, viewModel: PlaylistDetailViewModel) {
        self.playlist = playlist
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView(String(localized: "Loading playlist..."))
            case .loaded, .loadingMore:
                if let detail = viewModel.playlistDetail {
                    self.contentView(detail)
                } else {
                    ErrorView(title: String(localized: "Unable to load playlist"), message: String(localized: "Playlist not found")) {
                        Task { await self.viewModel.load() }
                    }
                }
            case let .error(error):
                ErrorView(error: error) {
                    Task { await self.viewModel.load() }
                }
            }
        }
        .accentBackground(from: self.viewModel.playlistDetail?.thumbnailURL?.highQualityThumbnailURL)
        .navigationTitle(self.playlist.title)
        .toolbarBackgroundVisibility(.hidden, for: .automatic)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .error = self.viewModel.loadingState {} else {
                PlayerBar()
            }
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

    private func contentView(_ detail: PlaylistDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                self.headerView(detail)

                Divider()

                // Tracks
                let fallbackAlbum = Album(
                    id: detail.id,
                    title: detail.title,
                    artists: detail.author.map { [Artist(id: "unknown", name: $0)] },
                    thumbnailURL: detail.thumbnailURL,
                    year: nil,
                    trackCount: detail.trackCount ?? detail.tracks.count
                )
                self.tracksView(detail.tracks, isAlbum: detail.isAlbum, author: detail.author, fallbackAlbum: fallbackAlbum)
            }
            .padding(24)
        }
    }

    private func headerView(_ detail: PlaylistDetail) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Thumbnail
            CachedAsyncImage(url: detail.thumbnailURL?.highQualityThumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 180, height: 180)
            .clipShape(.rect(cornerRadius: 8))
            .fadeIn(duration: 0.3)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.isAlbum ? String(localized: "Album") : String(localized: "Playlist"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(detail.title)
                    .font(.title)
                    .fontWeight(.bold)

                if let displayName = self.displayAuthor(for: detail) {
                    if let artist = self.navigableArtist(for: detail) {
                        NavigationLink(value: artist) {
                            Text(displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help(String(localized: "Go to Artist"))
                    } else {
                        Text(displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                self.headerButtons(detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func makeFallbackAlbum(from detail: PlaylistDetail) -> Album {
        Album(
            id: detail.id,
            title: detail.title,
            artists: detail.author.map { [Artist(id: "unknown", name: $0)] },
            thumbnailURL: detail.thumbnailURL,
            year: nil,
            trackCount: detail.trackCount ?? detail.tracks.count
        )
    }

    private func headerButtons(_ detail: PlaylistDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                // Play all button
                Button {
                    let fallbackAlbum = self.makeFallbackAlbum(from: detail)
                    self.playAll(detail.tracks, fallbackArtist: detail.author, fallbackAlbum: fallbackAlbum)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(detail.tracks.isEmpty)

                // Shuffle button
                Button {
                    let fallbackAlbum = self.makeFallbackAlbum(from: detail)
                    self.playAll(detail.tracks.shuffled(), fallbackArtist: detail.author, fallbackAlbum: fallbackAlbum)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(detail.tracks.isEmpty)

                // Play Next button
                Button {
                    let fallbackAlbum = self.makeFallbackAlbum(from: detail)
                    SongActionsHelper.addSongsToQueueNext(
                        detail.tracks,
                        playerService: self.playerService,
                        fallbackArtist: detail.author,
                        fallbackAlbum: fallbackAlbum
                    )
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(detail.tracks.isEmpty)

                // Add to Queue button
                Button {
                    let fallbackAlbum = self.makeFallbackAlbum(from: detail)
                    SongActionsHelper.addSongsToQueueLast(
                        detail.tracks,
                        playerService: self.playerService,
                        fallbackArtist: detail.author,
                        fallbackAlbum: fallbackAlbum
                    )
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(detail.tracks.isEmpty)

                // Add/Remove Library button
                let currentlyInLibrary = self.isInLibrary || self.isAddedToLibrary
                Button {
                    self.toggleLibrary()
                } label: {
                    Label(
                        currentlyInLibrary ? String(localized: "Added to Library") : String(localized: "Add to Library"),
                        systemImage: currentlyInLibrary ? "checkmark.circle.fill" : "plus.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text(self.metadataText(for: detail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metadataText(for detail: PlaylistDetail) -> String {
        if let duration = detail.duration {
            return "\(detail.trackCountDisplay) • \(duration)"
        }

        return detail.trackCountDisplay
    }

    private func tracksView(_ tracks: [Song], isAlbum: Bool, author: String?, fallbackAlbum: Album? = nil) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                self.trackRow(track, index: index, tracks: tracks, isAlbum: isAlbum, author: author, fallbackAlbum: fallbackAlbum)
                    .task {
                        if index >= tracks.count - 3, self.viewModel.hasMore {
                            await self.viewModel.loadMore()
                        }
                    }

                if index < tracks.count - 1 {
                    Divider()
                        // For albums: 28 (index) + 12 (spacing)
                        // For playlists: 28 (index) + 12 (spacing) + 40 (thumbnail) + 16 (spacing)
                        .padding(.leading, isAlbum ? 40 : 96)
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

    @ViewBuilder
    private func trackLeadingIndicator(
        index: Int,
        isCurrent: Bool,
        isHovering: Bool,
        play: @escaping () -> Void
    ) -> some View {
        if isCurrent {
            NowPlayingIndicator(isPlaying: self.playerService.isPlaying, size: 14)
        } else if isHovering {
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel(String(localized: "Play"))
        } else {
            Text("\(index + 1)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func trackRow(_ track: Song, index: Int, tracks: [Song], isAlbum: Bool, author: String?, fallbackAlbum: Album? = nil) -> some View {
        let isCurrent = self.playerService.currentTrack?.videoId == track.videoId
        let isHovering = self.hoveredTrackId == track.videoId

        let play = {
            self.playTrackInQueue(tracks: tracks, startingAt: index, fallbackArtist: author, fallbackAlbum: fallbackAlbum)
        }

        return HStack(spacing: 12) {
            // Single click is intentionally a no-op for both albums and playlists.
            // On hover the index swaps to a play.fill that single-clicks to play
            // (discoverability), and a double-click anywhere on the row plays.
            self.trackLeadingIndicator(index: index, isCurrent: isCurrent, isHovering: isHovering, play: play)
                .frame(width: 28, alignment: .trailing)

            // Thumbnail - only show for playlists (different album art per track)
            // Albums share the same artwork, so we hide per-track thumbnails
            if !isAlbum {
                CachedAsyncImage(url: track.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                }
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 4))
            }

            // Title and artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14))
                    .foregroundStyle(isCurrent ? .red : .primary)
                    .lineLimit(1)

                Text(track.artistsDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration
            Text(track.durationDisplay)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            if hovering {
                self.hoveredTrackId = track.videoId
            } else if self.hoveredTrackId == track.videoId {
                self.hoveredTrackId = nil
            }
        }
        .onTapGesture(count: 2, perform: play)
        .staggeredAppearance(index: min(index, 10))
        .contextMenu {
            self.trackContextMenu(track: track, play: play)
        }
    }

    @ViewBuilder
    private func trackContextMenu(track: Song, play: @escaping () -> Void) -> some View {
        AddToQueueContextMenu(song: track, playerService: self.playerService)

        Divider()

        Button(action: play) {
            Label("Play", systemImage: "play.fill")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: track, manager: self.favoritesManager)

        Divider()

        LikeDislikeContextMenu(song: track, likeStatusManager: self.likeStatusManager)

        Divider()

        StartRadioContextMenu.menuItem(for: track, playerService: self.playerService)

        Divider()

        Button {
            Task { await SongActionsHelper.addToLibrary(track, client: self.viewModel.client) }
        } label: {
            Label("Add to Library", systemImage: "plus.circle")
        }

        Divider()

        ShareContextMenu.menuItem(for: track)

        Divider()

        // Go to Artist - show first artist with valid ID
        if let artist = track.artists.first(where: { $0.hasNavigableId }) {
            NavigationLink(value: artist) {
                Label("Go to Artist", systemImage: "person")
            }
        }

        // Go to Album - show if album has valid browse ID
        if let album = track.album, album.hasNavigableId {
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL ?? track.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            NavigationLink(value: playlist) {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
    }

    /// Resolves a navigable Artist for the header subtitle on album pages.
    ///
    /// Preference order:
    ///   1. The header's own `authorChannelId` (extracted from
    ///      `straplineTextOne` / `subtitle` navigation endpoints). This is the
    ///      authoritative source — without it, albums whose track rows have
    ///      text-only artist runs (common on YT Music) had no path back to the
    ///      artist page.
    ///   2. The first track that carries a navigable artist.
    /// Returns nil on non-album pages (regular playlists usually have a
    /// user/creator name as author, not an artist channel).
    private func navigableArtist(for detail: PlaylistDetail) -> Artist? {
        guard detail.isAlbum else { return nil }
        if let channelId = detail.authorChannelId,
           Artist.isNavigableId(channelId),
           let name = detail.author, !name.isEmpty
        {
            return Artist(id: channelId, name: name)
        }
        return detail.tracks.lazy.compactMap { track in
            track.artists.first(where: { $0.hasNavigableId })
        }.first
    }

    /// Resolves a non-empty author string to display under the title.
    /// Falls back to the first track's artists when the API/playlist row
    /// didn't carry an author through.
    private func displayAuthor(for detail: PlaylistDetail) -> String? {
        if let author = detail.author, !author.isEmpty {
            return author
        }
        if detail.isAlbum,
           let firstTrack = detail.tracks.first,
           !firstTrack.artistsDisplay.isEmpty
        {
            return firstTrack.artistsDisplay
        }
        return nil
    }

    // MARK: - Actions

    private func playTrackInQueue(tracks: [Song], startingAt index: Int, fallbackArtist: String? = nil, fallbackAlbum: Album? = nil) {
        let cleanedTracks = self.cleanTracks(tracks, fallbackArtist: fallbackArtist, fallbackAlbum: fallbackAlbum)
        Task {
            await self.playerService.playQueue(cleanedTracks, startingAt: index)
        }
    }

    private func playAll(_ tracks: [Song], fallbackArtist: String? = nil, fallbackAlbum: Album? = nil) {
        guard !tracks.isEmpty else { return }
        let cleanedTracks = self.cleanTracks(tracks, fallbackArtist: fallbackArtist, fallbackAlbum: fallbackAlbum)
        Task {
            await self.playerService.playQueue(cleanedTracks, startingAt: 0)
        }
    }

    /// Cleans track artists and applies fallback artist/album when needed.
    private func cleanTracks(_ tracks: [Song], fallbackArtist: String?, fallbackAlbum: Album? = nil) -> [Song] {
        tracks.map { song in
            var cleanedArtists = song.artists.compactMap { artist -> Artist? in
                if artist.name == "Album" { return nil }
                var cleanName = artist.name
                if cleanName.hasPrefix("Album, ") {
                    cleanName = String(cleanName.dropFirst(7))
                }
                return Artist(id: artist.id, name: cleanName)
            }

            // Use fallback artist if artists are empty (and clean the fallback too)
            if cleanedArtists.isEmpty, let fallback = fallbackArtist, !fallback.isEmpty {
                var cleanFallback = fallback
                if cleanFallback == "Album" {
                    cleanFallback = "Unknown Artist"
                } else if cleanFallback.hasPrefix("Album, ") {
                    cleanFallback = String(cleanFallback.dropFirst(7))
                }
                // Also handle case where it's "Album, Artist" but we got it as a combined string
                if cleanFallback.contains("Album,") {
                    let parts = cleanFallback.split(separator: ",", maxSplits: 1)
                    if parts.count > 1 {
                        cleanFallback = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    }
                }
                cleanedArtists = [Artist(id: "unknown", name: cleanFallback)]
            }

            // Use fallback album if song doesn't have album info
            let finalAlbum = song.album ?? fallbackAlbum
            // Use fallback thumbnail if song doesn't have one
            let finalThumbnail = song.thumbnailURL ?? fallbackAlbum?.thumbnailURL

            return Song(
                id: song.id,
                title: song.title,
                artists: cleanedArtists,
                album: finalAlbum,
                duration: song.duration,
                thumbnailURL: finalThumbnail,
                videoId: song.videoId
            )
        }
    }

    private func toggleLibrary() {
        let currentlyInLibrary = self.isInLibrary || self.isAddedToLibrary
        HapticService.success()
        Task {
            if currentlyInLibrary {
                await SongActionsHelper.removePlaylistFromLibrary(
                    self.playlist,
                    client: self.viewModel.client,
                    libraryViewModel: self.libraryViewModel
                )
                self.isAddedToLibrary = false
            } else {
                await SongActionsHelper.addPlaylistToLibrary(
                    self.playlist,
                    client: self.viewModel.client,
                    libraryViewModel: self.libraryViewModel
                )
                self.isAddedToLibrary = true
            }
        }
    }
}

#Preview {
    let playlist = Playlist(
        id: "test",
        title: "Test Playlist",
        description: nil,
        thumbnailURL: nil,
        trackCount: 10,
        author: "Test Author"
    )
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    PlaylistDetailView(
        playlist: playlist,
        viewModel: PlaylistDetailViewModel(
            playlist: playlist,
            client: client
        )
    )
    .environment(PlayerService())
}
