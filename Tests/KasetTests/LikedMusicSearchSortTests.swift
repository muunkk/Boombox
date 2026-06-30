import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct LikedMusicSearchSortTests {
    private func makeViewModel(songs: [Song], pages: [[Song]] = []) async -> LikedMusicViewModel {
        let client = MockYTMusicClient()
        client.likedSongs = songs
        client.likedSongsContinuationSongs = pages
        let viewModel = LikedMusicViewModel(client: client)
        await viewModel.load()
        return viewModel
    }

    @Test("Empty query returns all songs in source order")
    func emptyQueryReturnsSourceOrder() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Banana"),
            TestFixtures.makeSong(id: "s2", title: "Apple"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        #expect(viewModel.displaySongs.map(\.id) == ["s1", "s2"])
    }

    @Test("Search filters by title and artist case-insensitively")
    func searchFilters() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Hello World", artistName: "Adele"),
            TestFixtures.makeSong(id: "s2", title: "Other", artistName: "ADELE"),
            TestFixtures.makeSong(id: "s3", title: "Nope", artistName: "Someone"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.setSearchQuery("adele")
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s1", "s2"])

        viewModel.setSearchQuery("hello")
        #expect(viewModel.displaySongs.map(\.id) == ["s1"])
    }

    @Test("Sort by title orders alphabetically")
    func sortByTitle() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Banana"),
            TestFixtures.makeSong(id: "s2", title: "apple"),
            TestFixtures.makeSong(id: "s3", title: "Cherry"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.sortOrder = .title
        #expect(viewModel.displaySongs.map(\.id) == ["s2", "s1", "s3"])
    }

    @Test("Sort by duration orders ascending")
    func sortByDuration() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "A", duration: 300),
            TestFixtures.makeSong(id: "s2", title: "B", duration: 120),
            TestFixtures.makeSong(id: "s3", title: "C", duration: 200),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.sortOrder = .duration
        #expect(viewModel.displaySongs.map(\.id) == ["s2", "s3", "s1"])
    }

    @Test("loadAllRemaining drains all continuation pages")
    func loadAllDrainsPages() async {
        let page0 = [TestFixtures.makeSong(id: "s0", title: "Zero")]
        let page1 = [TestFixtures.makeSong(id: "s1", title: "One")]
        let page2 = [TestFixtures.makeSong(id: "s2", title: "Two")]
        let viewModel = await self.makeViewModel(songs: page0, pages: [page1, page2])
        #expect(viewModel.hasMore == true)

        await viewModel.loadAllRemaining()

        #expect(viewModel.hasMore == false)
        #expect(viewModel.isLoadingAll == false)
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s0", "s1", "s2"])
    }

    @Test("Sort by artist orders alphabetically")
    func sortByArtist() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Track A", artistName: "Zebra"),
            TestFixtures.makeSong(id: "s2", title: "Track B", artistName: "apple"),
            TestFixtures.makeSong(id: "s3", title: "Track C", artistName: "Mango"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.sortOrder = .artist
        #expect(viewModel.displaySongs.map(\.id) == ["s2", "s3", "s1"])
    }

    @Test("setSearchQuery drives a complete background drain")
    func setSearchQueryDrivesCompleteDrain() async {
        let page0 = [TestFixtures.makeSong(id: "s0", title: "Song Zero")]
        let page1 = [TestFixtures.makeSong(id: "s1", title: "Song One")]
        let page2 = [TestFixtures.makeSong(id: "s2", title: "Song Two")]
        let viewModel = await self.makeViewModel(songs: page0, pages: [page1, page2])
        #expect(viewModel.hasMore == true)

        viewModel.setSearchQuery("song")

        // `setSearchQuery` spawns the drain Task synchronously; yield once first so
        // it gets scheduled and flips `isLoadingAll` before the poll loop checks it,
        // otherwise the loop can observe `isLoadingAll == false` before the drain
        // has even started.
        var guardCount = 0
        await Task.yield()
        while viewModel.isLoadingAll, guardCount < 1000 {
            await Task.yield()
            guardCount += 1
        }

        #expect(viewModel.hasMore == false)
        #expect(viewModel.isLoadingAll == false)
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s0", "s1", "s2"])
    }

    @Test("loadAllRemaining terminates across all-duplicate pages without breaking early")
    func loadAllRemainingHandlesDuplicatePages() async {
        // page1 repeats page0's song (all-duplicate: no new songs, but the
        // continuation token still advances). The drain's no-progress guard must
        // NOT break here — token advancement is real progress — and must still
        // terminate once a genuinely empty continuation is reached.
        let s0 = TestFixtures.makeSong(id: "s0", title: "Zero")
        let s2 = TestFixtures.makeSong(id: "s2", title: "Two")
        let viewModel = await self.makeViewModel(songs: [s0], pages: [[s0], [s2]])
        #expect(viewModel.hasMore == true)

        await viewModel.loadAllRemaining()

        #expect(viewModel.hasMore == false)
        #expect(viewModel.isLoadingAll == false)
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s0", "s2"])
    }
}
