import Foundation
import Observation

/// View model for the Liked Music view.
@MainActor
@Observable
final class LikedMusicViewModel {
    private struct LiveSyncTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// Sort orders offered in the Liked Songs UI.
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateAdded
        case title
        case artist
        case duration

        var id: String {
            self.rawValue
        }

        var label: String {
            switch self {
            case .dateAdded: String(localized: "Recently Added")
            case .title: String(localized: "Title")
            case .artist: String(localized: "Artist")
            case .duration: String(localized: "Duration")
            }
        }
    }

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Liked songs.
    private(set) var songs: [Song] = []

    /// Whether more songs are available to load.
    private(set) var hasMore: Bool = false

    /// Active search query (filters title/artist). Set via `setSearchQuery`.
    private(set) var searchQuery: String = ""

    /// Active sort order.
    var sortOrder: SortOrder = .dateAdded

    /// Whether a background "load all pages for search" pass is running.
    private(set) var isLoadingAll = false

    @ObservationIgnored
    private var loadAllTask: Task<Void, Never>?

    @ObservationIgnored
    private var loadAllGeneration = 0

    /// Continuation cursor for the next page of liked songs. Owned by this view
    /// model (not the shared client) so repeated or concurrent liked-music loads
    /// never cross pagination state.
    @ObservationIgnored
    private var continuationToken: String?

    /// Number of consecutive continuation pages that contained only already-seen
    /// songs. Used to keep paginating past legitimate duplicates while still
    /// bounding runaway pagination on overlapping feeds.
    @ObservationIgnored
    private var consecutiveEmptyPages = 0

    /// Maximum number of consecutive all-duplicate pages to tolerate before
    /// giving up on pagination (guards against infinite loops).
    private static let maxConsecutiveEmptyPages = 3

    /// The API client.
    let client: any YTMusicClientProtocol
    private static let logger = DiagnosticsLogger.api
    @ObservationIgnored
    private var liveSyncTasks: [String: LiveSyncTask] = [:]

    init(client: any YTMusicClientProtocol) {
        self.client = client
    }

    /// Songs after applying the active search filter and sort order.
    var displaySongs: [Song] {
        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let filtered: [Song] = if query.isEmpty {
            self.songs
        } else {
            self.songs.filter { song in
                song.title.localizedLowercase.contains(query)
                    || song.artistsDisplay.localizedLowercase.contains(query)
            }
        }

        switch self.sortOrder {
        case .dateAdded:
            return filtered
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted { $0.artistsDisplay.localizedCaseInsensitiveCompare($1.artistsDisplay) == .orderedAscending }
        case .duration:
            return filtered.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    /// Updates the search query. When non-empty, drains all remaining pages in
    /// the background so results are complete (the liked feed is paginated and
    /// has no server-side within-playlist search). When cleared, cancels that pass.
    func setSearchQuery(_ query: String) {
        self.searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.loadAllTask?.cancel()
            self.loadAllTask = nil
            self.isLoadingAll = false
        } else if self.hasMore, self.loadAllTask == nil {
            self.loadAllGeneration += 1
            let generation = self.loadAllGeneration
            self.loadAllTask = Task { [weak self] in
                await self?.loadAllRemaining(generation: generation)
            }
        }
    }

    /// Loads every remaining liked-songs page by repeatedly calling `loadMore`.
    func loadAllRemaining(generation: Int? = nil) async {
        guard self.hasMore else { return }
        self.isLoadingAll = true
        defer {
            // Only the current generation's task may clear shared state, so a
            // cancelled older drain can't clobber a newer respawned one.
            if generation == nil || generation == self.loadAllGeneration {
                self.isLoadingAll = false
                self.loadAllTask = nil
            }
        }
        while self.hasMore, !Task.isCancelled {
            await self.loadMore()
        }
    }

    /// Loads liked songs.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        Self.logger.info("Loading liked songs")

        do {
            let response = try await client.getLikedSongs()
            // Deduplicate by videoId and mark all songs as liked
            var seenVideoIds = Set<String>()
            self.songs = response.songs.compactMap { song in
                guard seenVideoIds.insert(song.videoId).inserted else { return nil }
                var mutableSong = song
                mutableSong.likeStatus = .like
                return mutableSong
            }
            self.continuationToken = response.continuationToken
            self.hasMore = response.hasMore
            self.consecutiveEmptyPages = 0
            // Also populate the like status manager cache
            for song in self.songs {
                SongLikeStatusManager.shared.setStatus(.like, for: song.videoId)
            }
            self.loadingState = .loaded
            Self.logger.info("Loaded \(response.songs.count) liked songs, hasMore: \(self.hasMore)")
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            Self.logger.debug("Liked songs load cancelled")
            self.loadingState = .idle
        } catch {
            Self.logger.error("Failed to load liked songs: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Loads more liked songs via continuation.
    func loadMore() async {
        guard self.loadingState == .loaded,
              self.hasMore,
              let token = continuationToken else { return }

        self.loadingState = .loadingMore
        Self.logger.info("Loading more liked songs")

        do {
            guard let response = try await client.getLikedSongsContinuation(token: token) else {
                self.continuationToken = nil
                self.hasMore = false
                self.loadingState = .loaded
                return
            }

            // Build a set of existing video IDs for deduplication
            let existingVideoIds = Set(self.songs.map(\.videoId))

            // Filter out duplicates and mark all songs as liked
            let newSongs = response.songs
                .filter { !existingVideoIds.contains($0.videoId) }
                .map { song in
                    var mutableSong = song
                    mutableSong.likeStatus = .like
                    return mutableSong
                }

            // A page with no new unique songs does NOT necessarily mean the end of
            // the liked-music list: an all-duplicate or empty continuation page can
            // be followed by distinct songs further on. Keep paginating (advancing
            // the token) while the server still reports more pages, but cap the
            // number of consecutive all-duplicate/empty pages to avoid runaway loops.
            if newSongs.isEmpty {
                self.consecutiveEmptyPages += 1
                if let nextToken = response.continuationToken,
                   response.hasMore,
                   self.consecutiveEmptyPages < Self.maxConsecutiveEmptyPages
                {
                    self.continuationToken = nextToken
                    self.hasMore = true
                    self.loadingState = .loaded
                    Self.logger.info("Continuation page had only duplicates (\(self.consecutiveEmptyPages)/\(Self.maxConsecutiveEmptyPages)), advancing token")
                } else {
                    self.continuationToken = nil
                    self.hasMore = false
                    self.loadingState = .loaded
                    Self.logger.info("No new unique songs in continuation, stopping pagination")
                }
                return
            }

            // Found new unique songs — reset the all-duplicate page counter.
            self.consecutiveEmptyPages = 0

            self.songs.append(contentsOf: newSongs)
            self.continuationToken = response.continuationToken
            self.hasMore = response.hasMore

            // Populate the like status manager cache
            for song in newSongs {
                SongLikeStatusManager.shared.setStatus(.like, for: song.videoId)
            }

            self.loadingState = .loaded
            Self.logger.info("Loaded \(newSongs.count) new liked songs (from \(response.songs.count)), total: \(self.songs.count), hasMore: \(self.hasMore)")
        } catch is CancellationError {
            Self.logger.debug("Liked songs continuation cancelled")
            self.loadingState = .loaded
        } catch {
            Self.logger.error("Failed to load more liked songs: \(error.localizedDescription)")
            // Stop the scroll sentinel from re-firing the same failing continuation
            // request in a tight loop: clearing hasMore makes the per-row .task
            // guard (`index >= count - 3 && hasMore`) false. The token is preserved
            // so a future refresh can resume from where pagination stopped.
            self.hasMore = false
            self.loadingState = .loaded
        }
    }

    /// Refreshes liked songs.
    func refresh() async {
        self.cancelAllLiveSyncTasks()
        self.loadAllTask?.cancel()
        self.loadAllTask = nil
        self.isLoadingAll = false
        self.searchQuery = ""
        self.songs = []
        self.hasMore = false
        self.continuationToken = nil
        self.consecutiveEmptyPages = 0
        await self.load()
    }

    // MARK: - Real-time Like Status Sync

    /// Handles a like status change event to keep the song list in sync.
    /// - When a song is liked: adds it to the top of the list (if not already present).
    /// - When a song is unliked/disliked: removes it from the list.
    func handleLikeStatusChange(_ event: LikeStatusEvent) {
        guard self.loadingState == .loaded || self.loadingState == .loadingMore else { return }

        switch event.status {
        case .like:
            if let song = event.song, !Self.requiresMetadataFetchForLiveSync(song) {
                self.cancelLiveSyncTask(for: event.videoId)
                self.insertLiveSyncedSong(song)
            } else {
                guard !self.songs.contains(where: { $0.videoId == event.videoId }) else { return }
                self.startLiveSyncTask(for: event.videoId)
            }
        case .indifferent, .dislike:
            self.cancelLiveSyncTask(for: event.videoId)
            // Remove from list
            let countBefore = self.songs.count
            self.songs.removeAll { $0.videoId == event.videoId }
            if self.songs.count < countBefore {
                Self.logger.info("Live sync: removed song \(event.videoId) from liked music")
            }
        }
    }

    private func insertLiveSyncedSong(_ song: Song) {
        guard !self.songs.contains(where: { $0.videoId == song.videoId }) else { return }

        var likedSong = song
        likedSong.likeStatus = .like
        self.songs.insert(likedSong, at: 0)
        Self.logger.info("Live sync: added song \(song.videoId) to liked music")
    }

    private func startLiveSyncTask(for videoId: String) {
        let taskID = UUID()
        self.cancelLiveSyncTask(for: videoId)

        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchAndInsertLiveSyncedSong(videoId: videoId, taskID: taskID)
        }
        self.liveSyncTasks[videoId] = LiveSyncTask(id: taskID, task: task)
    }

    private func cancelLiveSyncTask(for videoId: String) {
        self.liveSyncTasks.removeValue(forKey: videoId)?.task.cancel()
    }

    private func cancelAllLiveSyncTasks() {
        let tasks = self.liveSyncTasks.values.map(\.task)
        self.liveSyncTasks.removeAll()
        tasks.forEach { $0.cancel() }
    }

    private func fetchAndInsertLiveSyncedSong(videoId: String, taskID: UUID) async {
        defer {
            if self.liveSyncTasks[videoId]?.id == taskID {
                self.liveSyncTasks.removeValue(forKey: videoId)
            }
        }

        guard self.liveSyncTasks[videoId]?.id == taskID else { return }
        guard !Task.isCancelled else { return }
        guard !self.songs.contains(where: { $0.videoId == videoId }) else { return }

        do {
            let song = try await self.client.getSong(videoId: videoId)

            guard !Task.isCancelled else { return }
            guard self.liveSyncTasks[videoId]?.id == taskID else { return }
            guard !Self.requiresMetadataFetchForLiveSync(song) else {
                Self.logger.warning("Live sync: skipping incomplete metadata for liked song \(videoId)")
                return
            }

            self.insertLiveSyncedSong(song)
        } catch is CancellationError {
            return
        } catch {
            Self.logger.warning("Live sync: failed to fetch metadata for liked song \(videoId): \(error.localizedDescription)")
        }
    }

    private static func requiresMetadataFetchForLiveSync(_ song: Song) -> Bool {
        song.title.isEmpty ||
            song.title == "Loading..." ||
            song.artists.isEmpty ||
            song.artists.allSatisfy { $0.name.isEmpty || $0.name == "Unknown Artist" }
    }
}
