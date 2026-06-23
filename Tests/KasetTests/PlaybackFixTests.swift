import Foundation
import Testing
@testable import Kaset

/// Regression tests for the playback bug-fix batch (F001 shuffle, F003 reconciliation guard,
/// F004 duration overwrite). UI-only fixes (F002 menu-bar list identity, F005 WebView crash
/// recovery) are exercised through the app/UI tests rather than here.
@Suite(.serialized, .tags(.service))
@MainActor
struct PlaybackFixTests {
    var playerService: PlayerService
    var mockClient: MockYTMusicClient

    init() {
        UserDefaults.standard.removeObject(forKey: "boombox.saved.queue")
        UserDefaults.standard.removeObject(forKey: "boombox.saved.queueIndex")
        UserDefaults.standard.removeObject(forKey: "boombox.saved.playbackSession")
        SingletonPlayerWebView.shared.currentVideoId = nil

        self.mockClient = MockYTMusicClient()
        self.playerService = PlayerService()
        self.playerService.setYTMusicClient(self.mockClient)
    }

    // MARK: - F001: Shuffle never replays the current track

    @Test("Shuffle Next never replays the current track over many draws")
    func shuffleNextNeverReplaysCurrentTrack() async {
        let songs = TestFixtures.makeSongs(count: 5)
        await self.playerService.playQueue(songs, startingAt: 0)
        self.playerService.toggleShuffle()
        #expect(self.playerService.shuffleEnabled == true)

        // With no exclusion the old code had a 1-in-count chance of replaying per call; over many
        // iterations this would virtually always trip. The fix guarantees a strict change every time.
        for _ in 0 ..< 200 {
            let previousIndex = self.playerService.currentIndex
            await self.playerService.next()
            #expect(self.playerService.currentIndex != previousIndex)
            #expect(self.playerService.queue.count == songs.count)
        }
    }

    @Test("Shuffle Next on a two-song queue strictly alternates")
    func shuffleNextTwoSongQueueAlternates() async {
        let songs = TestFixtures.makeSongs(count: 2)
        await self.playerService.playQueue(songs, startingAt: 0)
        self.playerService.toggleShuffle()

        // Only one other index exists, so the exclusion forces a strict 0<->1 alternation.
        await self.playerService.next()
        #expect(self.playerService.currentIndex == 1)
        await self.playerService.next()
        #expect(self.playerService.currentIndex == 0)
        await self.playerService.next()
        #expect(self.playerService.currentIndex == 1)
    }

    @Test("Shuffle Next on a single-song queue does not crash and stays put")
    func shuffleNextSingleSongQueueDoesNotCrash() async {
        let songs = TestFixtures.makeSongs(count: 1)
        await self.playerService.playQueue(songs, startingAt: 0)
        self.playerService.toggleShuffle()

        // Must not evaluate `Int.random(in: 0 ..< 0)`, which would trap.
        await self.playerService.next()
        #expect(self.playerService.currentIndex == 0)
        #expect(self.playerService.queue.count == 1)
    }

    // MARK: - F004: Live observer must not wipe a known duration with 0

    @Test("Live playback update keeps the last known duration when the observer reports 0")
    func liveUpdateKeepsKnownDurationOnZero() {
        // Seed a real duration from a normal observer tick.
        self.playerService.updatePlaybackState(isPlaying: true, progress: 10, duration: 200)
        #expect(self.playerService.duration == 200)

        // A transient 0 (progress bar briefly absent during a track change) must not wipe it.
        self.playerService.updatePlaybackState(isPlaying: true, progress: 11, duration: 0)
        #expect(self.playerService.duration == 200)

        // A subsequent valid duration still updates normally.
        self.playerService.updatePlaybackState(isPlaying: true, progress: 12, duration: 240)
        #expect(self.playerService.duration == 240)
    }

    // MARK: - F003: Reconciliation guard default state

    @Test("Web queue reconciliation guard starts cleared")
    func reconciliationGuardStartsCleared() {
        #expect(self.playerService.isReconcilingWebQueue == false)
    }
}
