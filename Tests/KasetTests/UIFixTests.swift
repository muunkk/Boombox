import Foundation
import SwiftUI
import Testing
@testable import Kaset

/// Coverage for the batch of UX/UI fixes (F017–F026).
///
/// `@MainActor`: several of the units under test live on `View`-conforming
/// types (e.g. `HistoryView.historyRows`, `NavigationSwipeGestures`), which
/// Swift 6 infers as `@MainActor`. The suite must run on the main actor so
/// those calls execute on the correct executor (otherwise the synchronous
/// cross-actor call traps at runtime).
@MainActor
@Suite("UI Fix Tests")
struct UIFixTests {
    // MARK: - F026 Accessibility identifiers

    @Test("New Releases and History expose container accessibility identifiers")
    func containerAccessibilityIdentifiers() {
        #expect(AccessibilityID.NewReleases.container == "newReleasesView")
        #expect(AccessibilityID.History.container == "historyView")
        #expect(AccessibilityID.History.scrollView == "historyView.scrollView")
    }

    // MARK: - F018 History stable row identity

    @Test("History rows have unique, stable ids that tolerate duplicate videoIds")
    func historyRowsUniqueAndStable() {
        let songA = TestFixtures.makeSong(id: "vidA", title: "A")
        let songB = TestFixtures.makeSong(id: "vidB", title: "B")
        // 'songA' appears twice in the same section (played twice today).
        let songs = [songA, songB, songA]
        let rows = HistoryView.historyRows(for: songs, sectionID: "today")

        // Indices are preserved for playback (playQueue startingAt:).
        #expect(rows.map(\.index) == [0, 1, 2])
        // Ids are unique within the section despite the duplicate videoId.
        #expect(Set(rows.map(\.id)).count == rows.count)
        // Duplicate occurrences get distinct occurrence suffixes.
        #expect(rows[0].id == "today-vidA-0")
        #expect(rows[2].id == "today-vidA-1")
    }

    @Test("Prepending a distinct song keeps existing rows' identities stable")
    func historyRowsStableAcrossPrepend() {
        let songA = TestFixtures.makeSong(id: "vidA")
        let songB = TestFixtures.makeSong(id: "vidB")
        let before = HistoryView.historyRows(for: [songA, songB], sectionID: "today")
        let after = HistoryView.historyRows(
            for: [TestFixtures.makeSong(id: "vidC"), songA, songB],
            sectionID: "today"
        )

        // 'songA' keeps the same id after a new item is prepended — unlike the
        // old index-based identity, where every id shifted on refresh.
        let aBefore = before.first { $0.song.videoId == "vidA" }?.id
        let aAfter = after.first { $0.song.videoId == "vidA" }?.id
        #expect(aBefore != nil)
        #expect(aBefore == aAfter)
    }

    // MARK: - F025 Swipe promotion heuristic

    @Test("Strongly horizontal scrolls promote to swipe; carousel-like scrolls do not")
    func swipeHorizontalHeuristic() {
        // Deliberate horizontal swipe.
        #expect(NavigationSwipeGestures.isStronglyHorizontal(deltaX: 10, deltaY: 1))
        // Near-vertical scroll.
        #expect(!NavigationSwipeGestures.isStronglyHorizontal(deltaX: 1, deltaY: 10))
        // Ambiguous/diagonal carousel flick (deltaX only slightly greater than deltaY).
        #expect(!NavigationSwipeGestures.isStronglyHorizontal(deltaX: 3, deltaY: 2))
        // Tiny horizontal jitter below the magnitude floor.
        #expect(!NavigationSwipeGestures.isStronglyHorizontal(deltaX: 1.0, deltaY: 0.0))
    }

    // MARK: - F022 Add to Library does not play the song

    @MainActor
    @Test("Add to Library fetches the add token via metadata and never plays the song")
    func addToLibraryUsesApiWhenTokenMissing() async {
        let client = MockYTMusicClient()
        let videoId = "vidLib"
        client.songResponses[videoId] = Song(
            id: videoId,
            title: "Song",
            artists: [],
            videoId: videoId,
            isInLibrary: false,
            feedbackTokens: FeedbackTokens(add: "ADD_TOKEN", remove: "REMOVE_TOKEN")
        )
        // A search/list Song without feedback tokens.
        let song = TestFixtures.makeSong(id: videoId)

        await SongActionsHelper.addToLibrary(song, client: client)

        #expect(client.getSongVideoIds == [videoId])
        #expect(client.editSongLibraryStatusTokens == [["ADD_TOKEN"]])
    }

    @MainActor
    @Test("Add to Library uses the song's own add token without a metadata fetch")
    func addToLibraryUsesAttachedToken() async {
        let client = MockYTMusicClient()
        let song = Song(
            id: "vidT",
            title: "Song",
            artists: [],
            videoId: "vidT",
            feedbackTokens: FeedbackTokens(add: "OWN_ADD", remove: nil)
        )

        await SongActionsHelper.addToLibrary(song, client: client)

        #expect(client.getSongVideoIds.isEmpty)
        #expect(client.editSongLibraryStatusTokens == [["OWN_ADD"]])
    }

    @MainActor
    @Test("Add to Library skips the API when the song is already in the library")
    func addToLibrarySkipsWhenAlreadyInLibrary() async {
        let client = MockYTMusicClient()
        let videoId = "vidIn"
        client.songResponses[videoId] = Song(
            id: videoId,
            title: "Song",
            artists: [],
            videoId: videoId,
            isInLibrary: true,
            feedbackTokens: FeedbackTokens(add: "ADD", remove: "REMOVE")
        )
        let song = TestFixtures.makeSong(id: videoId)

        await SongActionsHelper.addToLibrary(song, client: client)

        #expect(client.getSongVideoIds == [videoId])
        #expect(client.editSongLibraryStatusTokens.isEmpty)
    }
}
