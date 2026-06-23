import Foundation
import Testing
@testable import Kaset

/// Pass 2 regression tests for view-model bug fixes (batch: viewmodels).
///
/// Covers:
/// - P2F012: TopSongsViewModel surfaces `.error` when a fetch fails and there is
///   nothing to show, while soft-degrading to a seed preview when one exists.
/// - P2F007: ArtistDetailViewModel.clearSubscriptionError() resets the error so
///   the view's alert binding can dismiss it.
/// - P2F047: PlaylistDetailViewModel keeps paginating past an all-duplicate
///   continuation page (legitimate intra-playlist duplicates) instead of
///   terminating early, while still bounding runaway pagination.
/// - P2F050: SearchViewModel debounced suggestion/search tasks keep working after
///   the `[weak self]` change.
@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct Pass2ViewModelsTests {
    // MARK: - P2F012: TopSongsViewModel error surfacing

    @Test("TopSongs: empty seed + fetch error surfaces a retryable error state")
    func topSongsEmptySeedErrorSurfacesError() async {
        let mockClient = MockYTMusicClient()
        let destination = TopSongsDestination(
            artistId: "artist-1",
            artistName: "Test Artist",
            songs: [], // No seed preview to fall back to
            songsBrowseId: "browse-id-123",
            songsParams: nil
        )
        let viewModel = TopSongsViewModel(destination: destination, client: mockClient)

        mockClient.shouldThrowError = YTMusicError.networkError(
            underlying: URLError(.notConnectedToInternet)
        )

        await viewModel.load()

        if case let .error(error) = viewModel.loadingState {
            #expect(!error.message.isEmpty)
            #expect(error.isRetryable)
        } else {
            Issue.record("Expected error state when seed is empty and fetch fails")
        }
        #expect(viewModel.songs.isEmpty)
    }

    @Test("TopSongs: non-empty seed + fetch error soft-degrades to loaded")
    func topSongsNonEmptySeedErrorStaysLoaded() async {
        let mockClient = MockYTMusicClient()
        let seed = [
            TestFixtures.makeSong(id: "seed-1", title: "Seed 1"),
            TestFixtures.makeSong(id: "seed-2", title: "Seed 2"),
        ]
        let destination = TopSongsDestination(
            artistId: "artist-1",
            artistName: "Test Artist",
            songs: seed,
            songsBrowseId: "browse-id-123",
            songsParams: nil
        )
        let viewModel = TopSongsViewModel(destination: destination, client: mockClient)

        mockClient.shouldThrowError = YTMusicError.networkError(
            underlying: URLError(.notConnectedToInternet)
        )

        await viewModel.load()

        #expect(viewModel.loadingState == .loaded)
        #expect(viewModel.songs.count == 2)
    }

    // MARK: - P2F007: ArtistDetailViewModel.clearSubscriptionError

    @Test("Artist: clearSubscriptionError resets the error message")
    func artistClearSubscriptionError() async {
        let mockClient = MockYTMusicClient()
        let libraryViewModel = LibraryViewModel(client: mockClient)
        let artist = TestFixtures.makeArtist(id: "UC-test-artist", name: "Test Artist")
        let viewModel = ArtistDetailViewModel(
            artist: artist,
            client: mockClient,
            libraryViewModel: libraryViewModel
        )

        let artistDetail = ArtistDetail(
            artist: artist,
            description: nil,
            songs: [],
            albums: [],
            thumbnailURL: nil,
            channelId: "UC-channel-123",
            isSubscribed: false
        )
        mockClient.artistDetails["UC-test-artist"] = artistDetail

        await viewModel.load()
        mockClient.shouldThrowError = YTMusicError.networkError(
            underlying: URLError(.notConnectedToInternet)
        )
        await viewModel.toggleSubscription()
        #expect(viewModel.subscriptionError != nil)

        viewModel.clearSubscriptionError()
        #expect(viewModel.subscriptionError == nil)
    }

    // MARK: - P2F047: PlaylistDetailViewModel pagination past all-duplicate page

    @Test("Playlist: all-duplicate page does not terminate pagination when more pages remain")
    func playlistContinuesPastAllDuplicatePage() async {
        let mockClient = MockYTMusicClient()
        let playlist = TestFixtures.makePlaylist(id: "VL-dup-playlist", title: "Dup Playlist")
        let viewModel = PlaylistDetailViewModel(playlist: playlist, client: mockClient)

        // Base detail has video-0 and video-1.
        let detail = TestFixtures.makePlaylistDetail(
            playlist: playlist,
            trackCount: 2
        )
        mockClient.playlistDetails["VL-dup-playlist"] = detail

        // Page 0: only already-seen tracks (legitimate intra-playlist duplicates).
        // Page 1: genuinely new unique tracks.
        mockClient.playlistContinuationTracks["VL-dup-playlist"] = [
            [
                TestFixtures.makeSong(id: "video-0"),
                TestFixtures.makeSong(id: "video-1"),
            ],
            [
                TestFixtures.makeSong(id: "new-track-a"),
                TestFixtures.makeSong(id: "new-track-b"),
            ],
        ]

        await viewModel.load()
        #expect(viewModel.playlistDetail?.tracks.count == 2)
        #expect(viewModel.hasMore == true)

        // First loadMore processes the all-duplicate page. Old behavior would stop
        // pagination here; the fix keeps hasMore true so the next page can load.
        await viewModel.loadMore()
        #expect(viewModel.playlistDetail?.tracks.count == 2) // No new tracks appended yet
        #expect(viewModel.hasMore == true)

        // Second loadMore fetches the page with new unique tracks.
        await viewModel.loadMore()
        #expect(viewModel.playlistDetail?.tracks.count == 4)
        #expect(viewModel.playlistDetail?.tracks.contains { $0.videoId == "new-track-a" } == true)
        #expect(viewModel.hasMore == false)
    }

    @Test("Playlist: consecutive all-duplicate pages are bounded to avoid runaway pagination")
    func playlistBoundsConsecutiveDuplicatePages() async {
        let mockClient = MockYTMusicClient()
        let playlist = TestFixtures.makePlaylist(id: "VL-radio-playlist", title: "Radio Playlist")
        let viewModel = PlaylistDetailViewModel(playlist: playlist, client: mockClient)

        let detail = TestFixtures.makePlaylistDetail(
            playlist: playlist,
            trackCount: 1 // only video-0
        )
        mockClient.playlistDetails["VL-radio-playlist"] = detail

        // Five consecutive all-duplicate pages (overlapping radio feed). The cap is
        // 3 consecutive empty pages, after which pagination must stop.
        let duplicatePage = [TestFixtures.makeSong(id: "video-0")]
        mockClient.playlistContinuationTracks["VL-radio-playlist"] = Array(
            repeating: duplicatePage,
            count: 5
        )

        await viewModel.load()
        #expect(viewModel.hasMore == true)

        var continuationCalls = 0
        // Drive loadMore until pagination stops, with a hard safety cap so a
        // regression (infinite loop) fails the test instead of hanging.
        while viewModel.hasMore, continuationCalls < 10 {
            await viewModel.loadMore()
            continuationCalls += 1
        }

        #expect(viewModel.hasMore == false)
        // Should give up after the bounded number of consecutive empty pages, not
        // walk all 5 overlapping pages.
        #expect(continuationCalls <= 3)
        #expect(viewModel.playlistDetail?.tracks.count == 1)
    }

    // MARK: - P2F050: SearchViewModel debounced tasks still work after [weak self]

    @Test("Search: debounced search still produces results after weak-self change")
    func searchDebouncedStillProducesResults() async {
        let mockClient = MockYTMusicClient()
        mockClient.searchResponse = TestFixtures.makeSearchResponse(songCount: 3)
        let viewModel = SearchViewModel(client: mockClient)

        viewModel.query = "test query"
        viewModel.search()

        // Wait past the 300ms debounce for the search task to run.
        try? await Task.sleep(for: .milliseconds(600))

        #expect(mockClient.searchCalled)
        #expect(viewModel.loadingState == .loaded)
        #expect(!viewModel.results.allItems.isEmpty)
    }

    @Test("Search: debounced suggestions still fetched after weak-self change")
    func searchDebouncedSuggestionsStillFetched() async {
        let mockClient = MockYTMusicClient()
        mockClient.searchSuggestions = [
            SearchSuggestion(query: "test suggestion"),
        ]
        let viewModel = SearchViewModel(client: mockClient)

        viewModel.query = "tes"
        viewModel.fetchSuggestions()

        // Wait past the 150ms suggestion debounce.
        try? await Task.sleep(for: .milliseconds(400))

        #expect(mockClient.getSearchSuggestionsCalled)
        #expect(viewModel.suggestions.count == 1)
    }
}
