import WebKit

// MARK: - SingletonPlayerWebView

/// Manages a single WebView instance for the entire app lifetime.
/// This ensures there's only ever ONE WebView playing audio.
///
/// Extensions provide:
/// - Playback controls (SingletonPlayerWebView+PlaybackControls.swift)
/// - Observer script (SingletonPlayerWebView+ObserverScript.swift)
@MainActor
final class SingletonPlayerWebView {
    static let shared = SingletonPlayerWebView()

    private(set) var webView: WKWebView?
    var currentVideoId: String?
    var coordinator: Coordinator?
    let logger = DiagnosticsLogger.player

    /// Current display mode for the WebView.
    enum DisplayMode {
        case hidden // 1x1 for audio-only
        case miniPlayer // 160x90 toast
        case video // Full size in video window
    }

    /// How `loadVideo` behaves when Swift already tracks a `videoId` (repeat-one vs queue drift recovery).
    enum VideoLoadStrategy: Equatable {
        /// Skip navigation when `videoId` matches `currentVideoId`.
        case standard
        /// Same `videoId` as tracked: `seek(0)` + play only (fast). Different id: full watch URL load.
        case preferInPlaceWhenSameVideoId
        /// Same `videoId` as tracked: full `webView.load` (DOM out of sync with Swift). Different id: full load.
        case forceFullPageWhenSameVideoId
    }

    var displayMode: DisplayMode = .hidden
    private var mediaControlUsesNextPrev: Bool

    /// Tracks if lyrics high-frequency polling should be active
    /// Used to restore polling after full-page navigation
    var isLyricsPollActive = false

    private init() {
        self.mediaControlUsesNextPrev = SettingsManager.shared.mediaControlStyle == .nextPreviousTrack
    }

    /// Get or create the singleton WebView.
    func getWebView(
        webKitManager: WebKitManager,
        playerService: PlayerService
    ) -> WKWebView {
        if let existing = webView {
            return existing
        }

        self.logger.info("Creating singleton WebView")

        // Create coordinator
        let coordinator = Coordinator(playerService: playerService)
        self.coordinator = coordinator

        let configuration = webKitManager.createWebViewConfiguration()

        // Add script message handler
        configuration.userContentController.add(coordinator, name: "singletonPlayer")

        // Note: We do NOT inject a static volume init script here because the volume
        // may change between WebView creation and page loads. Instead, we:
        // 1. Set __kasetTargetVolume in loadVideo() before loading a new page
        // 2. Update it in didFinish after each page load completes
        // This ensures we always use the CURRENT volume, not a stale value.

        // Keep the page preference in sync before any page script reads localStorage.
        let mediaControlBootstrapScript = WKUserScript(
            source: self.mediaControlBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(mediaControlBootstrapScript)

        // Keep the embedded YouTube Music player audio-only by suppressing the Song/Video switcher.
        let audioOnlyScript = WKUserScript(
            source: Self.audioOnlyPlaybackScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(audioOnlyScript)

        // Inject mediaSession override at document end without allowing duplicate RAF loops.
        let mediaOverrideScript = WKUserScript(
            source: Self.mediaControlOverrideScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(mediaOverrideScript)

        // Inject observer script (at document end)
        let script = WKUserScript(
            source: Self.observerScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = self.coordinator
        newWebView.customUserAgent = WebKitManager.userAgent

        #if DEBUG
            newWebView.isInspectable = true
        #endif

        self.webView = newWebView
        return newWebView
    }

    /// Ensures the WebView is in the given container's view hierarchy.
    func ensureInHierarchy(container: NSView) {
        guard let webView, webView.superview !== container else { return }
        webView.removeFromSuperview()
        container.addSubview(webView)

        // Use autoresizing to match container size
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
    }

    /// Starts high frequency polling for synced lyrics
    func startLyricsPoll() {
        self.isLyricsPollActive = true
        self.webView?.evaluateJavaScript("if (window.startLyricsPoll) { window.startLyricsPoll(); }")
    }

    /// Stops high frequency polling for synced lyrics
    func stopLyricsPoll() {
        self.isLyricsPollActive = false
        self.webView?.evaluateJavaScript("if (window.stopLyricsPoll) { window.stopLyricsPoll(); }")
    }

    /// Load a video, stopping any currently playing audio first.
    /// Note: Full page navigation destroys the video element; same-id restarts use ``restartInPlaceFromBeginning()`` when possible.
    /// AirPlay connections will be lost on full navigation but the auto-reconnect picker will appear.
    func loadVideo(videoId: String, strategy: VideoLoadStrategy = .standard) {
        guard let webView else {
            self.logger.error("loadVideo called but webView is nil")
            return
        }

        let previousVideoId = self.currentVideoId

        switch strategy {
        case .standard:
            if videoId == previousVideoId {
                self.logger.debug("Video \(videoId) already loaded, skipping")
                return
            }
        case .preferInPlaceWhenSameVideoId:
            if videoId == previousVideoId {
                self.logger.debug("In-place restart for \(videoId) (same id — avoid full page reload)")
                self.restartInPlaceFromBeginning()
                return
            }
        case .forceFullPageWhenSameVideoId:
            if videoId == previousVideoId {
                self.logger.info("Force full navigation for \(videoId) (DOM/WebView resync)")
            }
        }

        if videoId != previousVideoId {
            self.logger.info("Loading video: \(videoId) (was: \(previousVideoId ?? "none"))")
        }

        // Update currentVideoId immediately to prevent duplicate loads
        self.currentVideoId = videoId

        // Get current volume from PlayerService via coordinator
        let currentVolume = self.coordinator?.playerService.volume ?? 1.0
        self.logger.info("Will apply volume \(currentVolume) after page load")

        // Stop current playback first, then load new video
        guard let urlToLoad = URL(string: "https://music.youtube.com/watch?v=\(videoId)") else {
            self.logger.error("Failed to build watch URL for videoId: \(videoId, privacy: .public)")
            return
        }
        webView.evaluateJavaScript("document.querySelector('video')?.pause()") { [weak self] _, _ in
            guard let self, let webView = self.webView else { return }

            // Set target volume BEFORE loading so it's ready when video element appears
            let setTargetScript = "window.__kasetTargetVolume = \(currentVolume);"
            webView.evaluateJavaScript(setTargetScript, completionHandler: nil)

            webView.load(URLRequest(url: urlToLoad))
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let playerService: PlayerService

        init(playerService: PlayerService) {
            self.playerService = playerService
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            let observedVideoId: String? = if let videoId = body["videoId"] as? String, !videoId.isEmpty {
                videoId
            } else {
                nil
            }

            if type == "TRACK_ENDED" {
                Task { @MainActor in
                    await self.playerService.handleTrackEnded(observedVideoId: observedVideoId)
                }
                return
            }

            if type == "REMOTE_NEXT" {
                Task { @MainActor in
                    await self.playerService.next()
                }
                return
            }

            if type == "REMOTE_PREVIOUS" {
                Task { @MainActor in
                    await self.playerService.previous()
                }
                return
            }

            // Handle AirPlay status updates
            if type == "AIRPLAY_STATUS" {
                let isConnected = body["isConnected"] as? Bool ?? false
                let wasRequested = body["wasRequested"] as? Bool ?? false

                Task { @MainActor in
                    self.playerService.updateAirPlayStatus(
                        isConnected: isConnected,
                        wasRequested: wasRequested
                    )
                }
                return
            }

            // Handle high frequency lyrics time updates
            if type == "LYRICS_TIME" {
                if let time = body["time"] as? Double {
                    Task { @MainActor in
                        self.playerService.currentTimeMs = Int(time * 1000)
                    }
                }
                return
            }

            guard type == "STATE_UPDATE" else { return }

            let isPlaying = body["isPlaying"] as? Bool ?? false
            let progress = body["progress"] as? Int ?? 0
            let duration = body["duration"] as? Int ?? 0
            let title = body["title"] as? String ?? ""
            let artist = body["artist"] as? String ?? ""
            let thumbnailUrl = body["thumbnailUrl"] as? String ?? ""
            let trackChanged = body["trackChanged"] as? Bool ?? false
            let likeStatusString = body["likeStatus"] as? String ?? "INDIFFERENT"

            // Parse like status
            let likeStatus: LikeStatus = switch likeStatusString {
            case "LIKE":
                .like
            case "DISLIKE":
                .dislike
            default:
                .indifferent
            }

            Task { @MainActor in
                self.playerService.updatePlaybackState(
                    isPlaying: isPlaying,
                    progress: Double(progress),
                    duration: Double(duration)
                )

                // Update like status only when track changes (initial state)
                if trackChanged {
                    self.playerService.updateLikeStatus(likeStatus)
                }

                // Repeat-one must keep enforcing queue/current song even if WebView doesn't flag `trackChanged`
                // for a transient autoplay swap. In other modes, keep the existing trackChanged gate.
                let shouldReconcileMetadata = (trackChanged || self.playerService.repeatMode == .one)
                    && (observedVideoId != nil || !title.isEmpty)

                if shouldReconcileMetadata {
                    self.playerService.updateTrackMetadata(
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl,
                        videoId: observedVideoId
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DiagnosticsLogger.player.info(
                "Singleton WebView finished loading: \(webView.url?.absoluteString ?? "nil")"
            )

            // Apply the current volume when page finishes loading
            // This is critical because YouTube may set its own default volume
            let savedVolume = self.playerService.volume
            let applyVolumeScript = """
                (function() {
                    try {
                        const volume = \(savedVolume);
                        window.__kasetTargetVolume = volume;
                        window.__kasetIsSettingVolume = true;

                        const video = document.querySelector('video');
                        if (video) {
                            video.volume = volume;
                        }

                        // Sync YouTube's internal player APIs if ready
                        const ytVolume = Math.round(volume * 100);
                        const player = document.querySelector('ytmusic-player');
                        if (player && player.playerApi && typeof player.playerApi.setVolume === 'function') {
                            player.playerApi.setVolume(ytVolume);
                        }
                        const moviePlayer = document.getElementById('movie_player');
                        if (moviePlayer && typeof moviePlayer.setVolume === 'function') {
                            moviePlayer.setVolume(ytVolume);
                        }

                        setTimeout(() => { window.__kasetIsSettingVolume = false; }, 100);
                        return video ? 'applied' : 'no-video-yet';
                    } catch (e) {
                         return 'error: ' + e;
                    }
                })();
            """
            webView.evaluateJavaScript(applyVolumeScript) { result, error in
                if let error {
                    DiagnosticsLogger.player.error(
                        "Failed to apply saved volume \(savedVolume): \(error.localizedDescription)"
                    )
                } else if let resultString = result as? String {
                    DiagnosticsLogger.player.debug("Volume apply result: \(resultString)")
                }

                // Restore lyrics high-frequency polling if it was active
                if SingletonPlayerWebView.shared.isLyricsPollActive {
                    SingletonPlayerWebView.shared.startLyricsPoll()
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // WebView content process crashed - attempt recovery
            DiagnosticsLogger.player.error("Singleton WebView content process terminated, attempting recovery")

            // Get the current video ID before recovering
            let currentVideoId = SingletonPlayerWebView.shared.currentVideoId

            // Reflect the interruption in user-visible state. The JS bridge is dead until recovery
            // completes, so no STATE_UPDATE would otherwise clear the stale `.playing`/frozen-progress
            // UI. The observer flips this back to `.playing`/`.paused` once the recovered page reports.
            self.playerService.state = .loading

            if let videoId = currentVideoId {
                // Single recovery navigation. Previously an eager `webView.reload()` raced the delayed
                // `loadVideo`, causing a double-load/flash; rely on one watch-URL load instead.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    // Reset currentVideoId so the load isn't skipped by loadVideo's dedup guard.
                    SingletonPlayerWebView.shared.currentVideoId = nil
                    SingletonPlayerWebView.shared.loadVideo(videoId: videoId)
                }
            } else {
                // No tracked video to reload; just bring the crashed content process back.
                webView.reload()
            }
        }
    }
}

// MARK: - SingletonPlayerWebView Media Controls

extension SingletonPlayerWebView {
    /// Updates the current page and the bootstrap state used by future page loads.
    func setMediaControlStyle(useNextPrev: Bool) {
        self.mediaControlUsesNextPrev = useNextPrev

        guard let webView = self.webView else { return }
        let script = Self.mediaControlStyleSyncScript(useNextPrev: useNextPrev)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func mediaControlBootstrapScript() -> String {
        Self.mediaControlStyleBootstrapScript(useNextPrev: self.mediaControlUsesNextPrev)
    }

    static func mediaControlStyleBootstrapScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        return """
            (function() {
                try {
                    localStorage.setItem('kasetUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__kasetUseNextPrev = \(jsBoolean);
            })();
        """
    }

    static func mediaControlStyleSyncScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        let restoreSeekHandlers = if useNextPrev {
            ""
        } else {
            """
                try {
                    var ms = navigator.mediaSession;
                    ms.setActionHandler('nexttrack', null);
                    ms.setActionHandler('previoustrack', null);
                    ms.setActionHandler('seekforward', function(d) {
                        var v = document.querySelector('video');
                        if (v) v.currentTime = Math.min(v.duration,
                            v.currentTime + ((d && d.seekOffset) || 15));
                    });
                    ms.setActionHandler('seekbackward', function(d) {
                        var v = document.querySelector('video');
                        if (v) v.currentTime = Math.max(0,
                            v.currentTime - ((d && d.seekOffset) || 15));
                    });
                } catch (e) {}
            """
        }

        return """
            (function() {
                try {
                    localStorage.setItem('kasetUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__kasetUseNextPrev = \(jsBoolean);
                if (typeof window.__kasetRefreshMediaControlStyle === 'function') {
                    window.__kasetRefreshMediaControlStyle();
                }
                \(restoreSeekHandlers)
            })();
        """
    }

    static var mediaControlOverrideScript: String {
        """
        (function() {
            if (typeof window.__kasetUseNextPrev !== 'boolean') {
                try {
                    window.__kasetUseNextPrev =
                        localStorage.getItem('kasetUseNextPrev') === 'true';
                } catch (e) {
                    window.__kasetUseNextPrev = false;
                }
            }

            var overrideFrameId = null;

            function applyOverride() {
                if (!window.__kasetUseNextPrev) {
                    return;
                }
                try {
                    var ms = navigator.mediaSession;
                    ms.setActionHandler('seekforward', null);
                    ms.setActionHandler('seekbackward', null);
                    ms.setActionHandler('nexttrack', function() {
                        window.webkit.messageHandlers.singletonPlayer
                            .postMessage({ type: 'REMOTE_NEXT' });
                    });
                    ms.setActionHandler('previoustrack', function() {
                        window.webkit.messageHandlers.singletonPlayer
                            .postMessage({ type: 'REMOTE_PREVIOUS' });
                    });
                } catch (e) {}
            }

            function scheduleOverrideLoop() {
                if (overrideFrameId !== null || !window.__kasetUseNextPrev) {
                    return;
                }

                overrideFrameId = requestAnimationFrame(function() {
                    overrideFrameId = null;
                    if (!window.__kasetUseNextPrev) {
                        return;
                    }
                    applyOverride();
                    scheduleOverrideLoop();
                });
            }

            window.__kasetRefreshMediaControlStyle = function() {
                applyOverride();
                scheduleOverrideLoop();
            };

            window.__kasetRefreshMediaControlStyle();

            // Re-apply on video events where YouTube re-registers handlers.
            function attachVideoOverride() {
                var v = document.querySelector('video');
                if (!v || v.__kasetOverrideAttached) return;
                v.__kasetOverrideAttached = true;
                ['playing','loadedmetadata','loadeddata','canplay','seeked']
                    .forEach(function(e) { v.addEventListener(e, applyOverride); });
            }

            attachVideoOverride();
            new MutationObserver(attachVideoOverride)
                .observe(document.documentElement, {childList:true, subtree:true});
        })();
        """
    }
}
