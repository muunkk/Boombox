import SwiftUI

// MARK: - MenuBarPlayerView

/// Compact now-playing controller shown inside the menu bar popover.
/// Layout intentionally mirrors Apple's native Now Playing menu extra:
/// artwork on the left, title/artist on the right, scrubber underneath,
/// and centered previous / play-pause / next controls at the bottom.
struct MenuBarPlayerView: View {
    private static let brandAccent = PackageResourceLookup.brandAccent
    private static let popoverWidth: CGFloat = 320

    @Environment(PlayerService.self) private var playerService

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    @State private var formattedProgress: String = "0:00"
    @State private var formattedRemaining: String = "-0:00"
    @State private var lastProgressSecond: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.scrubber
            self.controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.popoverWidth)
        .onAppear {
            self.syncFormattedTimes(progress: self.playerService.progress)
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
        }
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

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 28) {
            Spacer(minLength: 0)

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

            Spacer(minLength: 0)
        }
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
