import Foundation
import Testing
@testable import Kaset

/// Pass-3 miscellaneous fix coverage.
///
/// The window/state and toast/sidebar fixes in this batch are SwiftUI view
/// changes that are exercised by UI tests rather than unit tests, so the
/// unit-testable surface here is the allocation-free rewrite of
/// `SyncedLyrics.currentLineIndex(at:)` (PERF-006 / P3F010). These tests pin its
/// behaviour to the original `lineStatuses(at:).lastIndex(of: .current)`
/// semantics so the optimization cannot silently change which line is current.
struct Pass3MiscTests {
    // MARK: - Helpers

    /// Builds a time-sorted line list. Each tuple is (startMs, durationMs); a
    /// duration of 0 means "unknown" (line stays current until the next start).
    private static func makeLyrics(_ entries: [(start: Int, duration: Int)]) -> SyncedLyrics {
        let lines = entries.enumerated().map { index, entry in
            SyncedLyricLine(
                timeInMs: entry.start,
                duration: entry.duration,
                text: "line \(index)",
                words: nil,
                romanizedText: nil
            )
        }
        return SyncedLyrics(lines: lines, source: "test")
    }

    /// The pre-optimization reference implementation: build the full status array
    /// and take the last `.current` index. Used as the oracle.
    private static func referenceCurrentLineIndex(_ lyrics: SyncedLyrics, at timeMs: Int) -> Int? {
        lyrics.lineStatuses(at: timeMs).lastIndex(of: .current)
    }

    // MARK: - PERF-006: currentLineIndex parity with lineStatuses

    @Test("currentLineIndex matches the lineStatuses oracle across a time sweep")
    func currentLineIndexMatchesOracleAcrossSweep() {
        // Mixed known/unknown durations, including a gap before the first line and
        // a tail where every line has elapsed.
        let lyrics = Self.makeLyrics([
            (start: 1000, duration: 2000), // [1000, 3000)
            (start: 3000, duration: 1500), // [3000, 4500)
            (start: 5000, duration: 0), // unknown duration -> current from 5000 on
            (start: 8000, duration: 1000), // [8000, 9000)
        ])

        for timeMs in stride(from: -500, through: 11000, by: 50) {
            let expected = Self.referenceCurrentLineIndex(lyrics, at: timeMs)
            let actual = lyrics.currentLineIndex(at: timeMs)
            #expect(actual == expected, "Mismatch at t=\(timeMs): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }

    @Test("Before the first line starts there is no current line")
    func noCurrentLineBeforeStart() {
        let lyrics = Self.makeLyrics([(start: 1000, duration: 2000)])
        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 999) == nil)
    }

    @Test("A line is current exactly within [start, start+duration)")
    func lineIsCurrentWithinDurationWindow() {
        let lyrics = Self.makeLyrics([
            (start: 1000, duration: 2000),
            (start: 4000, duration: 1000),
        ])
        // Boundary at start.
        #expect(lyrics.currentLineIndex(at: 1000) == 0)
        // Inside the first line's window.
        #expect(lyrics.currentLineIndex(at: 2999) == 0)
        // At start+duration the first line has elapsed and the next has not begun.
        #expect(lyrics.currentLineIndex(at: 3000) == nil)
        // Inside the second line's window.
        #expect(lyrics.currentLineIndex(at: 4500) == 1)
    }

    @Test("A zero-duration line stays current until the next line or end")
    func zeroDurationLineStaysCurrent() {
        let lyrics = Self.makeLyrics([
            (start: 1000, duration: 0),
            (start: 5000, duration: 0),
        ])
        // First line current from its start through any later time (no elapse rule).
        #expect(lyrics.currentLineIndex(at: 1000) == 0)
        #expect(lyrics.currentLineIndex(at: 4999) == 0)
        // Second line wins once it starts.
        #expect(lyrics.currentLineIndex(at: 5000) == 1)
        #expect(lyrics.currentLineIndex(at: 999_999) == 1)
    }

    @Test("After every line has elapsed there is no current line")
    func noCurrentLineAfterAllElapsed() {
        let lyrics = Self.makeLyrics([
            (start: 1000, duration: 1000), // ends 2000
            (start: 2000, duration: 1000), // ends 3000
        ])
        #expect(lyrics.currentLineIndex(at: 3000) == nil)
        #expect(lyrics.currentLineIndex(at: 10000) == nil)
    }

    @Test("Empty lyrics return no current line")
    func emptyLyricsReturnNil() {
        let lyrics = Self.makeLyrics([])
        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 5000) == nil)
    }
}
