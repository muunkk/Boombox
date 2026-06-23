import Foundation
import Testing
@testable import Kaset

/// Pass 2 regression tests for view-layer bug fixes (batch: views).
///
/// Covers the unit-testable logic behind the view fixes:
/// - P2F014: `ActionErrorPresenter` surfaces content-action failures (sequence
///   bumps, message mapping, auth-expired → sign-in prompt).
/// - P2F054: `SongActionsHelper.addToLibrary` only trusts the song's `add`
///   feedback token when the song is not already known to be in the library,
///   otherwise it falls through to the `getSong()` + `isInLibrary` slow path
///   (prevents an accidental toggle/remove).
/// - P2F009: `HistoryView.historyRows` produces stable, section-unique identities
///   (sanity coverage for the empty-state edit's surrounding logic).
@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct Pass2ViewsTests {
    // MARK: - P2F014: ActionErrorPresenter

    @Test("ActionErrorPresenter.show sets the message and bumps the sequence")
    func actionPresenterShowBumpsSequence() {
        let presenter = ActionErrorPresenter.shared
        presenter.clear()
        let startSequence = presenter.sequence

        presenter.show("First")
        #expect(presenter.lastMessage == "First")
        #expect(presenter.sequence == startSequence + 1)

        // An identical message still bumps the sequence so observers re-trigger.
        presenter.show("First")
        #expect(presenter.sequence == startSequence + 2)

        presenter.clear()
        #expect(presenter.lastMessage == nil)
    }

    @Test("ActionErrorPresenter maps authExpired to a sign-in prompt")
    func actionPresenterMapsAuthExpired() {
        let presenter = ActionErrorPresenter.shared
        presenter.clear()

        presenter.show(error: YTMusicError.authExpired, fallback: "fallback")
        #expect(presenter.lastMessage == String(localized: "Your session expired. Please sign in again."))

        presenter.show(error: YTMusicError.notAuthenticated, fallback: "fallback")
        #expect(presenter.lastMessage == String(localized: "Your session expired. Please sign in again."))

        presenter.clear()
    }

    @Test("ActionErrorPresenter uses the fallback for non-YTMusic errors")
    func actionPresenterUsesFallback() {
        let presenter = ActionErrorPresenter.shared
        presenter.clear()

        presenter.show(error: URLError(.notConnectedToInternet), fallback: "Custom fallback")
        #expect(presenter.lastMessage == "Custom fallback")

        presenter.clear()
    }

    @Test("ActionErrorPresenter surfaces a YTMusicError's own description")
    func actionPresenterSurfacesYTMusicDescription() {
        let presenter = ActionErrorPresenter.shared
        presenter.clear()

        let apiError = YTMusicError.apiError(message: "boom", code: 500)
        presenter.show(error: apiError, fallback: "fallback")
        #expect(presenter.lastMessage == apiError.localizedDescription)
        // It should not have used the generic fallback.
        #expect(presenter.lastMessage != "fallback")

        presenter.clear()
    }

    // MARK: - P2F054: addToLibrary fast-path guard

    @Test("addToLibrary uses the song's add token directly when not in library")
    func addToLibraryFastPathForNotInLibrarySong() async {
        let client = MockYTMusicClient()
        let song = Song(
            id: "vid-1",
            title: "Song",
            artists: [Artist(id: "a", name: "Artist")],
            videoId: "vid-1",
            isInLibrary: false,
            feedbackTokens: FeedbackTokens(add: "ADD_TOKEN", remove: "REMOVE_TOKEN")
        )

        await SongActionsHelper.addToLibrary(song, client: client)

        #expect(client.editSongLibraryStatusCalled)
        #expect(client.editSongLibraryStatusTokens == [["ADD_TOKEN"]])
        // Fast path means no metadata fetch.
        #expect(client.getSongCalled == false)
    }

    @Test("addToLibrary fast path also applies when isInLibrary is unknown (nil)")
    func addToLibraryFastPathForUnknownLibraryState() async {
        let client = MockYTMusicClient()
        let song = Song(
            id: "vid-2",
            title: "Song",
            artists: [Artist(id: "a", name: "Artist")],
            videoId: "vid-2",
            isInLibrary: nil,
            feedbackTokens: FeedbackTokens(add: "ADD_TOKEN_2", remove: "REMOVE_TOKEN_2")
        )

        await SongActionsHelper.addToLibrary(song, client: client)

        #expect(client.editSongLibraryStatusTokens == [["ADD_TOKEN_2"]])
        #expect(client.getSongCalled == false)
    }

    @Test("addToLibrary skips the toggle token for an already-in-library song")
    func addToLibrarySkipsFastPathForInLibrarySong() async {
        let client = MockYTMusicClient()
        // Slow-path metadata reports the song is already in the library, so no
        // edit should be issued (and definitely not the toggle-style add token).
        client.songResponses["vid-3"] = Song(
            id: "vid-3",
            title: "Song",
            artists: [Artist(id: "a", name: "Artist")],
            videoId: "vid-3",
            isInLibrary: true
        )

        let song = Song(
            id: "vid-3",
            title: "Song",
            artists: [Artist(id: "a", name: "Artist")],
            videoId: "vid-3",
            isInLibrary: true,
            feedbackTokens: FeedbackTokens(add: "TOGGLE_REMOVE_TOKEN", remove: "DEFAULT_TOKEN")
        )

        await SongActionsHelper.addToLibrary(song, client: client)

        // It fell through to the slow path that consults getSong().
        #expect(client.getSongCalled)
        // And it must NOT have called edit with the dangerous toggle token.
        #expect(client.editSongLibraryStatusCalled == false)
    }

    // MARK: - P2F009: HistoryView stable row identity (surrounding logic sanity)

    @Test("historyRows produces stable, section-unique identities for duplicates")
    func historyRowsStableIdentity() {
        let songA = Song(id: "v1", title: "A", artists: [], videoId: "v1")
        let songB = Song(id: "v2", title: "B", artists: [], videoId: "v2")
        // v1 appears twice — its two rows must still get unique ids.
        let rows = HistoryView.historyRows(for: [songA, songB, songA], sectionID: "today")

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows[0].id == "today-v1-0")
        #expect(rows[2].id == "today-v1-1")
        #expect(rows.map(\.index) == [0, 1, 2])
    }
}
