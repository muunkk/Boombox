import Foundation
import Testing
@testable import Kaset

/// Pass-3 player/UI performance-fix coverage (batch3-playerui).
///
/// These findings are about avoiding redundant per-tick work in the queue UI and
/// the player bar. Most of the fixes are AppKit/SwiftUI view-tree behaviors that
/// are exercised by integration/UI tests rather than pure logic, so this suite
/// pins down the unit-testable invariants that the fixes rely on:
///
/// - P3F037 / P3F006 (QueueSidePanelView): the side panel now skips a full
///   `NSTableView.reloadData()` when only `isPlaying`/`currentIndex` changed and
///   reloads only when the queue *contents* change. That decision is driven by a
///   per-position videoId identity token — equal queues must compare equal, and
///   reorder/insert/remove must compare not-equal.
/// - P3F038 (QueueView): `cachedEntries` is rebuilt only when the queue identity
///   changes; the same queue snapshot must yield identical entry identities so the
///   cache stays valid across isPlaying/currentIndex passes.
///
/// Not cleanly unit-testable here (and therefore not covered by assertions):
/// - P3F006 cell reuse via `tableView.makeView(withIdentifier:owner:)` and
///   `prepareForReuse()` — requires a live NSTableView.
/// - P3F013 (WaveformView timer using `MainActor.assumeIsolated`) — a run-loop
///   timer side effect, not pure logic.
/// - P3F034 (PlayerBar moving CoreAudio HAL queries off the MainActor) — the
///   correctness is "same values, computed off-actor"; verified by build/runtime,
///   and the values come from live CoreAudio hardware.
@Suite(.tags(.model))
struct Pass3PlayerUITests {
    // MARK: - Queue identity token (P3F037 / P3F006 / P3F038)

    /// The reload/rebuild decision compares `queue.map(\.videoId)`.
    private func identity(_ queue: [Song]) -> [String] {
        queue.map(\.videoId)
    }

    @Test("Identical queues produce an equal identity token (no reload needed)")
    func identicalQueuesAreEqual() {
        let queue = TestFixtures.makeSongs(count: 5)
        // A fresh snapshot of the same songs (as SwiftUI would pass on a
        // play/pause pass) must compare equal so reloadData()/rebuild is skipped.
        let snapshot = queue
        #expect(self.identity(queue) == self.identity(snapshot))
    }

    @Test("Reordering the queue changes the identity token (reload needed)")
    func reorderChangesIdentity() {
        let queue = TestFixtures.makeSongs(count: 4)
        var reordered = queue
        reordered.swapAt(0, 3)
        #expect(self.identity(queue) != self.identity(reordered))
    }

    @Test("Removing a song changes the identity token (reload needed)")
    func removalChangesIdentity() {
        let queue = TestFixtures.makeSongs(count: 4)
        let removed = Array(queue.dropFirst())
        #expect(self.identity(queue) != self.identity(removed))
    }

    @Test("Appending a song changes the identity token (reload needed)")
    func appendChangesIdentity() {
        var queue = TestFixtures.makeSongs(count: 3)
        let before = self.identity(queue)
        queue.append(TestFixtures.makeSong(id: "new-tail"))
        #expect(before != self.identity(queue))
    }

    @Test("Identity is order-sensitive even for duplicate videoIds")
    func identityIsOrderSensitiveWithDuplicates() {
        let a = TestFixtures.makeSong(id: "a")
        let b = TestFixtures.makeSong(id: "b")
        let dup = TestFixtures.makeSong(id: "a")
        // [a, b, a] vs [a, a, b] differ only by position of the duplicate.
        #expect(self.identity([a, b, dup]) != self.identity([a, dup, b]))
    }

    @Test("Empty queue has an empty identity token")
    func emptyQueueIdentity() {
        #expect(self.identity([]).isEmpty)
    }

    // MARK: - Cached entries memoization invariants (P3F038)

    @Test("Rebuilding entries for the same snapshot yields identical identities")
    func entriesAreStableForSameSnapshot() {
        let queue = TestFixtures.makeSongs(count: 6)
        let first = QueueDisplayEntry.entries(for: queue).map(\.id)
        let second = QueueDisplayEntry.entries(for: queue).map(\.id)
        // The cache is keyed on queue identity; equal identity must imply the same
        // entry ids so reusing the cached array across isPlaying passes is safe.
        #expect(first == second)
    }

    @Test("A changed queue identity yields different entry identities")
    func entriesChangeWhenQueueChanges() {
        let queue = TestFixtures.makeSongs(count: 3)
        var changed = queue
        changed.swapAt(0, 2)

        let beforeIds = QueueDisplayEntry.entries(for: queue).map(\.id)
        let afterIds = QueueDisplayEntry.entries(for: changed).map(\.id)
        #expect(beforeIds != afterIds)
    }

    @Test("Entry count and order track the queue exactly")
    func entriesTrackQueueOrder() {
        let queue = TestFixtures.makeSongs(count: 4)
        let entries = QueueDisplayEntry.entries(for: queue)
        #expect(entries.count == queue.count)
        for (offset, entry) in entries.enumerated() {
            #expect(entry.index == offset)
            #expect(entry.song.videoId == queue[offset].videoId)
        }
    }
}
