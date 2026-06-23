import Foundation
import Testing
@testable import Kaset

// MARK: - PlaylistContinuationScopingTests

/// Verifies playlist pagination state is scoped per request (per view model) so
/// two playlist detail views sharing one client cannot contaminate each other's pages.
@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct PlaylistContinuationScopingTests {
    @Test("Paginating one playlist after another fetches the correct continuation")
    func continuationIsScopedPerViewModel() async {
        let client = MockYTMusicClient()

        let playlistA = TestFixtures.makePlaylist(id: "VL-A", title: "Playlist A")
        let playlistB = TestFixtures.makePlaylist(id: "VL-B", title: "Playlist B")

        client.playlistDetails["VL-A"] = PlaylistDetail(
            playlist: playlistA,
            tracks: [TestFixtures.makeSong(id: "a-1"), TestFixtures.makeSong(id: "a-2")],
            duration: "5 min"
        )
        client.playlistContinuationTracks["VL-A"] = [
            [TestFixtures.makeSong(id: "a-cont-1"), TestFixtures.makeSong(id: "a-cont-2")],
        ]

        client.playlistDetails["VL-B"] = PlaylistDetail(
            playlist: playlistB,
            tracks: [TestFixtures.makeSong(id: "b-1")],
            duration: "3 min"
        )
        client.playlistContinuationTracks["VL-B"] = [
            [TestFixtures.makeSong(id: "b-cont-1")],
        ]

        let viewModelA = PlaylistDetailViewModel(playlist: playlistA, client: client)
        let viewModelB = PlaylistDetailViewModel(playlist: playlistB, client: client)

        // Load A, then load B (B's load previously overwrote the shared client cursor).
        await viewModelA.load()
        await viewModelB.load()

        // Paginate B first (simulates drilling into B and scrolling).
        await viewModelB.loadMore()
        let bIds = viewModelB.playlistDetail?.tracks.map(\.videoId) ?? []
        #expect(bIds.contains("b-cont-1"))

        // Returning to A and paginating must fetch A's continuation, never B's.
        await viewModelA.loadMore()
        let aIds = viewModelA.playlistDetail?.tracks.map(\.videoId) ?? []
        #expect(aIds.contains("a-cont-1"))
        #expect(aIds.contains("a-cont-2"))
        #expect(!aIds.contains("b-cont-1"))
    }
}

// MARK: - RetryPolicyCancellationTests

@Suite(.tags(.api), .timeLimit(.minutes(1)))
@MainActor
struct RetryPolicyCancellationTests {
    private func fastPolicy() -> RetryPolicy {
        RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.002)
    }

    @Test("CancellationError is not retried and surfaces as cancellation")
    func cancellationErrorNotRetried() async {
        let policy = self.fastPolicy()
        var attempts = 0
        do {
            _ = try await policy.execute { () async throws -> Int in
                attempts += 1
                throw CancellationError()
            }
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(attempts == 1)
    }

    @Test("Cancelled network error maps to CancellationError without retrying")
    func cancelledNetworkErrorMapsToCancellation() async {
        let policy = self.fastPolicy()
        var attempts = 0
        do {
            _ = try await policy.execute { () async throws -> Int in
                attempts += 1
                throw YTMusicError.networkError(underlying: URLError(.cancelled))
            }
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(attempts == 1)
    }

    @Test("Genuine network errors are still retried")
    func genuineNetworkErrorsAreRetried() async {
        let policy = self.fastPolicy()
        var attempts = 0
        do {
            _ = try await policy.execute { () async throws -> Int in
                attempts += 1
                throw YTMusicError.networkError(underlying: URLError(.timedOut))
            }
            Issue.record("Expected the operation to throw after exhausting retries")
        } catch {
            // Expected after all attempts fail.
        }
        #expect(attempts == 3)
    }
}

// MARK: - FavoritesDecodeTests

@Suite(.tags(.service))
@MainActor
struct FavoritesDecodeTests {
    /// Splices a corrupt element into an otherwise valid favorites payload.
    private func makeMixedPayload(validItems: [FavoriteItem]) throws -> Data {
        let validData = try JSONEncoder().encode(validItems)
        guard var array = try JSONSerialization.jsonObject(with: validData) as? [Any] else {
            throw YTMusicError.parseError(message: "Expected array")
        }
        array.append(["totally": "unexpected", "shape": 42])
        return try JSONSerialization.data(withJSONObject: array)
    }

    @Test("A single corrupt entry is skipped, valid favorites survive")
    func corruptEntryDoesNotWipeAll() throws {
        let song = TestFixtures.makeSong(id: "keep-song")
        let album = TestFixtures.makeAlbum(id: "MPRE-keep-album")
        let valid = [FavoriteItem.from(song), FavoriteItem.from(album)]

        let data = try self.makeMixedPayload(validItems: valid)
        let (items, skipped) = try FavoritesManager.decodeFavorites(from: data)

        #expect(items.count == 2)
        #expect(skipped == 1)
        #expect(items.contains { $0.contentId == "keep-song" })
        #expect(items.contains { $0.contentId == "MPRE-keep-album" })
    }

    @Test("A valid favorites file decodes fully with nothing skipped")
    func validFileDecodesFully() throws {
        let valid = [FavoriteItem.from(TestFixtures.makeSong(id: "s1"))]
        let data = try JSONEncoder().encode(valid)

        let (items, skipped) = try FavoritesManager.decodeFavorites(from: data)

        #expect(items.count == 1)
        #expect(skipped == 0)
    }

    @Test("Totally corrupt data throws rather than returning empty silently")
    func totallyCorruptDataThrows() {
        let garbage = Data("not even json".utf8)
        #expect(throws: (any Error).self) {
            _ = try FavoritesManager.decodeFavorites(from: garbage)
        }
    }
}

// MARK: - DataParserFixTests

@Suite(.tags(.parser))
struct DataParserFixTests {
    @Test("extractArtists drops content-type keywords and non-artist metadata")
    func extractArtistsFiltersNonArtists() {
        let data: [String: Any] = [
            "subtitle": ["runs": [
                ["text": "Song"],
                ["text": " • "],
                ["text": "Real Artist", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC_real"]]],
                ["text": " • "],
                ["text": "2024"],
                ["text": " • "],
                ["text": "1.2M views"],
            ]],
        ]

        let artists = ParsingHelpers.extractArtists(from: data)

        #expect(artists.count == 1)
        #expect(artists.first?.name == "Real Artist")
        #expect(artists.first?.id == "UC_real")
    }

    @Test("Combined ('All') search surfaces podcast shows")
    func combinedSearchIncludesPodcasts() {
        let json = Self.makeSearchResponseJSON(browseId: "MPSPPshow-123", title: "My Great Podcast")

        let response = SearchResponseParser.parse(json)

        #expect(response.podcastShows.count == 1)
        #expect(response.podcastShows.first?.id == "MPSPPshow-123")
        #expect(response.podcastShows.first?.title == "My Great Podcast")
    }

    /// Builds the minimal nested shape that `SearchResponseParser.parse` expects for
    /// a single browse-endpoint result item.
    private static func makeSearchResponseJSON(browseId: String, title: String) -> [String: Any] {
        let item: [String: Any] = [
            "musicResponsiveListItemRenderer": [
                "flexColumns": [[
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": title]]],
                    ],
                ]],
                "navigationEndpoint": ["browseEndpoint": ["browseId": browseId]],
            ],
        ]

        return [
            "contents": ["tabbedSearchResultsRenderer": ["tabs": [
                ["tabRenderer": ["content": ["sectionListRenderer": ["contents": [
                    ["musicShelfRenderer": ["contents": [item]]],
                ]]]]],
            ]]],
        ]
    }
}
