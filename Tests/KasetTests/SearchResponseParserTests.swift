import Foundation
import Testing
@testable import Kaset

/// Tests for the SearchResponseParser.
@Suite(.tags(.parser))
struct SearchResponseParserTests {
    @Test("Parse empty response returns empty results")
    func parseEmptyResponse() {
        let data: [String: Any] = [:]
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.isEmpty)
        #expect(response.albums.isEmpty)
        #expect(response.artists.isEmpty)
        #expect(response.playlists.isEmpty)
    }

    @Test("Parse response with only songs")
    func parseSongResults() {
        let data = self.makeSearchResponseData(songs: 3, albums: 0, artists: 0, playlists: 0)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.count == 3)
        #expect(response.albums.isEmpty)
        #expect(response.artists.isEmpty)
        #expect(response.playlists.isEmpty)
    }

    @Test("Parse response with only albums")
    func parseAlbumResults() {
        let data = self.makeSearchResponseData(songs: 0, albums: 2, artists: 0, playlists: 0)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.isEmpty)
        #expect(response.albums.count == 2)
    }

    @Test("Parse response with only artists")
    func parseArtistResults() {
        let data = self.makeSearchResponseData(songs: 0, albums: 0, artists: 2, playlists: 0)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.isEmpty)
        #expect(response.artists.count == 2)
    }

    @Test("Parse response with only playlists")
    func parsePlaylistResults() {
        let data = self.makeSearchResponseData(songs: 0, albums: 0, artists: 0, playlists: 2)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.isEmpty)
        #expect(response.playlists.count == 2)
    }

    @Test("Parse response with mixed results")
    func parseMixedResults() {
        let data = self.makeSearchResponseData(songs: 2, albums: 1, artists: 1, playlists: 1)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.count == 2)
        #expect(response.albums.count == 1)
        #expect(response.artists.count == 1)
        #expect(response.playlists.count == 1)
    }

    @Test("Song has correct video ID")
    func songHasVideoId() {
        let data = self.makeSearchResponseData(songs: 1, albums: 0, artists: 0, playlists: 0)
        let response = SearchResponseParser.parse(data)

        #expect(response.songs.first?.videoId == "video0")
    }

    @Test("Parse library artist result using library artist page type")
    func parseLibraryArtistResult() {
        let data: [String: Any] = [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [[
                                        "musicShelfRenderer": [
                                            "contents": [[
                                                "musicResponsiveListItemRenderer": [
                                                    "navigationEndpoint": [
                                                        "browseEndpoint": [
                                                            "browseId": "MPLAUC1234567890",
                                                            "browseEndpointContextSupportedConfigs": [
                                                                "browseEndpointContextMusicConfig": [
                                                                    "pageType": "MUSIC_PAGE_TYPE_LIBRARY_ARTIST",
                                                                ],
                                                            ],
                                                        ],
                                                    ],
                                                    "flexColumns": [
                                                        [
                                                            "musicResponsiveListItemFlexColumnRenderer": [
                                                                "text": ["runs": [["text": "Library Artist"]]],
                                                            ],
                                                        ],
                                                        [
                                                            "musicResponsiveListItemFlexColumnRenderer": [
                                                                "text": ["runs": [["text": "Artist"]]],
                                                            ],
                                                        ],
                                                    ],
                                                ],
                                            ]],
                                        ],
                                    ]],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]

        let response = SearchResponseParser.parse(data)

        #expect(response.artists.count == 1)
        #expect(response.artists.first?.id == "MPLAUC1234567890")
        #expect(response.artists.first?.name == "Library Artist")
        #expect(response.albums.isEmpty)
        #expect(response.playlists.isEmpty)
    }

    // MARK: - Section Ordering Tests

    @Test("parse preserves YT shelf order in `sections`")
    func parsePreservesShelfOrder() {
        let data: [String: Any] = [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        Self.makeShelf(title: "Songs", items: self.makeSongItems(count: 1)),
                                        Self.makeShelf(title: "Albums", items: self.makeAlbumItems(count: 1)),
                                        Self.makeShelf(title: "Community playlists", items: self.makePlaylistItems(count: 1)),
                                        Self.makeShelf(title: "Artists", items: self.makeArtistItems(count: 1)),
                                    ],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]

        let response = SearchResponseParser.parse(data)

        #expect(response.sections.map(\.title) == ["Songs", "Albums", "Community playlists", "Artists"])
    }

    @Test("parse unwraps itemSectionRenderer wrappers and preserves order")
    func parseUnwrapsItemSectionRenderer() {
        let data: [String: Any] = [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        [
                                            "itemSectionRenderer": [
                                                "contents": [
                                                    Self.makeShelf(title: "Songs", items: self.makeSongItems(count: 2)),
                                                ],
                                            ],
                                        ],
                                        Self.makeShelf(title: "Albums", items: self.makeAlbumItems(count: 1)),
                                    ],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]

        let response = SearchResponseParser.parse(data)

        #expect(response.sections.map(\.title) == ["Songs", "Albums"])
        #expect(response.songs.count == 2)
        #expect(response.albums.count == 1)
    }

    @Test("parse produces stable section ids across re-queries with reordered items")
    func parseProducesStableSectionIdsAcrossReQueries() {
        // Same shelves (Songs, Albums) — but a YouTube personalization pass
        // returns them with different first items. The section ids must not
        // depend on item identity, otherwise SwiftUI tears down and rebuilds
        // entire section subtrees on every re-search.
        let responseA = SearchResponseParser.parse(self.makeOrderedResponse(
            songItemIds: ["video-a", "video-b"],
            albumItemIds: ["MPRE-a", "MPRE-b"]
        ))
        let responseB = SearchResponseParser.parse(self.makeOrderedResponse(
            songItemIds: ["video-z", "video-y"],
            albumItemIds: ["MPRE-z", "MPRE-y"]
        ))

        #expect(responseA.sections.map(\.id) == responseB.sections.map(\.id))
        // Sanity: the items did actually change, so we know the ids aren't
        // stable by coincidence of identical content.
        #expect(responseA.songs.map(\.id) != responseB.songs.map(\.id))
    }

    @Test("parse falls back to shelf-index id for shelves with no title")
    func parseFallsBackToShelfIndexWhenShelfHasNoTitle() {
        let data: [String: Any] = [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        Self.makeShelf(title: nil, items: self.makeSongItems(count: 1)),
                                        Self.makeShelf(title: nil, items: self.makeAlbumItems(count: 1)),
                                    ],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]

        let response = SearchResponseParser.parse(data)

        // Two untitled shelves must still produce distinct, deterministic ids.
        #expect(response.sections.count == 2)
        let ids = Set(response.sections.map(\.id))
        #expect(ids.count == 2)
        #expect(response.sections.allSatisfy { $0.id.hasPrefix("shelf-") })
    }

    /// Builds a tabbed response with the conventional Songs → Albums shelf order.
    private func makeOrderedResponse(songItemIds: [String], albumItemIds: [String]) -> [String: Any] {
        [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        Self.makeShelf(title: "Songs", items: self.makeCustomSongItems(ids: songItemIds)),
                                        Self.makeShelf(title: "Albums", items: self.makeCustomAlbumItems(ids: albumItemIds)),
                                    ],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]
    }

    private func makeCustomSongItems(ids: [String]) -> [[String: Any]] {
        ids.map { videoId in
            [
                "musicResponsiveListItemRenderer": [
                    "playlistItemData": ["videoId": videoId],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": videoId]]]]],
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist"]]]]],
                    ],
                ],
            ]
        }
    }

    private func makeCustomAlbumItems(ids: [String]) -> [[String: Any]] {
        ids.map { browseId in
            [
                "musicResponsiveListItemRenderer": [
                    "navigationEndpoint": ["browseEndpoint": ["browseId": browseId]],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": browseId]]]]],
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist"]]]]],
                    ],
                ],
            ]
        }
    }

    private static func makeShelf(title: String?, items: [[String: Any]]) -> [String: Any] {
        var renderer: [String: Any] = ["contents": items]
        if let title {
            renderer["title"] = ["runs": [["text": title]]]
        }
        return ["musicShelfRenderer": renderer]
    }

    private static func makeShelf(title: String, items: [[String: Any]]) -> [String: Any] {
        [
            "musicShelfRenderer": [
                "title": ["runs": [["text": title]]],
                "contents": items,
            ],
        ]
    }

    // MARK: - Helpers

    private func makeSearchResponseData(songs: Int, albums: Int, artists: Int, playlists: Int) -> [String: Any] {
        var contents: [[String: Any]] = []

        if songs > 0 {
            contents.append(["musicShelfRenderer": ["contents": self.makeSongItems(count: songs)]])
        }
        if albums > 0 {
            contents.append(["musicShelfRenderer": ["contents": self.makeAlbumItems(count: albums)]])
        }
        if artists > 0 {
            contents.append(["musicShelfRenderer": ["contents": self.makeArtistItems(count: artists)]])
        }
        if playlists > 0 {
            contents.append(["musicShelfRenderer": ["contents": self.makePlaylistItems(count: playlists)]])
        }

        return [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": contents,
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
        ]
    }

    private func makeSongItems(count: Int) -> [[String: Any]] {
        (0 ..< count).map { i in
            [
                "musicResponsiveListItemRenderer": [
                    "playlistItemData": ["videoId": "video\(i)"],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(i)"]]]]],
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist"]]]]],
                    ],
                ],
            ]
        }
    }

    private func makeAlbumItems(count: Int) -> [[String: Any]] {
        (0 ..< count).map { i in
            [
                "musicResponsiveListItemRenderer": [
                    "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE\(i)"]],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Album \(i)"]]]]],
                    ],
                ],
            ]
        }
    }

    private func makeArtistItems(count: Int) -> [[String: Any]] {
        (0 ..< count).map { i in
            [
                "musicResponsiveListItemRenderer": [
                    "navigationEndpoint": ["browseEndpoint": ["browseId": "UC\(i)"]],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist \(i)"]]]]],
                    ],
                ],
            ]
        }
    }

    private func makePlaylistItems(count: Int) -> [[String: Any]] {
        (0 ..< count).map { i in
            [
                "musicResponsiveListItemRenderer": [
                    "navigationEndpoint": ["browseEndpoint": ["browseId": "VL\(i)"]],
                    "flexColumns": [
                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Playlist \(i)"]]]]],
                    ],
                ],
            ]
        }
    }
}
