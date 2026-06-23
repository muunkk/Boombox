import SwiftUI

/// View displaying the user's YouTube Music listening history.
/// Fetches history from the API and displays songs grouped by time period.
@available(macOS 26.0, *)
struct HistoryView: View {
    @State var viewModel: HistoryViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Binding var navigationPath: NavigationPath
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var hoveredSongId: String?

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: String(localized: "No Connection"),
                        message: String(localized: "Please check your internet connection and try again.")
                    ) {
                        Task { await self.performRefresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        LoadingView(String(localized: "Loading..."))
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.performRefresh() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .localizedNavigationTitle("Listening History")
            .navigationDestinations(client: self.viewModel.client)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.History.container)
        .navigationSwipeGestures(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
                self.viewModel.syncObservedPlayback(videoId: self.playerService.currentTrack?.videoId)
            }
        }
        .onAppear {
            self.viewModel.schedulePlaybackRefreshIfNeeded(for: self.playerService.currentTrack?.videoId)
        }
        .onChange(of: self.playerService.currentTrack?.videoId) { _, newVideoId in
            self.viewModel.schedulePlaybackRefreshIfNeeded(for: newVideoId)
        }
        .refreshable {
            await self.performRefresh()
        }
    }

    /// Refreshes the history list. Returns whether the data changed.
    @discardableResult
    private func performRefresh() async -> Bool {
        await self.viewModel.refresh()
    }

    // MARK: - Content

    private var headerView: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "History"))
                    .font(.title2)
                    .fontWeight(.bold)

                let todayCount = self.viewModel.sections.first?.items.count ?? 0
                Text(String(localized: "\(todayCount) songs listened today"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No listening history yet")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Songs you play will appear here", comment: "History empty state")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                self.headerView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                if self.viewModel.sections.isEmpty {
                    self.emptyStateView
                }

                ForEach(self.viewModel.sections) { section in
                    Text(section.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    let songs = section.items.compactMap { item -> Song? in
                        if case let .song(song) = item { return song }
                        return nil
                    }
                    let rows = Self.historyRows(for: songs, sectionID: section.id)

                    ForEach(rows) { row in
                        self.songRow(row.song, allSongs: songs, index: row.index)
                            .id(row.id)
                        if row.index < songs.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .accessibilityIdentifier(AccessibilityID.History.scrollView)
    }

    // MARK: - Stable Row Identity

    /// A history list row paired with a stable, section-unique identity.
    ///
    /// `Song.id` equals its `videoId`, so a track played more than once in the
    /// same time period yields duplicate ids. To keep `ForEach` identity stable
    /// across the playback-driven refresh (which prepends rows and shifts every
    /// index), each row is keyed by `section + videoId + occurrence`, which is
    /// unique within the section and tolerates duplicates — unlike the previous
    /// index-based `id: \.offset` anti-pattern.
    struct HistorySongRow: Identifiable {
        let id: String
        let song: Song
        let index: Int
    }

    /// Builds stable, section-unique identities for a section's songs.
    static func historyRows(for songs: [Song], sectionID: String) -> [HistorySongRow] {
        var occurrences: [String: Int] = [:]
        return songs.enumerated().map { index, song in
            let occurrence = occurrences[song.videoId, default: 0]
            occurrences[song.videoId] = occurrence + 1
            return HistorySongRow(
                id: "\(sectionID)-\(song.videoId)-\(occurrence)",
                song: song,
                index: index
            )
        }
    }

    // MARK: - Song Row

    private func songRow(_ song: Song, allSongs: [Song], index: Int) -> some View {
        let isHovering = self.hoveredSongId == "\(song.id)-\(index)"
        let hoverKey = "\(song.id)-\(index)"

        return Button {
            Task {
                await self.playerService.playQueue(allSongs, startingAt: index)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    SongThumbnailView(song: song)
                    if isHovering {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.45))
                            .frame(width: 48, height: 48)
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .pointingHandCursor()

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14))
                        .lineLimit(1)

                    Text(song.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(song.durationDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
                    .padding(.horizontal, 12)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            if hovering {
                self.hoveredSongId = hoverKey
            } else if self.hoveredSongId == hoverKey {
                self.hoveredSongId = nil
            }
        }
        .contextMenu {
            AddToQueueContextMenu(song: song, playerService: self.playerService)

            Divider()

            Button {
                Task { await self.playerService.play(song: song) }
            } label: {
                Label(String(localized: "Play"), systemImage: "play.fill")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: song, manager: self.favoritesManager)

            Divider()

            StartRadioContextMenu.menuItem(for: song, playerService: self.playerService)

            Divider()

            ShareContextMenu.menuItem(for: song)

            Divider()

            if let artist = song.artists.first(where: { $0.hasNavigableId }) {
                NavigationLink(value: artist) {
                    Label(String(localized: "Go to Artist"), systemImage: "person")
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
                    Label(String(localized: "Go to Album"), systemImage: "square.stack")
                }
            }
        }
    }
}
