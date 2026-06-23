import Foundation
import Testing
@testable import Kaset

/// PASS-2 regression coverage for the liked-songs pagination refactor.
///
/// - P2F042: `getLikedSongsContinuation(token:)` is per-request — the view model
///   owns the continuation cursor and feeds the token returned by the previous
///   page back in, instead of relying on shared client state.
/// - P2F047: an all-duplicate (or empty) continuation page no longer permanently
///   stops pagination. The view model keeps `hasMore` true and stays `.loaded`
///   for a bounded number of consecutive all-duplicate pages before giving up.
@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct Pass2LikedPaginationTests {
    var mockClient: MockYTMusicClient
    var viewModel: LikedMusicViewModel

    init() {
        self.mockClient = MockYTMusicClient()
        self.viewModel = LikedMusicViewModel(client: self.mockClient)
        // NOTE: deliberately does NOT touch SongLikeStatusManager.shared — these
        // tests only assert the view model's own paging state (songs/hasMore/
        // callCount), and mutating the shared singleton here races with the
        // serialized SongLikeStatusManagerTests suite running in parallel.
    }

    // MARK: - P2F042: per-request continuation token

    @Test("Continuation walks multiple pages using per-request tokens")
    func continuationWalksMultiplePagesViaPerRequestTokens() async {
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 2)
        self.mockClient.likedSongsContinuationSongs = [
            [TestFixtures.makeSong(id: "page1-a"), TestFixtures.makeSong(id: "page1-b")],
            [TestFixtures.makeSong(id: "page2-a"), TestFixtures.makeSong(id: "page2-b")],
        ]

        await self.viewModel.load()
        #expect(self.viewModel.songs.count == 2)
        #expect(self.viewModel.hasMore == true)

        // First continuation page.
        await self.viewModel.loadMore()
        #expect(self.viewModel.songs.count == 4)
        #expect(self.viewModel.hasMore == true)

        // Second continuation page — only reachable if the token from page 1's
        // response was carried forward (no shared client cursor).
        await self.viewModel.loadMore()
        #expect(self.viewModel.songs.count == 6)
        #expect(self.viewModel.hasMore == false)

        // Exactly one continuation call per page.
        #expect(self.mockClient.getLikedSongsContinuationCallCount == 2)
    }

    @Test("Continuation stops cleanly when the final page reports no more")
    func continuationStopsWhenServerReportsNoMore() async {
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 1)
        self.mockClient.likedSongsContinuationSongs = [
            [TestFixtures.makeSong(id: "tail-a")],
        ]

        await self.viewModel.load()
        await self.viewModel.loadMore()

        #expect(self.viewModel.songs.count == 2)
        #expect(self.viewModel.hasMore == false)
        #expect(self.viewModel.loadingState == .loaded)

        // No token left, so further loadMore is a no-op.
        await self.viewModel.loadMore()
        #expect(self.mockClient.getLikedSongsContinuationCallCount == 1)
    }

    // MARK: - P2F047: bounded all-duplicate pages

    @Test("All-duplicate page keeps paginating when more pages remain")
    func allDuplicatePageKeepsPaginatingWhenMorePagesRemain() async {
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 2)
        self.mockClient.likedSongsContinuationSongs = [
            // Page 0: entirely duplicates of the initial load.
            [TestFixtures.makeSong(id: "video-0"), TestFixtures.makeSong(id: "video-1")],
            // Page 1: a genuinely new song still waiting further on.
            [TestFixtures.makeSong(id: "deep-new")],
        ]

        await self.viewModel.load()
        #expect(self.viewModel.songs.count == 2)
        #expect(self.viewModel.hasMore == true)

        // All-duplicate page must NOT permanently stop pagination.
        await self.viewModel.loadMore()
        #expect(self.viewModel.songs.count == 2)
        #expect(self.viewModel.hasMore == true)
        #expect(self.viewModel.loadingState == .loaded)

        // Next page surfaces the new song.
        await self.viewModel.loadMore()
        #expect(self.viewModel.songs.count == 3)
        #expect(self.viewModel.songs.contains { $0.videoId == "deep-new" })
    }

    @Test("Pagination gives up after the bounded number of all-duplicate pages")
    func paginationGivesUpAfterBoundedDuplicatePages() async {
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 1)
        // More all-duplicate pages than the tolerance, each still reporting more.
        self.mockClient.likedSongsContinuationSongs = Array(
            repeating: [TestFixtures.makeSong(id: "video-0")],
            count: 6
        )

        await self.viewModel.load()
        #expect(self.viewModel.hasMore == true)

        // Drive loadMore repeatedly; the bound (3) caps the consecutive
        // all-duplicate pages even though the server keeps reporting more.
        for _ in 0 ..< 6 {
            await self.viewModel.loadMore()
        }

        #expect(self.viewModel.songs.count == 1)
        #expect(self.viewModel.hasMore == false)
        #expect(self.viewModel.loadingState == .loaded)
        // Bounded at 3 consecutive all-duplicate pages.
        #expect(self.mockClient.getLikedSongsContinuationCallCount == 3)
    }

    @Test("Refresh resets the duplicate-page counter")
    func refreshResetsDuplicatePageCounter() async {
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 1)
        self.mockClient.likedSongsContinuationSongs = [
            [TestFixtures.makeSong(id: "video-0")],
            [TestFixtures.makeSong(id: "video-0")],
        ]

        await self.viewModel.load()
        // Consume both all-duplicate pages (bound is 3, so it stops on its own
        // when the server reports no more).
        await self.viewModel.loadMore()
        await self.viewModel.loadMore()
        #expect(self.viewModel.hasMore == false)

        // Refresh should clear the counter and reload from scratch.
        self.mockClient.likedSongs = TestFixtures.makeSongs(count: 3)
        self.mockClient.likedSongsContinuationSongs = [
            [TestFixtures.makeSong(id: "fresh-1")],
        ]
        await self.viewModel.refresh()

        #expect(self.viewModel.songs.count == 3)
        #expect(self.viewModel.hasMore == true)

        await self.viewModel.loadMore()
        #expect(self.viewModel.songs.count == 4)
        #expect(self.viewModel.songs.contains { $0.videoId == "fresh-1" })
    }
}
