import Foundation

// MARK: - LRCParser

enum LRCParser {
    /// Compiled once at type-load time and reused across every line so we don't
    /// recompile the identical pure-metadata pattern inside the parse loop.
    private static let pureMetadataRegex = try? NSRegularExpression(pattern: "^\\[([a-z]+):([^\\]]+)\\]\\s*$")

    // swiftlint:disable:next cyclomatic_complexity
    static func parse(_ raw: String) -> SyncedLyrics? {
        var unmergedLines: [SyncedLyricLine] = []
        var offsetMs = 0

        let lines = raw.components(separatedBy: .newlines)

        // Match regex for timestamps and metadata. The minute group is capped at
        // 7 digits so adversarial third-party (lrclib.net) data can't drive the
        // minute → milliseconds math into integer overflow.
        let timeRegex = try? NSRegularExpression(pattern: "\\[(\\d{2,7}):(\\d{2})\\.(\\d{2,3})\\]")
        let metadataRegex = try? NSRegularExpression(pattern: "\\[([a-z]+):([^\\]]+)\\]")
        let wordRegex = try? NSRegularExpression(pattern: "<(\\d{2,7}):(\\d{2})\\.(\\d{2,3})>([^<]+)")

        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            // Check for metadata
            if let metaMatch = metadataRegex?.firstMatch(in: line, options: [], range: fullRange) {
                let key = nsLine.substring(with: metaMatch.range(at: 1)).lowercased()
                let value = nsLine.substring(with: metaMatch.range(at: 2)).trimmingCharacters(in: .whitespaces)

                if key == "offset", let offset = Int(value) {
                    offsetMs = offset
                }

                // If it's pure metadata and has no lyric text or time tag, skip
                if let pure = Self.pureMetadataRegex,
                   pure.firstMatch(in: line, options: [], range: fullRange) != nil
                {
                    continue
                }
            }

            guard let regex = timeRegex else { continue }
            let matches = regex.matches(in: line, options: [], range: fullRange)

            if matches.isEmpty {
                continue
            }

            // Text extraction
            var textOnly = regex.stringByReplacingMatches(in: line, options: [], range: fullRange, withTemplate: "")

            // Find word level timing
            var words: [TimedWord]?
            if let wRegex = wordRegex {
                let nsText = textOnly as NSString
                let wMatches = wRegex.matches(in: textOnly, options: [], range: NSRange(location: 0, length: nsText.length))
                if !wMatches.isEmpty {
                    var extracted: [TimedWord] = []
                    for match in wMatches {
                        let mm = Int(nsText.substring(with: match.range(at: 1))) ?? 0
                        let ss = Int(nsText.substring(with: match.range(at: 2))) ?? 0
                        let msStr = nsText.substring(with: match.range(at: 3))
                        let ms = self.parseCentsToMs(msStr)
                        // Overflow-safe: skip the word rather than trapping on
                        // adversarial timestamps that exceed Int range.
                        guard let time = self.timestampMs(minutes: mm, seconds: ss, ms: ms) else {
                            continue
                        }
                        let word = nsText.substring(with: match.range(at: 4))
                        extracted.append(TimedWord(timeInMs: time, word: word))
                    }
                    words = extracted
                    textOnly = wRegex.stringByReplacingMatches(in: textOnly, options: [], range: NSRange(location: 0, length: nsText.length), withTemplate: "$4")
                }
            }

            textOnly = textOnly.trimmingCharacters(in: .whitespaces)

            for match in matches {
                let mm = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
                let ss = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
                let msStr = nsLine.substring(with: match.range(at: 3))
                let ms = self.parseCentsToMs(msStr)

                // Overflow-safe: skip the line instead of trapping if the
                // timestamp math would exceed Int range.
                guard let base = self.timestampMs(minutes: mm, seconds: ss, ms: ms) else {
                    continue
                }
                let (timeMs, subOverflow) = base.subtractingReportingOverflow(offsetMs)
                if subOverflow { continue }

                unmergedLines.append(SyncedLyricLine(
                    timeInMs: max(0, timeMs),
                    duration: 0,
                    text: textOnly,
                    words: words
                ))
            }
        }

        if unmergedLines.isEmpty {
            return nil
        }

        unmergedLines.sort { $0.timeInMs < $1.timeInMs }

        var processedLines: [SyncedLyricLine] = []

        // Auto-insert empty line at 0ms if first > 300ms
        if let first = unmergedLines.first, first.timeInMs > 300 {
            processedLines.append(SyncedLyricLine(timeInMs: 0, duration: first.timeInMs, text: "", words: nil))
        }

        for i in 0 ..< unmergedLines.count {
            var line = unmergedLines[i]
            if i < unmergedLines.count - 1 {
                let next = unmergedLines[i + 1]
                line.duration = next.timeInMs - line.timeInMs
            } else {
                line.duration = 5000 // default 5 seconds end blank
            }
            processedLines.append(line)
        }

        return SyncedLyrics(lines: processedLines, source: "Parsed")
    }

    /// Combines minutes/seconds/milliseconds into a single millisecond count
    /// using overflow-checked arithmetic. Returns nil if any step would exceed
    /// Int range so adversarial timestamps degrade gracefully instead of trapping.
    private static func timestampMs(minutes: Int, seconds: Int, ms: Int) -> Int? {
        guard minutes >= 0, seconds >= 0, ms >= 0 else { return nil }
        let (minutesMs, mo) = minutes.multipliedReportingOverflow(by: 60 * 1000)
        if mo { return nil }
        let (secondsMs, so) = seconds.multipliedReportingOverflow(by: 1000)
        if so { return nil }
        let (partial, po) = minutesMs.addingReportingOverflow(secondsMs)
        if po { return nil }
        let (total, to) = partial.addingReportingOverflow(ms)
        if to { return nil }
        return total
    }

    /// ".1" -> 100, ".12" -> 120, ".123" -> 123
    private static func parseCentsToMs(_ cc: String) -> Int {
        var str = cc
        while str.count < 3 {
            str += "0"
        }
        if str.count > 3 {
            str = String(str.prefix(3))
        }
        return Int(str) ?? 0
    }
}
