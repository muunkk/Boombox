import Foundation
import Testing
@testable import Kaset

/// Pass-2 player batch regression tests.
///
/// Covers the confirmed Pass-2 player findings:
/// - CRASH-001 (P2F006): reorderQueue bounds guard against stale drag indices.
/// - PLAY2-003 (P2F034): shuffle + single-song queue with repeat off ends instead of looping forever.
/// - CONC-003 (P2F003) / PLAY2-002 (P2F033): play(videoId:) seeds isKasetInitiatedPlayback and resets track status.
/// - PLAY2-007 (P2F038): stop() clears pendingPlayVideoId / showMiniPlayer.
/// - ERR-04 (P2F010): playWithMix surfaces a user-facing error on failure.
/// - PLAY2-005 (P2F036): a STATE_UPDATE does not resurrect a deliberately-ended state.
/// - PLAY2-009 (P2F040): a non-playing observation resolves a stuck .loading state to .paused.
@Suite(.serialized, .tags(.service))
@MainActor
struct Pass2PlayerTests {
    var playerService: PlayerService

    init() {
        UserDefaults.standard.removeObject(forKey: "playerVolume")
        UserDefaults.standard.removeObject(forKey: "playerVolumeBeforeMute")
        self.playerService = PlayerService()
    }

    private func makeSongs(count: Int) -> [Song] {
        (0 ..< count).map { index in
            Song(
                id: "\(index)",
                title: "Song \(index)",
                artists: [Artist(id: "a\(index)", name: "Artist \(index)")],
                album: nil,
                duration: 180,
                thumbnailURL: nil,
                videoId: "v\(index)"
            )
        }
    }

    // MARK: - CRASH-001: reorderQueue bounds guard

    @Test("reorderQueue ignores a source index that exceeds the (shrunken) queue without crashing")
    func reorderQueueIgnoresStaleSourceIndex() async {
        let songs = self.makeSongs(count: 3)
        await self.playerService.playQueue(songs, startingAt: 0)

        // Captured drag source (index 5) no longer exists after the queue shrank to 3.
        self.playerService.reorderQueue(from: IndexSet(integer: 5), to: 1)

        // Safe no-op: queue order is unchanged and no trap occurred.
        #expect(self.playerService.queue.count == 3)
        #expect(self.playerService.queue.map(\.videoId) == ["v0", "v1", "v2"])
    }

    @Test("reorderQueue ignores a destination offset beyond queue.count without crashing")
    func reorderQueueIgnoresOversizedDestination() async {
        let songs = self.makeSongs(count: 3)
        await self.playerService.playQueue(songs, startingAt: 0)

        // Valid source, but destination 9 exceeds the legal 0...count window.
        self.playerService.reorderQueue(from: IndexSet(integer: 1), to: 9)

        #expect(self.playerService.queue.count == 3)
        #expect(self.playerService.queue.map(\.videoId) == ["v0", "v1", "v2"])
    }

    @Test("reorderQueue still moves a valid item with an in-bounds destination of queue.count")
    func reorderQueueAcceptsDestinationEqualToCount() async {
        let songs = self.makeSongs(count: 3)
        await self.playerService.playQueue(songs, startingAt: 0)

        // Move the last non-current item (index 2) to the very end (destination == count).
        self.playerService.reorderQueue(from: IndexSet(integer: 1), to: 3)

        #expect(self.playerService.queue.count == 3)
        // [v0*, v1, v2] -> moving v1 to end -> [v0, v2, v1]
        #expect(self.playerService.queue.map(\.videoId) == ["v0", "v2", "v1"])
    }

    // MARK: - PLAY2-003: shuffle + single-song + repeat off ends at track end

    @Test("Single-song shuffle queue with repeat off ends at track end instead of looping forever")
    func singleSongShuffleRepeatOffEndsAtTrackEnd() async {
        let song = Song(
            id: "solo",
            title: "Solo",
            artists: [],
            album: nil,
            duration: 180,
            thumbnailURL: nil,
            videoId: "solo-video"
        )
        await self.playerService.playQueue([song], startingAt: 0)
        self.playerService.toggleShuffle()
        #expect(self.playerService.shuffleEnabled)
        #expect(self.playerService.repeatMode == .off)

        await self.playerService.handleTrackEnded(observedVideoId: "solo-video")

        // The fix gates the shuffle term on queue.count > 1, so a 1-song queue ends instead of replaying.
        #expect(self.playerService.state == .ended)
        #expect(self.playerService.currentIndex == 0)
    }

    @Test("Multi-song shuffle queue still advances at track end")
    func multiSongShuffleStillAdvancesAtTrackEnd() async {
        let songs = self.makeSongs(count: 3)
        await self.playerService.playQueue(songs, startingAt: 0)
        self.playerService.toggleShuffle()
        #expect(self.playerService.shuffleEnabled)

        await self.playerService.handleTrackEnded(observedVideoId: "v0")

        // A multi-song shuffle queue keeps advancing; it must not declare end-of-queue.
        #expect(self.playerService.state != .ended)
    }

    // MARK: - CONC-003 / PLAY2-002: play(videoId:) flags + status reset

    @Test("play(videoId:) sets isKasetInitiatedPlayback so the autoplay corrector is active")
    func playByVideoIdSetsKasetInitiatedFlag() async {
        await self.playerService.play(videoId: "abc123")
        #expect(self.playerService.isKasetInitiatedPlayback)
        #expect(self.playerService.pendingPlayVideoId == "abc123")
    }

    @Test("play(videoId:) resets the previous track's like/library/feedback state")
    func playByVideoIdResetsTrackStatus() async {
        // Seed stale per-track status that belongs to a previous track.
        self.playerService.currentTrackLikeStatus = .like
        self.playerService.currentTrackInLibrary = true
        self.playerService.currentTrackFeedbackTokens = FeedbackTokens(add: "stale-add", remove: "stale-remove")

        await self.playerService.play(videoId: "fresh-video")

        // The stale feedback tokens must not leak onto the new track (would corrupt toggleLibraryStatus).
        #expect(self.playerService.currentTrackFeedbackTokens == nil)
        #expect(!self.playerService.currentTrackInLibrary)
    }

    // MARK: - PLAY2-007: stop() clears pending playback identity

    @Test("stop() clears pendingPlayVideoId and showMiniPlayer")
    func stopClearsPendingPlaybackIdentity() async {
        await self.playerService.play(videoId: "stop-me")
        #expect(self.playerService.pendingPlayVideoId == "stop-me")

        await self.playerService.stop()

        #expect(self.playerService.pendingPlayVideoId == nil)
        #expect(!self.playerService.showMiniPlayer)
        #expect(self.playerService.currentTrack == nil)
        #expect(self.playerService.state == .idle)
    }

    // MARK: - ERR-04: playWithMix surfaces failure

    @Test("playWithMix without a client surfaces a user-facing error")
    func playWithMixWithoutClientSurfacesError() async {
        // No YTMusicClient configured.
        await self.playerService.playWithMix(playlistId: "RDEM123", startVideoId: nil)

        #expect(self.playerService.queue.isEmpty)
        #expect(self.playerService.lastPlaybackError != nil)
    }

    @Test("playWithMix with an empty result surfaces a user-facing error")
    func playWithMixEmptyResultSurfacesError() async {
        let mockClient = MockYTMusicClient()
        self.playerService.setYTMusicClient(mockClient)

        // MockYTMusicClient.getMixQueue returns an empty RadioQueueResult by default.
        await self.playerService.playWithMix(playlistId: "RDEM123", startVideoId: nil)

        #expect(self.playerService.queue.isEmpty)
        #expect(self.playerService.lastPlaybackError != nil)
    }

    // MARK: - PLAY2-005: STATE_UPDATE does not resurrect a deliberately-ended state

    @Test("A playing observation does not resurrect a deliberately-ended state")
    func playingObservationDoesNotResurrectEndedState() async {
        let songs = self.makeSongs(count: 2)
        await self.playerService.playQueue(songs, startingAt: 1)
        self.playerService.isKasetInitiatedPlayback = false

        // End of native queue with repeat off -> markPlaybackEnded() sets .ended.
        await self.playerService.handleTrackEnded(observedVideoId: "v1")
        #expect(self.playerService.state == .ended)

        // A lingering YouTube autoplay STATE_UPDATE must not flip us back to .playing.
        self.playerService.updatePlaybackState(isPlaying: true, progress: 0, duration: 180)
        #expect(self.playerService.state == .ended)
    }

    // MARK: - PLAY2-009: loaded-but-not-autoplaying resolves to paused

    @Test("A non-playing observation resolves a stuck .loading state to .paused")
    func nonPlayingObservationResolvesLoadingToPaused() async {
        await self.playerService.play(videoId: "loaded-but-paused")
        #expect(self.playerService.state == .loading)

        // Load completed but the page did not autoplay (autoplay blocked / AirPlay handoff).
        self.playerService.updatePlaybackState(isPlaying: false, progress: 0, duration: 200)

        #expect(self.playerService.state == .paused)
    }

    @Test("A playing observation still transitions a fresh load to .playing")
    func playingObservationTransitionsLoadingToPlaying() async {
        await self.playerService.play(videoId: "autoplaying")
        #expect(self.playerService.state == .loading)

        self.playerService.updatePlaybackState(isPlaying: true, progress: 1, duration: 200)

        #expect(self.playerService.state == .playing)
    }
}
