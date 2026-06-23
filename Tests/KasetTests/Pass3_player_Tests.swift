import Foundation
import Observation
import Testing
@testable import Kaset

// MARK: - ChangeFlag

/// Reference box so withObservationTracking's @Sendable onChange can record a
/// mutation without capturing a `var` (forbidden under Swift 6 concurrency).
private final class ChangeFlag: @unchecked Sendable {
    var value = false
}

// MARK: - Pass3PlayerTests

/// Pass-3 player batch regression tests.
///
/// Covers the confirmed Pass-3 player findings fixed in this batch:
/// - SEC-003 (P3F003): thumbnail URL from the WebView bridge is rejected unless it is http(s).
/// - PERF-001 (P3F005): a repeated `.playing` STATE_UPDATE does not re-notify Observation.
/// - PERSIST-005 (P3F041): persisted session schema versioning is backward-compatible and
///   refuses to restore a session written by a newer (unsupported) schema version.
@Suite(.serialized, .tags(.service))
@MainActor
struct Pass3PlayerTests {
    /// The three UserDefaults keys PlayerService uses for queue persistence (kept in sync with the
    /// private constants in PlayerService+Queue.swift). Cleared around persistence tests so they
    /// never read or leave behind real user data.
    /// Unique prefix so this suite's queue-persistence keys never collide with the real keys that
    /// sibling suites write to the shared UserDefaults.standard via saveQueueForPersistence.
    private static let keyPrefix = "test.pass3player."
    private static let savedQueueKey = "\(keyPrefix)boombox.saved.queue"
    private static let savedQueueIndexKey = "\(keyPrefix)boombox.saved.queueIndex"
    private static let savedPlaybackSessionKey = "\(keyPrefix)boombox.saved.playbackSession"

    let playerService: PlayerService

    init() {
        UserDefaults.standard.removeObject(forKey: "playerVolume")
        UserDefaults.standard.removeObject(forKey: "playerVolumeBeforeMute")
        Self.clearPersistenceKeys()
        self.playerService = PlayerService(queuePersistenceKeyPrefix: Self.keyPrefix)
    }

    private static func clearPersistenceKeys() {
        UserDefaults.standard.removeObject(forKey: self.savedQueueKey)
        UserDefaults.standard.removeObject(forKey: self.savedQueueIndexKey)
        UserDefaults.standard.removeObject(forKey: self.savedPlaybackSessionKey)
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

    // MARK: - SEC-003: thumbnail URL scheme guard at the WebView trust boundary

    @Test("updateTrackMetadata accepts an https thumbnail URL")
    func updateTrackMetadataAcceptsHttpsThumbnail() {
        self.playerService.updateTrackMetadata(
            title: "Track",
            artist: "Artist",
            thumbnailUrl: "https://i.ytimg.com/vi/abc/hqdefault.jpg",
            videoId: "abc"
        )

        #expect(self.playerService.currentTrack?.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/abc/hqdefault.jpg")
    }

    @Test("updateTrackMetadata accepts a plain http thumbnail URL")
    func updateTrackMetadataAcceptsHttpThumbnail() {
        self.playerService.updateTrackMetadata(
            title: "Track",
            artist: "Artist",
            thumbnailUrl: "http://i.ytimg.com/vi/abc/hqdefault.jpg",
            videoId: "abc"
        )

        #expect(self.playerService.currentTrack?.thumbnailURL?.scheme == "http")
    }

    @Test("updateTrackMetadata rejects a file:// thumbnail URL (no local-file fetch)")
    func updateTrackMetadataRejectsFileThumbnail() {
        self.playerService.updateTrackMetadata(
            title: "Track",
            artist: "Artist",
            thumbnailUrl: "file:///etc/passwd",
            videoId: "abc"
        )

        // The spoofed file:// URL must never become a real URL that ImageCache could fetch.
        #expect(self.playerService.currentTrack != nil)
        #expect(self.playerService.currentTrack?.thumbnailURL == nil)
    }

    @Test("updateTrackMetadata rejects a data: thumbnail URL")
    func updateTrackMetadataRejectsDataThumbnail() {
        self.playerService.updateTrackMetadata(
            title: "Track",
            artist: "Artist",
            thumbnailUrl: "data:image/png;base64,AAAA",
            videoId: "abc"
        )

        #expect(self.playerService.currentTrack?.thumbnailURL == nil)
    }

    // MARK: - PERF-001: @Observable state is not re-notified on an unchanged .playing tick

    @Test("A repeated playing STATE_UPDATE does not re-notify Observation when state is unchanged")
    func repeatedPlayingTickDoesNotRenotifyState() async {
        // Drive a fresh load into .playing exactly like the WebView observer would.
        await self.playerService.play(videoId: "perf-001")
        self.playerService.updatePlaybackState(isPlaying: true, progress: 1, duration: 200)
        #expect(self.playerService.state == .playing)

        // Track reads of `state`; the closure fires only when an *actual* mutation is observed.
        let stateChange = ChangeFlag()
        withObservationTracking {
            _ = self.playerService.state
        } onChange: {
            stateChange.value = true
        }

        // A second identical playing tick (progress moves, state does not) must NOT mutate `state`.
        self.playerService.updatePlaybackState(isPlaying: true, progress: 2, duration: 200)

        #expect(self.playerService.state == .playing)
        #expect(!stateChange.value, "Re-assigning the same .playing value must not fire Observation")
    }

    @Test("A genuine state change still notifies Observation")
    func genuineStateChangeStillNotifies() async {
        await self.playerService.play(videoId: "perf-001-change")
        self.playerService.updatePlaybackState(isPlaying: true, progress: 1, duration: 200)
        #expect(self.playerService.state == .playing)

        let stateChange = ChangeFlag()
        withObservationTracking {
            _ = self.playerService.state
        } onChange: {
            stateChange.value = true
        }

        // Transitioning playing -> paused is a real change and must notify observers.
        self.playerService.updatePlaybackState(isPlaying: false, progress: 2, duration: 200)

        #expect(self.playerService.state == .paused)
        #expect(stateChange.value, "A real state transition must fire Observation")
    }

    @Test("A playing observation still transitions a fresh load to .playing (no regression)")
    func playingObservationStillTransitionsLoadingToPlaying() async {
        await self.playerService.play(videoId: "perf-001-load")
        #expect(self.playerService.state == .loading)

        self.playerService.updatePlaybackState(isPlaying: true, progress: 1, duration: 200)

        #expect(self.playerService.state == .playing)
    }

    // MARK: - PERSIST-005: schema-versioned playback session restore

    @Test("restoreQueueFromPersistence restores a legacy session written without a schemaVersion field")
    func restoresLegacySessionWithoutSchemaVersion() throws {
        defer { Self.clearPersistenceKeys() }

        let songs = self.makeSongs(count: 3)
        try Self.writeSessionBlob(
            queue: songs,
            currentIndex: 1,
            currentVideoId: "v1",
            progress: 12,
            duration: 180,
            schemaVersion: nil
        )

        let restored = self.playerService.restoreQueueFromPersistence()

        #expect(restored)
        #expect(self.playerService.queue.map(\.videoId) == ["v0", "v1", "v2"])
        #expect(self.playerService.currentIndex == 1)
    }

    @Test("restoreQueueFromPersistence restores a current-schema (v1) session")
    func restoresCurrentSchemaSession() throws {
        defer { Self.clearPersistenceKeys() }

        let songs = self.makeSongs(count: 2)
        try Self.writeSessionBlob(
            queue: songs,
            currentIndex: 0,
            currentVideoId: "v0",
            progress: 0,
            duration: 180,
            schemaVersion: 1
        )

        let restored = self.playerService.restoreQueueFromPersistence()

        #expect(restored)
        #expect(self.playerService.queue.count == 2)
    }

    @Test("restoreQueueFromPersistence refuses a session from a newer, unsupported schema version")
    func refusesNewerSchemaSession() throws {
        defer { Self.clearPersistenceKeys() }

        let songs = self.makeSongs(count: 2)
        try Self.writeSessionBlob(
            queue: songs,
            currentIndex: 0,
            currentVideoId: "v0",
            progress: 0,
            duration: 180,
            schemaVersion: 999
        )
        // No legacy keys present, so the fallback finds nothing and restore reports failure rather
        // than mis-applying a session shaped by a future build.
        UserDefaults.standard.removeObject(forKey: Self.savedQueueKey)
        UserDefaults.standard.removeObject(forKey: Self.savedQueueIndexKey)

        let restored = self.playerService.restoreQueueFromPersistence()

        #expect(!restored)
        #expect(self.playerService.queue.isEmpty)
    }

    // Writes a PersistedPlaybackSession-shaped JSON blob to the session UserDefaults key. The
    // struct is private, so the blob is assembled by encoding the queue and merging the scalar
    // fields (optionally omitting schemaVersion to emulate a pre-versioning session).
    // swiftlint:disable:next function_parameter_count
    private static func writeSessionBlob(
        queue: [Song],
        currentIndex: Int,
        currentVideoId: String,
        progress: Double,
        duration: Double,
        schemaVersion: Int?
    ) throws {
        let queueData = try JSONEncoder().encode(queue)
        let queueJSON = try JSONSerialization.jsonObject(with: queueData)

        var session: [String: Any] = [
            "queue": queueJSON,
            "currentIndex": currentIndex,
            "currentVideoId": currentVideoId,
            "progress": progress,
            "duration": duration,
        ]
        if let schemaVersion {
            session["schemaVersion"] = schemaVersion
        }

        let sessionData = try JSONSerialization.data(withJSONObject: session)
        UserDefaults.standard.set(sessionData, forKey: Self.savedPlaybackSessionKey)
    }
}
