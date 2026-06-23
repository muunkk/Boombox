import Foundation
import Testing
@testable import Kaset

/// Tests for the ParsingHelpers.
@Suite(.tags(.parser))
struct ParsingHelpersTests {
    // MARK: - Chart Section Detection

    @Test(
        "Chart section detection returns true for chart titles",
        arguments: ["Top Charts", "Weekly Top 50", "Trending Now", "Daily Top 100"]
    )
    func isChartSectionWithChart(title: String) {
        #expect(ParsingHelpers.isChartSection(title) == true)
    }

    @Test(
        "Chart section detection returns false for non-chart titles",
        arguments: ["Quick picks", "New releases", "Recommended"]
    )
    func isChartSectionWithNonChart(title: String) {
        #expect(ParsingHelpers.isChartSection(title) == false)
    }

    // MARK: - URL Normalization

    @Test("Normalize URL adds https to protocol-relative URL")
    func normalizeURLWithProtocolRelative() {
        let result = ParsingHelpers.normalizeURL("//example.com/image.jpg")
        #expect(result == "https://example.com/image.jpg")
    }

    @Test("Normalize URL preserves full URL")
    func normalizeURLWithFullURL() {
        let result = ParsingHelpers.normalizeURL("https://example.com/image.jpg")
        #expect(result == "https://example.com/image.jpg")
    }

    // MARK: - Thumbnail Extraction

    @Test("Extract thumbnails from musicThumbnailRenderer")
    func extractThumbnailsFromMusicThumbnailRenderer() {
        let data: [String: Any] = [
            "thumbnail": [
                "musicThumbnailRenderer": [
                    "thumbnail": [
                        "thumbnails": [
                            ["url": "//example.com/small.jpg"],
                            ["url": "//example.com/large.jpg"],
                        ],
                    ],
                ],
            ],
        ]

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)

        #expect(thumbnails.count == 2)
        #expect(thumbnails.first == "https://example.com/small.jpg")
        #expect(thumbnails.last == "https://example.com/large.jpg")
    }

    @Test("Extract thumbnails from empty data returns empty array")
    func extractThumbnailsFromEmptyData() {
        let data: [String: Any] = [:]
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        #expect(thumbnails.isEmpty)
    }

    // MARK: - Title Extraction

    @Test("Extract title from standard title key")
    func extractTitle() {
        let data: [String: Any] = [
            "title": [
                "runs": [
                    ["text": "Test Title"],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitle(from: data)
        #expect(title == "Test Title")
    }

    @Test("Extract title with custom key")
    func extractTitleWithCustomKey() {
        let data: [String: Any] = [
            "name": [
                "runs": [
                    ["text": "Custom Name"],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitle(from: data, key: "name")
        #expect(title == "Custom Name")
    }

    @Test("Extract title from empty data returns nil")
    func extractTitleFromEmptyData() {
        let data: [String: Any] = [:]
        let title = ParsingHelpers.extractTitle(from: data)
        #expect(title == nil)
    }

    // MARK: - Artist Extraction

    @Test("Extract artists from subtitle runs")
    func extractArtists() {
        let data: [String: Any] = [
            "subtitle": [
                "runs": [
                    ["text": "Artist 1", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC1"]]],
                    ["text": " & "],
                    ["text": "Artist 2", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC2"]]],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtists(from: data)

        #expect(artists.count == 2)
        #expect(artists[0].name == "Artist 1")
        #expect(artists[0].id == "UC1")
        #expect(artists[1].name == "Artist 2")
    }

    @Test("Extract artists filters out separator characters")
    func extractArtistsFiltersSeparators() {
        // Uses two real artist names separated by a bullet. The names avoid
        // content-type keywords like "Song"/"Artist", which extractArtists now
        // filters out per the F012 fix (exercised separately in DataFixTests).
        let data: [String: Any] = [
            "subtitle": [
                "runs": [
                    ["text": "Adele"],
                    ["text": " • "],
                    ["text": "Collaborator"],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtists(from: data)

        #expect(artists.count == 2)
        #expect(artists[0].name == "Adele")
        #expect(artists[1].name == "Collaborator")
    }

    @Test("Extract artists from flex columns accepts library artist browse IDs")
    func extractArtistsFromFlexColumnsWithLibraryArtistBrowseId() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Song Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                [
                                    "text": "Library Artist",
                                    "navigationEndpoint": [
                                        "browseEndpoint": [
                                            "browseId": "MPLAUC1234567890",
                                        ],
                                    ],
                                ],
                                ["text": " • "],
                                ["text": "2026"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        #expect(artists.count == 1)
        #expect(artists[0].id == "MPLAUC1234567890")
        #expect(artists[0].name == "Library Artist")
    }

    // MARK: - Video ID Extraction

    @Test("Extract video ID from playlistItemData")
    func extractVideoIdFromPlaylistItemData() {
        let data: [String: Any] = [
            "playlistItemData": ["videoId": "abc123"],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)
        #expect(videoId == "abc123")
    }

    @Test("Extract video ID from watchEndpoint")
    func extractVideoIdFromWatchEndpoint() {
        let data: [String: Any] = [
            "navigationEndpoint": [
                "watchEndpoint": ["videoId": "xyz789"],
            ],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)
        #expect(videoId == "xyz789")
    }

    @Test("Extract video ID from overlay")
    func extractVideoIdFromOverlay() {
        let data: [String: Any] = [
            "overlay": [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "playNavigationEndpoint": [
                                "watchEndpoint": ["videoId": "overlay123"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)
        #expect(videoId == "overlay123")
    }

    // MARK: - Browse ID Extraction

    @Test("Extract browse ID from navigation endpoint")
    func extractBrowseId() {
        let data: [String: Any] = [
            "navigationEndpoint": [
                "browseEndpoint": ["browseId": "VLPL12345"],
            ],
        ]

        let browseId = ParsingHelpers.extractBrowseId(from: data)
        #expect(browseId == "VLPL12345")
    }

    // MARK: - Duration Parsing

    @Test(
        "Parse duration string to seconds",
        arguments: [
            ("3:45", 225.0), // 3 * 60 + 45
            ("1:30:00", 5400.0), // 1 * 3600 + 30 * 60
        ]
    )
    func parseDuration(input: String, expectedSeconds: TimeInterval) {
        let duration = ParsingHelpers.parseDuration(input)
        #expect(duration == expectedSeconds)
    }

    @Test("Parse invalid duration returns nil")
    func parseDurationInvalid() {
        let duration = ParsingHelpers.parseDuration("invalid")
        #expect(duration == nil)
    }

    // MARK: - Flex Column Extraction

    @Test("Extract title from flex columns")
    func extractTitleFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [["text": "Song Title"]],
                        ],
                    ],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitleFromFlexColumns(data)
        #expect(title == "Song Title")
    }

    @Test("Extract subtitle from flex columns")
    func extractSubtitleFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Artist"],
                                ["text": " • "],
                                ["text": "Album"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let subtitle = ParsingHelpers.extractSubtitleFromFlexColumns(data)
        #expect(subtitle == "Artist • Album")
    }

    @Test("Extract artists from flex columns")
    func extractArtistsFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Artist Name", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC123"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        #expect(artists.count == 1)
        #expect(artists.first?.name == "Artist Name")
        #expect(artists.first?.id == "UC123")
    }

    @Test("Fall back to text-only artist names when no navigation endpoint is present")
    func extractArtistsFromFlexColumnsTextOnlyFallback() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Artist Name"]]],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        #expect(artists.count == 1)
        #expect(artists.first?.name == "Artist Name")
        #expect(artists.first?.hasNavigableId == false)
        #expect(artists.first?.id.isEmpty == false)
    }

    @Test("Strip non-artist metadata like durations, years, and view counts")
    func extractArtistsFromFlexColumnsStripsMetadata() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Real Artist"],
                                ["text": " • "],
                                ["text": "3:45"],
                                ["text": " • "],
                                ["text": "2024"],
                                ["text": " • "],
                                ["text": "1.2M views"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        #expect(artists.count == 1)
        #expect(artists.first?.name == "Real Artist")
    }

    @Test("Keeps band names that look like words inside the views/plays patterns")
    func extractArtistsFromFlexColumnsKeepsLookAlikeBandNames() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Reviews"]]],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        // "Reviews" should NOT be filtered out — only strings matching the
        // anchored "<number>[KMB]? views/plays/streams" pattern get dropped.
        #expect(artists.count == 1)
        #expect(artists.first?.name == "Reviews")
    }

    // MARK: - Duration from Flex Columns (Artist Page)

    @Test("Extract duration from combined flex column runs (artist top songs)")
    func extractDurationFromCombinedFlexRuns() {
        // Artist page top songs have duration as the last run in a combined flex column:
        // "Artist • Album • 4:55"
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Billie Jean"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Michael Jackson", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC123"]]],
                                ["text": " • "],
                                ["text": "Thriller", "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE456"]]],
                                ["text": " • "],
                                ["text": "4:55"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let duration = ParsingHelpers.extractDurationFromFlexColumns(data)
        #expect(duration == 295.0) // 4 * 60 + 55
    }
}
