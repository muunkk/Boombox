import Foundation
import Testing
@testable import Kaset

/// Pass-3 regression tests for parser robustness against adversarial / malformed
/// API and third-party (lrclib.net) data: integer-overflow traps in duration and
/// timestamp math, unbounded recursion, and number-encoding brittleness.
///
/// Each previously-crashing input is exercised here; before the fixes these would
/// trap the process (integer overflow / stack exhaustion) instead of degrading to
/// nil / 0 / empty.
@Suite(.tags(.parser))
struct Pass3ParsersTests {
    // MARK: - FUZZ-001: ParsingHelpers.parseDuration overflow

    @Test("ParsingHelpers.parseDuration returns nil on overflowing minutes")
    func parseDurationOverflowTwoComponents() {
        // 18-digit value parses as Int but *60 overflows Int64.
        #expect(ParsingHelpers.parseDuration("200000000000000000:00") == nil)
    }

    @Test("ParsingHelpers.parseDuration returns nil on overflowing hours")
    func parseDurationOverflowThreeComponents() {
        #expect(ParsingHelpers.parseDuration("9999999999999999:00:00") == nil)
    }

    @Test("ParsingHelpers.parseDuration still parses valid durations")
    func parseDurationValidUnaffected() {
        #expect(ParsingHelpers.parseDuration("3:45") == 225)
        #expect(ParsingHelpers.parseDuration("1:11:19") == 4279)
        #expect(ParsingHelpers.parseDuration("0:00") == 0)
    }

    @Test("ParsingHelpers.parseDuration rejects malformed component counts")
    func parseDurationRejectsMalformed() {
        #expect(ParsingHelpers.parseDuration("invalid") == nil)
        #expect(ParsingHelpers.parseDuration("45") == nil)
        #expect(ParsingHelpers.parseDuration("1:2:3:4") == nil)
    }

    // MARK: - FUZZ-005 (ParsingHelpers): accessibility-label minute/second overflow

    @Test("Duration from accessibility label does not trap on absurd minute count")
    func accessibilityLabelDurationOverflowSafe() {
        // Reaches the private extractDurationFromAccessibilityLabel via the overlay
        // play-button accessibility path. The absurd minute value would overflow
        // `minutes * 60` with trapping Int math.
        let label = "Play Song by Artist, 999999999999999999 minutes, 55 seconds"
        let data: [String: Any] = [
            "overlay": [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "accessibilityPlayData": [
                                "accessibilityData": ["label": label],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        // Should not trap; computed in Double it yields a finite value (or nil),
        // never a crash.
        let result = ParsingHelpers.extractDurationFromFlexColumns(data)
        if let result {
            #expect(result.isFinite)
        }
    }

    @Test("Duration from accessibility label parses normal values")
    func accessibilityLabelDurationNormal() {
        let label = "Play Billie Jean by Michael Jackson, 4 minutes, 55 seconds"
        let data: [String: Any] = [
            "overlay": [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "accessibilityPlayData": [
                                "accessibilityData": ["label": label],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        #expect(ParsingHelpers.extractDurationFromFlexColumns(data) == 295)
    }

    // MARK: - FUZZ-002 / FUZZ-006: Song.parseDuration overflow

    @Test("Song(from:) does not trap on overflowing duration string")
    func songParseDurationOverflowSafe() {
        let data: [String: Any] = [
            "videoId": "abc123",
            "title": "Adversarial",
            "duration": "9999999999999999:00:00",
        ]
        let song = Song(from: data)
        // Decode must succeed (the rest of the payload is valid) with a nil
        // duration rather than crashing the whole decode path.
        #expect(song != nil)
        #expect(song?.duration == nil)
    }

    @Test("Song(from:) parses a valid duration string")
    func songParseDurationValid() {
        let data: [String: Any] = [
            "videoId": "abc123",
            "title": "Valid",
            "duration": "3:45",
        ]
        #expect(Song(from: data)?.duration == 225)
    }

    // MARK: - FUZZ-002 (LRCParser): timestamp math overflow on untrusted LRC

    @Test("LRCParser does not trap on adversarial minute timestamp")
    func lrcParserLineTimestampOverflowSafe() {
        // Minute group is now capped at 7 digits by the regex, so this 16-digit
        // run no longer matches the timestamp and the (only) line is dropped,
        // yielding nil instead of trapping.
        let lrc = "[9999999999999999:00.00]Adversarial line"
        #expect(LRCParser.parse(lrc) == nil)
    }

    @Test("LRCParser does not trap on adversarial word-level timestamp")
    func lrcParserWordTimestampOverflowSafe() {
        let lrc = "[00:01.00]<9999999999999999:00.00>word"
        // Must not crash; the line-level timestamp is valid so we still get a
        // result, but the adversarial word timing is skipped safely.
        _ = LRCParser.parse(lrc)
    }

    @Test("LRCParser parses normal synced lyrics with valid timestamps")
    func lrcParserValidUnaffected() throws {
        let lrc = "[00:12.00]First line\n[00:15.50]Second line"
        let synced = try #require(LRCParser.parse(lrc))
        #expect(!synced.lines.isEmpty)
    }

    // MARK: - FUZZ-003: PodcastParser.parseDurationToSeconds overflow

    @Test("Podcast episode duration does not trap on overflowing 'X min'")
    func podcastDurationMinSuffixOverflowSafe() {
        let data = Self.makePodcastDiscovery(durationText: "200000000000000000 min")
        let sections = PodcastParser.parseDiscovery(data)
        let episode = Self.firstEpisode(in: sections)
        #expect(episode != nil)
        #expect(episode?.durationSeconds == nil)
    }

    @Test("Podcast episode duration does not trap on overflowing colon format")
    func podcastDurationColonOverflowSafe() {
        let data = Self.makePodcastDiscovery(durationText: "200000000000000000:00")
        let sections = PodcastParser.parseDiscovery(data)
        let episode = Self.firstEpisode(in: sections)
        #expect(episode != nil)
        #expect(episode?.durationSeconds == nil)
    }

    @Test("Podcast episode duration parses valid values")
    func podcastDurationValid() {
        let minData = Self.makePodcastDiscovery(durationText: "36 min")
        #expect(Self.firstEpisode(in: PodcastParser.parseDiscovery(minData))?.durationSeconds == 2160)

        let colonData = Self.makePodcastDiscovery(durationText: "1:11:19")
        #expect(Self.firstEpisode(in: PodcastParser.parseDiscovery(colonData))?.durationSeconds == 4279)
    }

    // MARK: - FUZZ-005 (Podcast): playback progress encoded as a float NSNumber

    @Test("Podcast playback progress honors float-encoded percentage")
    func podcastPlaybackProgressFloatEncoded() {
        // 33.0 deserializes to a Double-backed NSNumber; the old `as? Int` would
        // drop it, leaving progress at 0. Now it is honored.
        let data = Self.makePodcastDiscovery(durationText: "36 min", playbackPercentage: 33.0)
        let episode = Self.firstEpisode(in: PodcastParser.parseDiscovery(data))
        #expect(episode?.playbackProgress == 0.33)
        #expect(episode?.isPlayed == false)
    }

    @Test("Podcast playback progress still honors integer percentage")
    func podcastPlaybackProgressIntEncoded() {
        let data = Self.makePodcastDiscovery(durationText: "36 min", playbackPercentage: 96)
        let episode = Self.firstEpisode(in: PodcastParser.parseDiscovery(data))
        #expect(episode?.playbackProgress == 0.96)
        #expect(episode?.isPlayed == true)
    }

    // MARK: - FUZZ-004: LyricsParser.findTimedLyricsModel deep recursion

    @Test("LyricsParser tolerates pathologically deep response without crashing")
    func lyricsParserDeepNestingDoesNotCrash() {
        // Build a nesting far deeper than the depth cap (20) so the parser must stop
        // at the cap and never traverse this far. Kept modest (100) so tearing down
        // the nested structure doesn't itself overflow the test harness's stack.
        var node: Any = ["leaf": "value"]
        for _ in 0 ..< 100 {
            node = ["child": node]
        }
        let data: [String: Any] = ["contents": node]
        // No timedLyricsModel present -> nil, but crucially must not crash.
        #expect(LyricsParser.extractTimedLyrics(from: data) == nil)
    }

    @Test("LyricsParser still finds a shallow timedLyricsModel")
    func lyricsParserFindsShallowModel() {
        let data: [String: Any] = [
            "wrapper": [
                "timedLyricsModel": [
                    "lyricsData": [
                        ["lyricLine": "Hello", "startTimeMs": "1000", "durationMs": "500"],
                    ],
                ],
            ],
        ]
        let result = LyricsParser.extractTimedLyrics(from: data)
        #expect(result != nil)
        #expect(result?.lines.count == 1)
    }

    // MARK: - FUZZ-007: SearchResponseParser.parseSearchSections deep recursion

    @Test("SearchResponseParser tolerates deeply nested itemSectionRenderer wrappers")
    func searchParserDeepNestingDoesNotCrash() {
        // Nest itemSectionRenderer wrappers far past the depth cap (16) — the parser
        // must stop at the cap. Kept modest (100) so tearing down the nested structure
        // doesn't itself overflow the test harness's stack.
        var inner: [String: Any] = ["musicShelfRenderer": ["contents": [[String: Any]]()]]
        for _ in 0 ..< 100 {
            inner = ["itemSectionRenderer": ["contents": [inner]]]
        }
        let data: [String: Any] = [
            "contents": [
                "tabbedSearchResultsRenderer": [
                    "tabs": [
                        [
                            "tabRenderer": [
                                "content": [
                                    "sectionListRenderer": [
                                        "contents": [inner],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        // Must complete without crashing.
        let response = SearchResponseParser.parse(data)
        #expect(response.sections.isEmpty)
    }

    // MARK: - Helpers

    /// Builds a minimal-but-valid podcast discovery response carrying one episode
    /// in a music shelf, with the given duration text and optional playback
    /// progress percentage (encoded with whatever numeric type is passed).
    private static func makePodcastDiscovery(
        durationText: String,
        playbackPercentage: Any? = nil
    ) -> [String: Any] {
        var episodeRenderer: [String: Any] = [
            "onTap": ["watchEndpoint": ["videoId": "vid123"]],
            "title": ["runs": [["text": "Episode Title"]]],
            "durationText": ["runs": [["text": durationText]]],
        ]
        if let playbackPercentage {
            episodeRenderer["playbackProgress"] = [
                "playbackProgressPercentage": playbackPercentage,
            ]
        }

        let shelf: [String: Any] = [
            "musicShelfRenderer": [
                "title": ["runs": [["text": "Episodes"]]],
                "contents": [
                    ["musicMultiRowListItemRenderer": episodeRenderer],
                ],
            ],
        ]

        return [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [
                        [
                            "tabRenderer": [
                                "content": [
                                    "sectionListRenderer": [
                                        "contents": [shelf],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func firstEpisode(in sections: [PodcastSection]) -> PodcastEpisode? {
        for section in sections {
            for item in section.items {
                if case let .episode(episode) = item {
                    return episode
                }
            }
        }
        return nil
    }
}
