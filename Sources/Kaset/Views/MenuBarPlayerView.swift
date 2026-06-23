import SwiftUI

// MARK: - MenuBarPlayerView

/// Compact now-playing controller shown inside the menu bar popover.
/// Layout intentionally mirrors Apple's native Now Playing menu extra:
/// artwork on the left, title/artist on the right, scrubber underneath,
/// and centered transport controls. A footer row exposes like / queue
/// toggles, and the queue list expands inline below the player.
struct MenuBarPlayerView: View {
    private static let brandAccent = PackageResourceLookup.brandAccent
    private static let popoverWidth: CGFloat = 340

    /// Closure that brings the main app window forward.
    let openApp: () -> Void

    @Environment(PlayerService.self) private var playerService

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    @State private var formattedProgress: String = "0:00"
    @State private var formattedRemaining: String = "-0:00"
    @State private var lastProgressSecond: Int = -1

    @State private var isQueueExpanded = false

    @State private var audioOutput = AudioOutputDeviceInfo.unknown
    @State private var availableAudioOutputs: [AudioOutputDeviceInfo] = []

    @State private var volumeValue: Double = 1.0
    @State private var isAdjustingVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.scrubber
            self.transport
            self.volumeRow
            self.footer

            // Snap the queue layout in/out instantly. NSPopover then animates
            // its frame to the new intrinsic content size, which looks
            // smoother than trying to tween a SwiftUI frame against the
            // popover's own resize.
            if self.isQueueExpanded {
                Divider()
                    .opacity(0.4)
                self.queueList
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.popoverWidth)
        .onAppear {
            self.syncFormattedTimes(progress: self.playerService.progress)
            self.refreshAudioOutputs()
            self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: self.playerService.volume)
        }
        .onChange(of: self.playerService.volume) { _, newValue in
            if !self.isAdjustingVolume {
                self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: newValue)
            }
        }
        .onChange(of: self.playerService.progress) { _, newValue in
            if !self.isSeeking, self.playerService.duration > 0 {
                self.seekValue = newValue / self.playerService.duration
            }
            let currentSecond = Int(newValue)
            if currentSecond != self.lastProgressSecond {
                self.lastProgressSecond = currentSecond
                self.syncFormattedTimes(progress: newValue)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            self.artwork

            VStack(alignment: .leading, spacing: 2) {
                if let track = self.playerService.currentTrack {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Boombox")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Nothing Playing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.audioOutputMenu

            Button {
                self.openApp()
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open Boombox"))
            .accessibilityLabel(String(localized: "Open Boombox"))
        }
    }

    private var audioOutputMenu: some View {
        Menu {
            if self.availableAudioOutputs.isEmpty {
                Text("No Output Devices")
            } else {
                ForEach(self.availableAudioOutputs) { output in
                    Button {
                        self.selectAudioOutput(output)
                    } label: {
                        if output.id == self.audioOutput.id, output.isSelectable {
                            Label(output.accessibilityName, systemImage: "checkmark")
                        } else {
                            Text(output.accessibilityName)
                        }
                    }
                    .disabled(!output.isSelectable)
                }
            }

            Divider()

            Button("Refresh Devices") {
                self.refreshAudioOutputs()
            }
        } label: {
            Image(systemName: self.audioOutput.pickerButtonSystemImageName())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(self.audioOutput.isAirPods ? .red : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Audio Output"))
        .accessibilityLabel(String(localized: "Audio Output"))
    }

    @ViewBuilder
    private var artwork: some View {
        if let track = self.playerService.currentTrack {
            SongThumbnailView(song: track, size: 56, cornerRadius: 6)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay {
                    CassetteIcon(size: 28)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 56, height: 56)
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: self.$seekValue, in: 0 ... 1) { editing in
                if editing {
                    self.isSeeking = true
                } else {
                    self.performSeek()
                }
            }
            .controlSize(.mini)
            .tint(Self.brandAccent)
            .disabled(self.playerService.duration <= 0)

            HStack {
                Text(self.isSeeking ? self.formatTime(self.seekValue * self.playerService.duration) : self.formattedProgress)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(self.isSeeking
                    ? "-\(self.formatTime(max(self.playerService.duration - self.seekValue * self.playerService.duration, 0)))"
                    : self.formattedRemaining)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 22) {
            Spacer(minLength: 0)

            Button {
                HapticService.toggle()
                self.playerService.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.playerService.shuffleEnabled ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Shuffle"))
            .accessibilityLabel(String(localized: "Shuffle"))
            .accessibilityValue(self.playerService.shuffleEnabled ? String(localized: "On") : String(localized: "Off"))

            Button {
                HapticService.playback()
                Task {
                    await self.playerService.previous()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Previous track"))
            .disabled(!self.canControlPlayback)

            Button {
                HapticService.playback()
                Task {
                    await self.playerService.playPause()
                }
            } label: {
                Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.playerService.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
            .disabled(!self.canControlPlayback)

            Button {
                HapticService.playback()
                Task {
                    await self.playerService.next()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Next track"))
            .disabled(!self.canControlPlayback)

            Button {
                HapticService.toggle()
                self.playerService.cycleRepeatMode()
            } label: {
                Image(systemName: self.repeatIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.playerService.repeatMode != .off ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Repeat"))
            .accessibilityLabel(String(localized: "Repeat"))

            Spacer(minLength: 0)
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

    // MARK: - Volume

    private var volumeRow: some View {
        // Scroll-to-adjust is handled at the popover level by MenuBarController
        // so a scroll anywhere in the popover changes volume — not just over
        // the slider.
        HStack(spacing: 8) {
            Image(systemName: self.volumeIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .contentTransition(.symbolEffect(.replace))

            Slider(value: self.$volumeValue, in: 0 ... 1) { editing in
                if editing {
                    self.isAdjustingVolume = true
                } else {
                    self.isAdjustingVolume = false
                    Task {
                        await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: self.volumeValue))
                    }
                }
            }
            .controlSize(.mini)
            .tint(Self.brandAccent)
            .onChange(of: self.volumeValue) { _, newValue in
                if self.isAdjustingVolume {
                    Task {
                        await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: newValue))
                    }
                }
            }
        }
    }

    private var volumeIcon: String {
        let current = VolumeCurve.outputVolume(forSliderValue: self.volumeValue)
        if current == 0 {
            return "speaker.slash.fill"
        } else if current < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                HapticService.toggle()
                self.playerService.likeCurrentTrack()
            } label: {
                Image(systemName: self.playerService.currentTrackLikeStatus == .like
                    ? "hand.thumbsup.fill"
                    : "hand.thumbsup")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.playerService.currentTrackLikeStatus == .like ? .red : .primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: self.playerService.currentTrackLikeStatus == .like)
            .disabled(self.playerService.currentTrack == nil)
            .help(String(localized: "Like"))
            .accessibilityLabel(String(localized: "Like"))

            Spacer()

            Button {
                HapticService.toggle()
                withAnimation(.easeOut(duration: 0.2)) {
                    self.isQueueExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .medium))
                    Text(self.isQueueExpanded ? String(localized: "Hide Queue") : String(localized: "Show Queue"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(self.isQueueExpanded ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Queue"))
            .accessibilityValue(self.isQueueExpanded ? String(localized: "Showing") : String(localized: "Hidden"))
        }
    }

    // MARK: - Queue List

    private var queueList: some View {
        Group {
            if self.playerService.queue.isEmpty {
                Text("Queue is empty")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(self.playerService.queue.enumerated()), id: \.element.videoId) { index, song in
                            MenuBarQueueRow(
                                song: song,
                                isCurrent: index == self.playerService.currentIndex,
                                onPlay: {
                                    Task {
                                        await self.playerService.playFromQueue(at: index)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: self.queueListHeight)
            }
        }
    }

    /// Caps queue height at ~6 visible rows to keep the popover compact.
    private var queueListHeight: CGFloat {
        let rowHeight: CGFloat = 36
        let count = CGFloat(min(self.playerService.queue.count, 6))
        return max(count, 1) * rowHeight + 8
    }

    // MARK: - Helpers

    private var canControlPlayback: Bool {
        self.playerService.currentTrack != nil || self.playerService.pendingPlayVideoId != nil
    }

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

    private func syncFormattedTimes(progress: TimeInterval) {
        self.formattedProgress = self.formatTime(progress)
        let remaining = max(self.playerService.duration - progress, 0)
        self.formattedRemaining = "-\(self.formatTime(remaining))"
    }

    private func refreshAudioOutputs() {
        self.audioOutput = AudioOutputDeviceInfo.currentDefaultOutput()
        self.availableAudioOutputs = AudioOutputDeviceInfo.availableOutputDevices()
    }

    private func selectAudioOutput(_ output: AudioOutputDeviceInfo) {
        guard output.isSelectable else { return }
        if AudioOutputDeviceInfo.setDefaultOutput(output) {
            HapticService.success()
            self.refreshAudioOutputs()
        } else {
            HapticService.error()
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
}

// MARK: - MenuBarQueueRow

private struct MenuBarQueueRow: View {
    let song: Song
    let isCurrent: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 8) {
                SongThumbnailView(song: self.song, size: 28, cornerRadius: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(self.song.title)
                        .font(.system(size: 11, weight: self.isCurrent ? .semibold : .medium))
                        .foregroundStyle(self.isCurrent ? Color.red : .primary)
                        .lineLimit(1)

                    Text(self.song.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : self.song.artistsDisplay)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if self.isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(self.isHovering ? Color.primary.opacity(0.08) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovering = hovering
        }
    }
}
