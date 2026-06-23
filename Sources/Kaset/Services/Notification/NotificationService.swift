import Foundation
import UserNotifications

/// Posts silent local notifications when the current track changes.
@MainActor
final class NotificationService {
    private let playerService: PlayerService
    private let settingsManager: SettingsManager
    private let logger = DiagnosticsLogger.notification
    // swiftformat:disable modifierOrder
    /// Task for the system authorization prompt, cancelled in deinit.
    /// nonisolated(unsafe) required for deinit access; Swift 6.2 warning is expected.
    nonisolated(unsafe) private var authorizationTask: Task<Void, Never>?
    /// Whether change observation is active. Drives the re-registering
    /// `withObservationTracking` loop and stops it when set to `false`.
    /// nonisolated(unsafe) required for deinit access; Swift 6.2 warning is expected.
    nonisolated(unsafe) private var isObservingFlag = false
    // swiftformat:enable modifierOrder
    /// Tracks the last notified track to prevent duplicate notifications.
    /// Internal for testing.
    private(set) var lastNotifiedTrackId: String?

    /// Previous track snapshot, used to detect track changes across observations.
    private var previousTrack: Song?
    /// Previous playback state snapshot, used to detect playback start.
    private var previousIsPlaying = false

    init(playerService: PlayerService, settingsManager: SettingsManager = .shared) {
        self.playerService = playerService
        self.settingsManager = settingsManager
        self.requestAuthorization()
        self.startObserving()
    }

    deinit {
        isObservingFlag = false
        authorizationTask?.cancel()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        // UNUserNotificationCenter crashes without an app bundle (e.g., unit/performance tests)
        guard Bundle.main.bundleIdentifier != nil, !UITestConfig.isRunningUnitTests else { return }
        self.authorizationTask = Task { @MainActor [weak self] in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert])
                self?.logger.info("Notification authorization: \(granted)")
            } catch {
                self?.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Observation

    private func startObserving() {
        self.isObservingFlag = true
        // Seed the playback baseline so a track that is already playing at
        // startup isn't treated as a "playback just started" event.
        self.previousIsPlaying = self.playerService.isPlaying
        self.registerObservation()
    }

    /// Registers a single `withObservationTracking` pass over the player's
    /// `currentTrack`/`isPlaying`, evaluates whether to notify, then re-registers
    /// on the next change. This replaces the previous 500ms polling loop so
    /// notifications are driven by actual state transitions rather than a timer.
    private func registerObservation() {
        guard self.isObservingFlag else { return }
        withObservationTracking {
            // Read both tracked properties so the observer fires on either change.
            // `isPlaying` is derived from `state`, so reading it registers `state`.
            let track = self.playerService.currentTrack
            let isPlaying = self.playerService.isPlaying
            self.evaluate(track: track, isPlaying: isPlaying)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.registerObservation()
            }
        }
    }

    /// Evaluates the current track/playback snapshot and posts a notification
    /// when active playback starts for a new, fully resolved track. Updates the
    /// previous-state snapshot used for the next evaluation.
    private func evaluate(track: Song?, isPlaying: Bool) {
        defer {
            self.previousTrack = track
            self.previousIsPlaying = isPlaying
        }

        guard let track,
              track.id != self.lastNotifiedTrackId,
              track.title != "Loading..."
        else { return }

        let trackChanged = track.id != self.previousTrack?.id
        let playbackJustStarted = isPlaying && !self.previousIsPlaying

        guard isPlaying, trackChanged || playbackJustStarted else { return }

        self.lastNotifiedTrackId = track.id
        Task { @MainActor [weak self] in
            await self?.postTrackNotification(track)
        }
    }

    // MARK: - Notification

    private func postTrackNotification(_ track: Song) async {
        // UNUserNotificationCenter crashes without an app bundle (e.g., unit/performance tests)
        guard Bundle.main.bundleIdentifier != nil, !UITestConfig.isRunningUnitTests else { return }
        // Check if notifications are enabled in settings
        guard self.settingsManager.showNowPlayingNotifications else {
            self.logger.debug("Notifications disabled in settings, skipping: \(track.title)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = track.artistsDisplay.isEmpty ? "Unknown Artist" : track.artistsDisplay
        content.sound = nil // Silent notification

        let request = UNNotificationRequest(
            identifier: "track-change-\(track.id)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            self.logger.debug("Posted notification for: \(track.title)")
        } catch {
            self.logger.error("Failed to post notification: \(error.localizedDescription)")
        }
    }

    /// Whether change observation is actively running.
    var isObserving: Bool {
        self.isObservingFlag
    }

    func stopObserving() {
        self.isObservingFlag = false
    }
}
