import SwiftUI

// MARK: - PlayerBar

/// Player bar shown at the bottom of the content area, styled like Apple Music with Liquid Glass.
@available(macOS 26.0, *)
struct PlayerBar: View {
    private static let brandAccent = PackageResourceLookup.brandAccent

    @Environment(PlayerService.self) private var playerService

    /// Namespace for glass effect morphing and unioning.
    @Namespace private var playerNamespace

    @State private var settings = SettingsManager.shared

    @State private var isHovering = false

    /// Local seek value for smooth slider dragging without network calls on every change.
    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    /// Local volume value for smooth slider dragging.
    @State private var volumeValue: Double = 1.0
    @State private var isAdjustingVolume = false
    @State private var audioOutput = AudioOutputDeviceInfo.unknown

    /// Cached formatted progress string to avoid repeated formatting.
    @State private var formattedProgress: String = "0:00"
    @State private var formattedRemaining: String = "-0:00"
    /// Last integer second of progress to reduce string formatting frequency.
    @State private var lastProgressSecond: Int = -1

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                // Left section: Playback controls
                self.playbackControls

                Spacer()

                // Center section: track info or seek bar.
                self.centerSection

                Spacer()

                // Right section: Volume control
                self.volumeControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("playerBar", in: self.playerNamespace)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isHovering = hovering
            }
        }
        .background {
            // Keyboard shortcuts for media controls
            Group {
                // Space: Play/Pause
                Button("") {
                    Task { await self.playerService.playPause() }
                }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)

                // Command + Right Arrow: Next track
                Button("") {
                    Task { await self.playerService.next() }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .opacity(0)

                // Command + Left Arrow: Previous track
                Button("") {
                    Task { await self.playerService.previous() }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .opacity(0)

                // Command + Up Arrow: Volume up
                Button("") {
                    Task {
                        await self.playerService.setVolume(
                            VolumeCurve.steppedOutputVolume(
                                fromOutputVolume: self.playerService.volume,
                                bySliderStep: 0.1
                            )
                        )
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .opacity(0)

                // Command + Down Arrow: Volume down
                Button("") {
                    Task {
                        await self.playerService.setVolume(
                            VolumeCurve.steppedOutputVolume(
                                fromOutputVolume: self.playerService.volume,
                                bySliderStep: -0.1
                            )
                        )
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .opacity(0)
            }
        }
        .onChange(of: self.playerService.progress) { _, newValue in
            // Sync local seek value when not actively seeking
            if !self.isSeeking, self.playerService.duration > 0 {
                self.seekValue = newValue / self.playerService.duration
            }
            // Only update formatted strings when the second changes to reduce Text view updates
            let currentSecond = Int(newValue)
            if currentSecond != self.lastProgressSecond {
                self.lastProgressSecond = currentSecond
                self.formattedProgress = self.formatTime(newValue)
                self.formattedRemaining = "-\(self.formatTime(self.playerService.duration - newValue))"
            }
        }
        .onChange(of: self.playerService.volume) { _, newValue in
            // Sync local volume value when not actively adjusting
            if !self.isAdjustingVolume {
                self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: newValue)
            }
        }
        .onAppear {
            // Sync local volume value from saved state on initial load
            self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: self.playerService.volume)
            self.audioOutput = AudioOutputDeviceInfo.currentDefaultOutput()
        }
        .task {
            await self.refreshAudioOutputLoop()
        }
    }

    // MARK: - Center Section

    private var centerSection: some View {
        ZStack {
            // Error state display with retry option
            if case let .error(message) = playerService.state {
                self.errorView(message: message)
            } else {
                if self.shouldShowSeekBar {
                    self.seekBarView
                        .transition(.opacity)
                } else {
                    self.trackInfoView
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: 400)
    }

    private var shouldShowSeekBar: Bool {
        self.playerService.currentTrack != nil
            && (self.settings.showSidebarNowPlayingPanel || self.isHovering || self.isSeeking)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))

            Text(message)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    if let track = playerService.currentTrack {
                        await self.playerService.play(song: track)
                    }
                }
            } label: {
                Text("Retry", comment: "Button to retry failed playback")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(.capsule)
        }
    }

    // MARK: - Track Info View

    private var trackInfoView: some View {
        self.trackInfoContent
        .accessibilityLabel(self.nowPlayingAccessibilityLabel)
        .allowsHitTesting(false)
    }

    private var trackInfoContent: some View {
        HStack(spacing: 10) {
            // Thumbnail
            if let track = self.playerService.currentTrack {
                SongThumbnailView(song: track, size: 36, cornerRadius: 4)
                    .accessibilityIdentifier(AccessibilityID.PlayerBar.thumbnail)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .overlay {
                        CassetteIcon(size: 20)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
            }

            // Track info
            if let track = self.playerService.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier(AccessibilityID.PlayerBar.trackTitle)

                    Text(track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.PlayerBar.trackArtist)
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    private var nowPlayingAccessibilityLabel: String {
        guard let track = self.playerService.currentTrack else {
            return String(localized: "No song playing")
        }

        let artist = track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay
        return String(localized: "Now playing: \(track.title) by \(artist)")
    }

    // MARK: - Seek Bar View (replaces track info on hover)

    private var seekBarView: some View {
        HStack(spacing: 10) {
            // Elapsed time - use cached formatted string when not seeking
            Text(self.isSeeking ? self.formatTime(self.seekValue * self.playerService.duration) : self.formattedProgress)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 45, alignment: .trailing)
                .monospacedDigit()

            // Seek slider
            Slider(value: self.$seekValue, in: 0 ... 1) { editing in
                if editing {
                    // User started dragging
                    self.isSeeking = true
                } else {
                    // User finished dragging - perform seek
                    self.performSeek()
                }
            }
            .controlSize(.small)
            .tint(Self.brandAccent)
            .disabled(self.playerService.duration <= 0)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.seekSlider)

            // Remaining time - use cached formatted string when not seeking
            Text(self.isSeeking ? "-\(self.formatTime(self.playerService.duration - self.seekValue * self.playerService.duration))" : self.formattedRemaining)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 45, alignment: .leading)
                .monospacedDigit()
        }
    }

    /// Performs the actual seek operation after slider interaction ends.
    private func performSeek() {
        guard self.isSeeking else { return }
        guard self.playerService.currentTrack != nil, self.playerService.duration > 0 else {
            self.isSeeking = false
            self.seekValue = 0
            return
        }

        let seekTime = self.seekValue * self.playerService.duration
        Task {
            await self.playerService.seek(to: seekTime)
            self.isSeeking = false
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            // Shuffle
            Button {
                HapticService.toggle()
                self.playerService.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.shuffleEnabled ? .red : .primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(String(localized: "Shuffle"))
            .accessibilityValue(self.playerService.shuffleEnabled ? String(localized: "On") : String(localized: "Off"))

            self.nowPlayingPanelToggleButton

            // Previous
            Button {
                HapticService.playback()
                Task {
                    await self.playerService.previous()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(String(localized: "Previous track"))

            // Play/Pause
            Button {
                HapticService.playback()
                Task {
                    await self.playerService.playPause()
                }
            } label: {
                Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .glassEffectID("playPause", in: self.playerNamespace)
            .accessibilityLabel(self.playerService.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            // Next
            Button {
                HapticService.playback()
                Task {
                    await self.playerService.next()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(String(localized: "Next track"))

            // Repeat
            Button {
                HapticService.toggle()
                self.playerService.cycleRepeatMode()
            } label: {
                Image(systemName: self.repeatIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.repeatMode != .off ? .red : .primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(String(localized: "Repeat"))
            .accessibilityValue(self.repeatAccessibilityValue)
        }
    }

    private var repeatIcon: String {
        switch self.playerService.repeatMode {
        case .off, .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }

    private var repeatAccessibilityValue: String {
        switch self.playerService.repeatMode {
        case .off:
            String(localized: "Off")
        case .all:
            String(localized: "All")
        case .one:
            String(localized: "One")
        }
    }

    // MARK: - Volume Control

    private var volumeControl: some View {
        HStack(spacing: 8) {
            // Like/Dislike/Library actions
            self.actionButtons

            // AirPlay button
            Button {
                HapticService.toggle()
                self.playerService.showAirPlayPicker()
            } label: {
                Image(systemName: self.audioOutputIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.isAirPlayConnected ? .red : .primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.airplayButton)
            .accessibilityLabel(
                self.playerService.isAirPlayConnected
                    ? String(localized: "AirPlay Connected")
                    : String(localized: "Audio Output: \(self.audioOutput.accessibilityName)")
            )
            .disabled(self.playerService.currentTrack == nil)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Image(systemName: self.volumeIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 18)

            // Volume slider with immediate updates
            Slider(value: self.$volumeValue, in: 0 ... 1) { editing in
                if editing {
                    // User started dragging
                    self.isAdjustingVolume = true
                } else {
                    // User finished dragging/clicking - apply volume change
                    self.isAdjustingVolume = false
                    // Always apply volume when interaction ends to ensure WebView is synced
                    Task {
                        await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: self.volumeValue))
                    }
                }
            }
            .frame(width: 80)
            .controlSize(.small)
            .tint(Self.brandAccent)
            .onChange(of: self.volumeValue) { oldValue, newValue in
                // Apply volume changes in real-time during dragging for immediate feedback
                if self.isAdjustingVolume {
                    // Haptic feedback at slider boundaries
                    if (oldValue > 0 && newValue == 0) || (oldValue < 1 && newValue == 1) {
                        HapticService.sliderBoundary()
                    }
                    Task {
                        await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: newValue))
                    }
                }
            }
        }
    }

    // MARK: - Now Playing Panel Toggle

    private var nowPlayingPanelToggleButton: some View {
        Button {
            HapticService.toggle()
            withAnimation(AppAnimation.standard) {
                self.settings.showSidebarNowPlayingPanel.toggle()
            }
        } label: {
            Image(systemName: self.settings.showSidebarNowPlayingPanel ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(self.settings.showSidebarNowPlayingPanel ? .red : .primary.opacity(0.85))
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressable)
        .glassEffectID("nowPlayingPanel", in: self.playerNamespace)
        .accessibilityIdentifier(AccessibilityID.PlayerBar.nowPlayingPanelToggle)
        .accessibilityLabel(String(localized: "Now Playing Panel"))
        .accessibilityValue(self.settings.showSidebarNowPlayingPanel ? String(localized: "Shown") : String(localized: "Hidden"))
        .help(String(localized: "Now Playing Panel"))
    }

    // MARK: - Action Buttons (Like/Lyrics/Queue)

    private var actionButtons: some View {
        @Bindable var player = self.playerService

        return HStack(spacing: 12) {
            // Like button
            Button {
                HapticService.toggle()
                self.playerService.likeCurrentTrack()
            } label: {
                Image(systemName: self.playerService.currentTrackLikeStatus == .like
                    ? "hand.thumbsup.fill"
                    : "hand.thumbsup")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.currentTrackLikeStatus == .like ? .red : .primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .symbolEffect(.bounce, value: self.playerService.currentTrackLikeStatus == .like)
            .accessibilityLabel(String(localized: "Like"))
            .accessibilityValue(self.playerService.currentTrackLikeStatus == .like ? String(localized: "Liked") : String(localized: "Not liked"))
            .disabled(self.playerService.currentTrack == nil)

            // Lyrics button
            Button {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    player.showLyrics.toggle()
                }
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.showLyrics ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.pressable)
            .glassEffectID("lyrics", in: self.playerNamespace)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.lyricsButton)
            .accessibilityLabel(String(localized: "Lyrics"))
            .accessibilityValue(self.playerService.showLyrics ? String(localized: "Showing") : String(localized: "Hidden"))

            // Queue button
            Button {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    player.showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(self.playerService.showQueue ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.pressable)
            .glassEffectID("queue", in: self.playerNamespace)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.queueButton)
            .accessibilityLabel(String(localized: "Queue"))
            .accessibilityValue(self.playerService.showQueue ? String(localized: "Showing") : String(localized: "Hidden"))

        }
    }

    private var volumeIcon: String {
        let currentVolume = self.isAdjustingVolume ? VolumeCurve.outputVolume(forSliderValue: self.volumeValue) : self.playerService.volume
        if currentVolume == 0 {
            return "speaker.slash.fill"
        } else if currentVolume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    private var audioOutputIcon: String {
        self.audioOutput.systemImageName(fallbackVolumeIcon: self.volumeIcon)
    }

    private func refreshAudioOutputLoop() async {
        while !Task.isCancelled {
            self.audioOutput = AudioOutputDeviceInfo.currentDefaultOutput()
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    PlayerBar()
        .environment(PlayerService())
        .environment(WebKitManager.shared)
        .frame(width: 600)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
}
