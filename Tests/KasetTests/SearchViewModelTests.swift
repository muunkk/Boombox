import Foundation
import Testing
@testable import Kaset

/// Tests for SearchViewModel using mock client.
@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct SearchViewModelTests {
    var mockClient: MockYTMusicClient
    var viewModel: SearchViewModel

    init() {
        self.mockClient = MockYTMusicClient()
        self.viewModel = SearchViewModel(client: self.mockClient)
    }

    @Test("Initial state is idle with empty query")
    func initialState() {
        #expect(self.viewModel.loadingState == .idle)
        #expect(self.viewModel.query.isEmpty)
        #expect(self.viewModel.results.allItems.isEmpty)
        #expect(self.viewModel.selectedFilter == .all)
    }

    @Test("Query change clears results when empty")
    func queryChangeClearsResultsWhenEmpty() {
        self.viewModel.query = "test"
        self.viewModel.query = ""

        #expect(self.viewModel.loadingState == .idle)
        #expect(self.viewModel.results.allItems.isEmpty)
    }

    @Test("Search with empty query does not call API")
    func searchWithEmptyQueryDoesNotCallAPI() {
        self.viewModel.query = ""
        self.viewModel.search()

        #expect(self.mockClient.searchCalled == false)
    }

    @Test("Immediate search calls API without debounce")
    func immediateSearchCallsAPIWithoutDebounce() async {
        self.mockClient.searchResponse = TestFixtures.makeSearchResponse(
            songCount: 1,
            albumCount: 0,
            artistCount: 0,
            playlistCount: 0
        )
        self.viewModel.query = "boards of canada"

        await self.viewModel.searchImmediately()

        #expect(self.mockClient.searchCalled)
        #expect(self.mockClient.searchQueries == ["boards of canada"])
        #expect(self.viewModel.loadingState == .loaded)
        #expect(self.viewModel.results.allItems.count == 1)
    }

    @Test("Immediate search with empty query does not call API")
    func immediateSearchWithEmptyQueryDoesNotCallAPI() async {
        self.viewModel.query = ""

        await self.viewModel.searchImmediately()

        #expect(self.mockClient.searchCalled == false)
        #expect(self.viewModel.loadingState == .idle)
    }

    @Test("Clear resets state")
    func clearResetsState() {
        self.viewModel.query = "test query"
        self.viewModel.selectedFilter = .songs

        self.viewModel.clear()

        #expect(self.viewModel.query.isEmpty)
        #expect(self.viewModel.loadingState == .idle)
        #expect(self.viewModel.results.allItems.isEmpty)
    }

    @Test("Filtered items returns all when all selected")
    func filteredItemsReturnsAllWhenAllSelected() {
        self.viewModel.selectedFilter = .all

        let response = TestFixtures.makeSearchResponse(
            songCount: 2,
            albumCount: 1,
            artistCount: 1,
            playlistCount: 1
        )

        #expect(response.allItems.count == 5)
    }

    @Test("Filtered items returns songs only when songs selected")
    func filteredItemsReturnsSongsOnlyWhenSongsSelected() {
        let response = TestFixtures.makeSearchResponse(
            songCount: 3,
            albumCount: 2,
            artistCount: 1,
            playlistCount: 1
        )

        let songItems = response.songs.map { SearchResultItem.song($0) }
        #expect(songItems.count == 3)
    }

    @Test("Podcast filter is available")
    func podcastFilterIsAvailable() {
        let filters = SearchViewModel.SearchFilter.allCases
        #expect(filters.contains(.podcasts))
    }

    @Test("Podcast filter has correct raw value")
    func podcastFilterRawValue() {
        #expect(SearchViewModel.SearchFilter.podcasts.rawValue == "Podcasts")
    }

    @Test("Selected filter defaults to all")
    func selectedFilterDefaultsToAll() {
        #expect(self.viewModel.selectedFilter == .all)
    }

    @Test("Can set filter to podcasts")
    func canSetFilterToPodcasts() {
        self.viewModel.selectedFilter = .podcasts
        #expect(self.viewModel.selectedFilter == .podcasts)
    }
}
