import Foundation
import Testing
@testable import Kaset

/// Pass-2 data-layer fix coverage: continuation-format parsing, search section
/// id de-duplication, ArtistDetail album-pagination preservation, and auth-error
/// re-auth signalling.
@Suite(.tags(.parser))
struct Pass2DataTests {
    // MARK: - DATA2-006: SearchSection id collision

    @Test("Duplicate shelf titles produce distinct SearchSection ids")
    func duplicateShelfTitlesAreDisambiguated() {
        // Two separate musicShelfRenderers both titled "Songs", each wrapped in
        // its own itemSectionRenderer (the shape YT "All" responses can return).
        let data = Self.makeSearchResponse(shelfTitles: ["Songs", "Albums", "Songs"])
        let response = SearchResponseParser.parse(data)

        let ids = response.sections.map(\.id)
        // All ids must be unique so SwiftUI identity does not collapse a shelf.
        #expect(Set(ids).count == ids.count)
        // The first occurrence keeps the bare title for cross-requery stability.
        #expect(ids.contains("Songs"))
        #expect(ids.contains("Albums"))
        // The duplicate is suffixed rather than dropped.
        #expect(ids.contains("Songs#1"))
    }

    @Test("Single-occurrence shelf titles keep bare-title ids (stability)")
    func uniqueShelfTitlesKeepBareIds() {
        let data = Self.makeSearchResponse(shelfTitles: ["Songs", "Albums", "Artists"])
        let response = SearchResponseParser.parse(data)
        let ids = response.sections.map(\.id)
        #expect(ids == ["Songs", "Albums", "Artists"])
    }

    // MARK: - DATA2-003: filtered-search 2025 continuation

    @Test("Filtered songs continuation token reads 2025 continuationItemRenderer")
    func filteredSearchTokenFrom2025Format() {
        let data = Self.makeFilteredSongsResponse2025(token: "TOKEN_2025")
        let (songs, token) = SearchResponseParser.parseSongsWithContinuation(data)
        #expect(songs.count == 1)
        #expect(token == "TOKEN_2025")
    }

    @Test("Search continuation parses 2025 onResponseReceivedActions shape")
    func searchContinuation2025Format() {
        let data = Self.makeSearchContinuation2025(token: "NEXT_TOKEN")
        let response = SearchResponseParser.parseContinuation(data)
        #expect(response.songs.count == 1)
        #expect(response.continuationToken == "NEXT_TOKEN")
    }

    @Test("Search continuation still parses legacy musicShelfContinuation")
    func searchContinuationLegacyFormat() {
        let data: [String: Any] = [
            "continuationContents": [
                "musicShelfContinuation": [
                    "contents": [Self.songItem(videoId: "legacy1", title: "Legacy")],
                    "continuations": [["nextContinuationData": ["continuation": "LEGACY_TOKEN"]]],
                ],
            ],
        ]
        let response = SearchResponseParser.parseContinuation(data)
        #expect(response.songs.count == 1)
        #expect(response.continuationToken == "LEGACY_TOKEN")
    }

    // MARK: - DATA2-004: home/explore 2025 continuation

    @Test("Home continuation parses 2025 onResponseReceivedActions shape")
    func homeContinuation2025Format() {
        let data = Self.makeHomeContinuation2025()
        let sections = HomeResponseParser.parseContinuation(data)
        #expect(sections.count == 1)
        #expect(sections.first?.title == "More Songs")
    }

    @Test("Home continuation token reads 2025 continuationItemRenderer")
    func homeContinuationToken2025Format() {
        let data = Self.makeHomeContinuation2025(token: "HOME_NEXT")
        let token = HomeResponseParser.extractContinuationTokenFromContinuation(data)
        #expect(token == "HOME_NEXT")
    }

    @Test("Home continuation token still reads legacy nextContinuationData")
    func homeContinuationTokenLegacyFormat() {
        let data: [String: Any] = [
            "continuationContents": [
                "sectionListContinuation": [
                    "continuations": [["nextContinuationData": ["continuation": "HOME_LEGACY"]]],
                ],
            ],
        ]
        let token = HomeResponseParser.extractContinuationTokenFromContinuation(data)
        #expect(token == "HOME_LEGACY")
    }

    // MARK: - DATA2-001: ArtistDetail preserves album-pagination fields

    @Test("ArtistDetail initializer preserves album-pagination fields")
    func artistDetailPreservesAlbumPagination() {
        let artist = Artist(id: "UC123", name: "Test Artist")
        let detail = ArtistDetail(
            artist: artist,
            description: nil,
            songs: [],
            albums: [],
            thumbnailURL: nil,
            hasMoreAlbums: true,
            albumsBrowseId: "ALBUMS_BROWSE",
            albumsParams: "ALBUMS_PARAMS"
        )
        // Re-init mirroring the duration-enrichment rebuild in getArtist(id:).
        let rebuilt = ArtistDetail(
            artist: detail.artist,
            description: detail.description,
            songs: detail.songs,
            albums: detail.albums,
            thumbnailURL: detail.thumbnailURL,
            channelId: detail.channelId,
            isSubscribed: detail.isSubscribed,
            subscriberCount: detail.subscriberCount,
            hasMoreSongs: detail.hasMoreSongs,
            songsBrowseId: detail.songsBrowseId,
            songsParams: detail.songsParams,
            hasMoreAlbums: detail.hasMoreAlbums,
            albumsBrowseId: detail.albumsBrowseId,
            albumsParams: detail.albumsParams,
            mixPlaylistId: detail.mixPlaylistId,
            mixVideoId: detail.mixVideoId
        )
        #expect(rebuilt.hasMoreAlbums)
        #expect(rebuilt.albumsBrowseId == "ALBUMS_BROWSE")
        #expect(rebuilt.albumsParams == "ALBUMS_PARAMS")
    }

    // MARK: - ERR-07: auth errors require re-auth and are not retryable

    @Test("Auth errors require reauth and are not retryable")
    func authErrorsRequireReauth() {
        #expect(YTMusicError.notAuthenticated.requiresReauth)
        #expect(YTMusicError.authExpired.requiresReauth)
        #expect(!YTMusicError.notAuthenticated.isRetryable)
        #expect(!YTMusicError.authExpired.isRetryable)
    }

    // MARK: - Fixtures

    private static func songItem(videoId: String, title: String) -> [String: Any] {
        [
            "musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": videoId],
                "flexColumns": [
                    [
                        "musicResponsiveListItemFlexColumnRenderer": [
                            "text": ["runs": [["text": title]]],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func continuationItemRenderer(token: String) -> [String: Any] {
        [
            "continuationItemRenderer": [
                "continuationEndpoint": [
                    "continuationCommand": ["token": token],
                ],
            ],
        ]
    }

    /// Builds an "All"-style tabbed search response with one musicShelfRenderer per title.
    private static func makeSearchResponse(shelfTitles: [String]) -> [String: Any] {
        let sectionContents: [[String: Any]] = shelfTitles.enumerated().map { index, title in
            [
                "itemSectionRenderer": [
                    "contents": [
                        [
                            "musicShelfRenderer": [
                                "title": ["runs": [["text": title]]],
                                "contents": [Self.songItem(videoId: "v\(index)", title: "\(title) item")],
                            ],
                        ],
                    ],
                ],
            ]
        }
        return [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [
                        [
                            "tabRenderer": [
                                "content": [
                                    "sectionListRenderer": ["contents": sectionContents],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    /// Filtered (non-tabbed) songs response whose token lives in a trailing
    /// continuationItemRenderer (2025 format), not a continuations array.
    private static func makeFilteredSongsResponse2025(token: String) -> [String: Any] {
        [
            "contents": [
                "sectionListRenderer": [
                    "contents": [
                        [
                            "musicShelfRenderer": [
                                "contents": [self.songItem(videoId: "s1", title: "Song One")],
                            ],
                        ],
                        self.continuationItemRenderer(token: token),
                    ],
                ],
            ],
        ]
    }

    private static func makeSearchContinuation2025(token: String) -> [String: Any] {
        [
            "onResponseReceivedActions": [
                [
                    "appendContinuationItemsAction": [
                        "continuationItems": [
                            self.songItem(videoId: "c1", title: "Continued Song"),
                            self.continuationItemRenderer(token: token),
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func makeHomeContinuation2025(token: String = "HOME_TOKEN") -> [String: Any] {
        let shelf: [String: Any] = [
            "musicShelfRenderer": [
                "title": ["runs": [["text": "More Songs"]]],
                "contents": [Self.songItem(videoId: "h1", title: "Home Song")],
            ],
        ]
        return [
            "onResponseReceivedActions": [
                [
                    "appendContinuationItemsAction": [
                        "continuationItems": [
                            shelf,
                            Self.continuationItemRenderer(token: token),
                        ],
                    ],
                ],
            ],
        ]
    }
}
