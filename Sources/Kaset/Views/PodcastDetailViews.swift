import SwiftUI

// MARK: - PodcastShowView

@available(macOS 26.0, *)
struct PodcastShowView: View {
    let show: PodcastShow
    let client: any YTMusicClientProtocol
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?

    @State private var episodes: [PodcastEpisode] = []
    @State private var continuationToken: String?
    @State private var loadingState: LoadingState = .idle
    @State private var isSubscribed: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var showAllEpisodes = false
    @State private var subscriptionError: String?

    /// Number of episodes to show in the preview
    private let previewEpisodeCount = 5

    var body: some View {
        Group {
            if case let .error(error) = self.loadingState {
                ErrorView(error: error) {
                    // Reset to .idle so loadShow()'s guard allows the retry.
                    self.loadingState = .idle
                    Task { await self.loadShow() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        self.headerView

                        Divider()

                        // Episodes list
                        self.episodesList
                    }
                    .padding(24)
                }
            }
        }
        .accentBackground(from: self.show.thumbnailURL)
        .navigationTitle(self.show.title)
        .navigationDestination(for: AllEpisodesDestination.self) { destination in
            AllEpisodesView(
                show: destination.show,
                initialEpisodes: destination.episodes,
                continuationToken: destination.continuationToken,
                client: self.client
            )
        }
        .navigationDestination(isPresented: self.$showAllEpisodes) {
            AllEpisodesView(
                show: self.show,
                initialEpisodes: self.episodes,
                continuationToken: self.continuationToken,
                client: self.client
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hide the PlayerBar over the error state, matching ArtistDetailView.
            if case .error = self.loadingState {} else {
                PlayerBar()
            }
        }
        .task {
            await self.loadShow()
        }
        .alert(
            String(localized: "Subscription Error"),
            isPresented: Binding(
                get: { self.subscriptionError != nil },
                set: { if !$0 { self.subscriptionError = nil } }
            )
        ) {
            Button(String(localized: "OK")) { self.subscriptionError = nil }
        } message: {
            Text(self.subscriptionError ?? String(localized: "An unknown error occurred"))
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 20) {
            // Artwork
            CachedAsyncImage(url: self.show.thumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                FavoritesContextMenu.menuItem(for: self.show, manager: self.favoritesManager)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(self.show.title)
                    .font(.title)
                    .fontWeight(.bold)

                if let author = show.author {
                    Text(author)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let description = show.description {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    // Play button - plays from the first episode and queues the rest
                    if !self.episodes.isEmpty {
                        Button {
                            self.playEpisodeInQueue(at: 0)
                        } label: {
                            Label("Play Latest", systemImage: "play.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.glassProminent)
                    }

                    // Add to Library button
                    Button {
                        Task {
                            await self.toggleSubscription()
                        }
                    } label: {
                        if self.isSubscribing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                self.isSubscribed ? String(localized: "In Library") : String(localized: "Add to Library"),
                                systemImage: self.isSubscribed ? "checkmark" : "plus"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.isSubscribing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var episodesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with "Show All" button
            HStack {
                Text("Episodes")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if self.episodes.count > self.previewEpisodeCount || self.continuationToken != nil {
                    Button {
                        self.showAllEpisodes = true
                    } label: {
                        Text("Show All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }

            if self.loadingState == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(self.previewEpisodes.enumerated()), id: \.element.id) { index, episode in
                        PodcastEpisodeRow(episode: episode) {
                            self.playEpisodeInQueue(at: index)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    /// Episodes to show in the preview (limited to previewEpisodeCount)
    private var previewEpisodes: [PodcastEpisode] {
        Array(self.episodes.prefix(self.previewEpisodeCount))
    }

    private func loadShow() async {
        guard self.loadingState == .idle else { return }
        self.loadingState = .loading

        do {
            let showDetail = try await client.getPodcastShow(browseId: self.show.id)
            self.episodes = showDetail.episodes
            self.continuationToken = showDetail.continuationToken
            self.isSubscribed = showDetail.isSubscribed
            self.loadingState = .loaded
        } catch {
            DiagnosticsLogger.api.error("Failed to load podcast show: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Plays an episode and queues the remaining episodes from the show.
    private func playEpisodeInQueue(at index: Int) {
        let songs = self.episodes.map { self.episodeToSong($0) }
        Task {
            await self.playerService.playQueue(songs, startingAt: index)
        }
    }

    /// Converts a podcast episode to a Song for playback.
    private func episodeToSong(_ episode: PodcastEpisode) -> Song {
        Song(
            id: episode.id,
            title: episode.title,
            artists: episode.showTitle.map { [Artist(id: "podcast", name: $0)] } ?? [],
            album: nil,
            duration: episode.durationSeconds.map { TimeInterval($0) },
            thumbnailURL: episode.thumbnailURL,
            videoId: episode.id
        )
    }

    private func toggleSubscription() async {
        self.isSubscribing = true
        defer { self.isSubscribing = false }

        DiagnosticsLogger.api.debug("toggleSubscription called, isSubscribed=\(self.isSubscribed), showId=\(self.show.id)")

        do {
            if self.isSubscribed {
                try await SongActionsHelper.unsubscribeFromPodcast(
                    self.show,
                    client: self.client,
                    libraryViewModel: self.libraryViewModel
                )
                self.isSubscribed = false
                DiagnosticsLogger.api.debug("Unsubscribe completed, isSubscribed now=\(self.isSubscribed)")
            } else {
                try await SongActionsHelper.subscribeToPodcast(
                    self.show,
                    client: self.client,
                    libraryViewModel: self.libraryViewModel
                )
                self.isSubscribed = true
                DiagnosticsLogger.api.debug("Subscribe completed, isSubscribed now=\(self.isSubscribed)")
            }
        } catch {
            let errorMessage = error.localizedDescription
            DiagnosticsLogger.api.error(
                "Failed to toggle podcast subscription for \(self.show.title): \(errorMessage)"
            )
            self.subscriptionError = errorMessage
        }
    }
}

// MARK: - PodcastEpisodeRow

@available(macOS 26.0, *)
struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                CachedAsyncImage(url: self.episode.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    HStack {
                        Text(self.episode.title)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer()
                        if let duration = episode.formattedDuration {
                            Text(duration)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Description
                    if let description = episode.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Date and progress
                    HStack {
                        if let date = episode.publishedDate {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if self.episode.isPlayed {
                            Label("Played", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress bar
                    if self.episode.playbackProgress > 0, !self.episode.isPlayed {
                        ProgressView(value: self.episode.playbackProgress)
                            .tint(.accentColor)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AllEpisodesDestination

/// Navigation destination for the all episodes view.
struct AllEpisodesDestination: Hashable {
    let show: PodcastShow
    let episodes: [PodcastEpisode]
    let continuationToken: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.show.id)
    }

    static func == (lhs: AllEpisodesDestination, rhs: AllEpisodesDestination) -> Bool {
        lhs.show.id == rhs.show.id
    }
}

// MARK: - AllEpisodesView

/// View displaying all episodes of a podcast show with infinite scroll pagination.
@available(macOS 26.0, *)
struct AllEpisodesView: View {
    let show: PodcastShow
    let initialEpisodes: [PodcastEpisode]
    let continuationToken: String?
    let client: any YTMusicClientProtocol

    @Environment(PlayerService.self) private var playerService
    @State private var episodes: [PodcastEpisode] = []
    @State private var currentContinuationToken: String?
    @State private var isLoadingMore = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(self.episodes.enumerated()), id: \.element.id) { index, episode in
                    PodcastEpisodeRow(episode: episode) {
                        self.playEpisodeInQueue(at: index)
                    }
                    Divider()

                    // Infinite scroll trigger - load more when near the end
                    if episode.id == self.episodes.last?.id, self.currentContinuationToken != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .task {
                                await self.loadMoreEpisodes()
                            }
                    }
                }
            }
            .padding(24)
        }
        .accentBackground(from: self.show.thumbnailURL)
        .localizedNavigationTitle("All Episodes")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .onAppear {
            // Initialize with episodes passed from parent
            if self.episodes.isEmpty {
                self.episodes = self.initialEpisodes
                self.currentContinuationToken = self.continuationToken
            }
        }
    }

    private func loadMoreEpisodes() async {
        guard !self.isLoadingMore, let token = self.currentContinuationToken else { return }
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }

        do {
            let continuation = try await self.client.getPodcastEpisodesContinuation(token: token)
            self.episodes.append(contentsOf: continuation.episodes)
            self.currentContinuationToken = continuation.continuationToken
            DiagnosticsLogger.api.info("Loaded \(continuation.episodes.count) more episodes")
        } catch {
            DiagnosticsLogger.api.error("Failed to load more episodes: \(error.localizedDescription)")
        }
    }

    /// Plays an episode and queues the remaining episodes.
    private func playEpisodeInQueue(at index: Int) {
        let songs = self.episodes.map { self.episodeToSong($0) }
        Task {
            await self.playerService.playQueue(songs, startingAt: index)
        }
    }

    /// Converts a podcast episode to a Song for playback.
    private func episodeToSong(_ episode: PodcastEpisode) -> Song {
        Song(
            id: episode.id,
            title: episode.title,
            artists: episode.showTitle.map { [Artist(id: "podcast", name: $0)] } ?? [],
            album: nil,
            duration: episode.durationSeconds.map { TimeInterval($0) },
            thumbnailURL: episode.thumbnailURL,
            videoId: episode.id
        )
    }
}
