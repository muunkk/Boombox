import Foundation
import Testing
@testable import Kaset

/// Pass-2 player/UI bug-fix coverage.
///
/// Focuses on the unit-testable logic from batch2-playerui:
/// - P2F035: `QueueDisplayEntry` must produce unique, stable identities even
///   when a queue contains duplicate videoIds (playlists/albums may legitimately
///   repeat a track), so SwiftUI `ForEach` no longer collides.
///
/// The other batch findings are not cleanly unit-testable here:
/// - P2F001 (MenuBarController scroll-to-volume race) lives in a private
///   `@MainActor` handler driven by live `NSEvent`s and `PlayerService`.
/// - P2F019 / P2F020 (AppKit + SwiftUI accessibility) are view-tree assertions
///   exercised by VoiceOver / UI tests, not pure logic.
/// - P2F029 (RTL chevron glyph) is a one-line SF Symbol swap with no logic.
@Suite(.tags(.model))
struct Pass2PlayerUITests {
    // MARK: - P2F035: QueueDisplayEntry identity

    @Test("Entries are produced 1:1 with the queue in order")
    func entriesPreserveOrderAndCount() {
        let songs = TestFixtures.makeSongs(count: 4)
        let entries = QueueDisplayEntry.entries(for: songs)

        #expect(entries.count == songs.count)
        for (offset, entry) in entries.enumerated() {
            #expect(entry.index == offset)
            #expect(entry.song.videoId == songs[offset].videoId)
        }
    }

    @Test("Empty queue produces no entries")
    func emptyQueueProducesNoEntries() {
        #expect(QueueDisplayEntry.entries(for: []).isEmpty)
    }

    @Test("Duplicate videoIds yield unique, stable identities")
    func duplicateVideoIdsAreUniquelyIdentified() {
        // A playlist legitimately containing the same track twice.
        let duplicate = TestFixtures.makeSong(id: "dup-video", title: "Repeat")
        let other = TestFixtures.makeSong(id: "other-video", title: "Other")
        let queue = [duplicate, other, duplicate]

        let entries = QueueDisplayEntry.entries(for: queue)
        let ids = entries.map(\.id)

        // Without the position-composite key these two would collide.
        #expect(Set(ids).count == queue.count)
        #expect(ids[0] != ids[2])
        // The two copies still map to the same underlying song.
        #expect(entries[0].song.videoId == entries[2].song.videoId)
    }

    @Test("Identity is the composite index-videoId key")
    func identityIsCompositeKey() {
        let songs = [
            TestFixtures.makeSong(id: "a"),
            TestFixtures.makeSong(id: "b"),
        ]
        let entries = QueueDisplayEntry.entries(for: songs)

        #expect(entries[0].id == "0-a")
        #expect(entries[1].id == "1-b")
    }

    @Test("All identities are unique for a fully-duplicated queue")
    func fullyDuplicatedQueueHasUniqueIdentities() {
        let song = TestFixtures.makeSong(id: "same")
        let queue = Array(repeating: song, count: 5)

        let ids = QueueDisplayEntry.entries(for: queue).map(\.id)
        #expect(Set(ids).count == 5)
    }
}
