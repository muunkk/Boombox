import Foundation

// MARK: - TimedWord

/// A single timed word for karaoke mode.
struct TimedWord: Equatable {
    let timeInMs: Int
    let word: String
}

// MARK: - SyncedLyricLine

/// A single timed lyric line.
struct SyncedLyricLine: Identifiable, Equatable {
    let id = UUID()
    /// Timestamp in milliseconds when this line starts.
    let timeInMs: Int
    /// Duration in milliseconds (time until next line).
    var duration: Int
    /// The lyric text for this line.
    let text: String
    /// Optional word-level timing for karaoke mode.
    let words: [TimedWord]?
    /// Romanized version of text (nil if already Latin or romanization disabled).
    var romanizedText: String?
}

// MARK: - SyncedLyrics

/// Represents synced lyrics with per-line timestamps.
struct SyncedLyrics: Equatable {
    let lines: [SyncedLyricLine]
    let source: String

    var isEmpty: Bool {
        self.lines.isEmpty
    }

    enum LineStatus {
        case previous, current, upcoming
    }

    func lineStatuses(at timeMs: Int) -> [LineStatus] {
        self.lines.map { line in
            if line.timeInMs > timeMs { return .upcoming }
            // If the time passed the start time + duration, it's previous
            if timeMs - line.timeInMs >= line.duration, line.duration > 0 { return .previous }
            return .current
        }
    }

    /// Returns the index of the last `.current` line at `timeMs` without
    /// allocating an intermediate `[LineStatus]` array.
    ///
    /// Lines are time-sorted, so a single forward scan that stops at the first
    /// upcoming line is sufficient. A line is `.current` only while playback is
    /// within its `duration`; this matches `lineStatuses(at:)` semantics exactly.
    /// Called at ~10Hz during synced-lyric playback, so the allocation-free path
    /// avoids per-tick heap churn.
    func currentLineIndex(at timeMs: Int) -> Int? {
        var index: Int?
        for i in self.lines.indices {
            let line = self.lines[i]
            // Lines are sorted by start time; once we pass `timeMs` we can stop.
            if line.timeInMs > timeMs { break }
            // Skip lines that have already elapsed (only when a duration is known).
            if line.duration > 0, timeMs - line.timeInMs >= line.duration { continue }
            index = i
        }
        return index
    }
}

// MARK: - LyricResult

/// Unified lyrics result that can hold either synced or plain lyrics.
enum LyricResult: Equatable {
    case synced(SyncedLyrics)
    case plain(Lyrics)
    case unavailable

    var isAvailable: Bool {
        switch self {
        case let .synced(s): !s.isEmpty
        case let .plain(p): p.isAvailable
        case .unavailable: false
        }
    }
}
