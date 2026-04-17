import Foundation
import SwiftUI

// MARK: - FocusPlayerView

/// Full-window now-playing surface used by Focus Player mode.
@available(macOS 26.0, *)
struct FocusPlayerView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    var body: some View {
        ZStack {
            AccentBackground(imageURL: self.playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                self.header
                Spacer(minLength: 0)
                NowPlayingArtworkView(size: 320, cornerRadius: 12)
                NowPlayingTitleBlock(titleFont: .title2, artistFont: .title3)
                NowPlayingTransportControls(size: .large)
                Spacer(minLength: 0)
            }
            .padding(32)
        }
        .frame(minWidth: 900, minHeight: 600)
        .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayer)
    }

    private var header: some View {
        HStack {
            Text(PlayerPresentationMode.focus.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.playerPresentationMode.wrappedValue = .standard
                }
            } label: {
                Label("Return to Full App", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - CompactPlayerView

/// Compact same-window now-playing surface used by Small Player mode.
@available(macOS 26.0, *)
struct CompactPlayerView: View {
    private enum Layout {
        static let minimumSize = CGSize(width: 360, height: 540)
        static let idealSize = CGSize(width: 420, height: 640)
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 14
    }

    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = self.artworkSize(for: proxy.size)

            ZStack {
                AccentBackground(imageURL: self.playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL)
                    .ignoresSafeArea()

                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.22)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    self.header

                    Spacer(minLength: 4)

                    NowPlayingArtworkView(size: artworkSize, cornerRadius: 18)
                        .accessibilityHidden(self.playerService.currentTrack == nil)

                    Spacer(minLength: 8)

                    NowPlayingTitleBlock(titleFont: .title3, artistFont: .callout)

                    Spacer(minLength: 6)

                    NowPlayingProgressView()

                    Spacer(minLength: 10)

                    NowPlayingTransportControls(size: .regular)

                    Spacer(minLength: 10)

                    CompactPlayerActionRow()

                    Spacer(minLength: 6)

                    NowPlayingVolumeControl()
                }
                .padding(.horizontal, Self.Layout.horizontalPadding)
                .padding(.vertical, Self.Layout.verticalPadding)
            }
        }
        .frame(
            minWidth: Self.Layout.minimumSize.width,
            idealWidth: Self.Layout.idealSize.width,
            minHeight: Self.Layout.minimumSize.height,
            idealHeight: Self.Layout.idealSize.height
        )
        .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayer)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlayerPresentationMode.compact.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(self.playbackStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.playerPresentationMode.wrappedValue = .standard
                }
            } label: {
                Label("Back to Full App", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayerBackButton)
        }
    }

    private var playbackStateLabel: String {
        guard self.playerService.currentTrack != nil else {
            return String(localized: "Nothing Playing")
        }

        return self.playerService.isPlaying ? String(localized: "Playing") : String(localized: "Paused")
    }

    private func artworkSize(for availableSize: CGSize) -> CGFloat {
        min(max(availableSize.height * 0.38, 198), availableSize.width - 64, 292)
    }
}

// MARK: - NowPlayingTimeFormatter

enum NowPlayingTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - NowPlayingProgressView

/// Shared seek/progress control for now-playing presentation surfaces.
@available(macOS 26.0, *)
struct NowPlayingProgressView: View {
    private static let brandAccent = PackageResourceLookup.brandAccent

    @Environment(PlayerService.self) private var playerService

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: self.$seekValue, in: 0 ... 1) { editing in
                if editing {
                    self.isSeeking = true
                } else {
                    self.performSeek()
                }
            }
            .tint(Self.brandAccent)
            .disabled(self.playerService.currentTrack == nil || self.playerService.duration <= 0)
            .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayerSeekSlider)
            .accessibilityLabel(String(localized: "Playback position"))

            HStack {
                Text(self.elapsedText)
                Spacer()
                Text(self.remainingText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .onAppear {
            self.syncSeekValue()
        }
        .onChange(of: self.playerService.progress) { _, _ in
            self.syncSeekValue()
        }
        .onChange(of: self.playerService.duration) { _, _ in
            self.syncSeekValue()
        }
    }

    private var elapsedText: String {
        let progress = self.isSeeking ? self.seekValue * self.playerService.duration : self.playerService.progress
        return NowPlayingTimeFormatter.string(from: progress)
    }

    private var remainingText: String {
        let progress = self.isSeeking ? self.seekValue * self.playerService.duration : self.playerService.progress
        let remaining = max(0, self.playerService.duration - progress)
        return "-\(NowPlayingTimeFormatter.string(from: remaining))"
    }

    private func syncSeekValue() {
        guard !self.isSeeking else { return }

        if self.playerService.duration > 0 {
            self.seekValue = min(max(self.playerService.progress / self.playerService.duration, 0), 1)
        } else {
            self.seekValue = 0
        }
    }

    private func performSeek() {
        guard self.isSeeking else { return }

        let seekTime = self.seekValue * self.playerService.duration
        Task { @MainActor in
            await self.playerService.seek(to: seekTime)
            self.isSeeking = false
        }
    }
}

// MARK: - CompactPlayerActionRow

/// Secondary actions for Small Player mode.
@available(macOS 26.0, *)
struct CompactPlayerActionRow: View {
    @Environment(PlayerService.self) private var playerService

    var body: some View {
        HStack(spacing: 10) {
            CompactPlayerActionButton(
                title: String(localized: "Like"),
                systemImage: self.playerService.currentTrackLikeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                isActive: self.playerService.currentTrackLikeStatus == .like,
                accessibilityIdentifier: AccessibilityID.MainWindow.compactPlayerLikeButton
            ) {
                HapticService.toggle()
                self.playerService.likeCurrentTrack()
            }
            .disabled(self.playerService.currentTrack == nil)

            CompactPlayerActionButton(
                title: String(localized: "Lyrics"),
                systemImage: "quote.bubble",
                isActive: self.playerService.showLyrics,
                accessibilityIdentifier: AccessibilityID.MainWindow.compactPlayerLyricsButton
            ) {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    self.playerService.showLyrics.toggle()
                }
            }
            .disabled(self.playerService.currentTrack == nil)

            CompactPlayerActionButton(
                title: String(localized: "Queue"),
                systemImage: "list.bullet",
                isActive: self.playerService.showQueue,
                accessibilityIdentifier: AccessibilityID.MainWindow.compactPlayerQueueButton
            ) {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    self.playerService.showQueue.toggle()
                }
            }
            .disabled(self.playerService.currentTrack == nil)

            CompactPlayerActionButton(
                title: String(localized: "Output"),
                systemImage: "airplayaudio",
                isActive: self.playerService.isAirPlayConnected,
                accessibilityIdentifier: AccessibilityID.MainWindow.compactPlayerAirPlayButton
            ) {
                HapticService.toggle()
                self.playerService.showAirPlayPicker()
            }
            .disabled(self.playerService.currentTrack == nil)
        }
    }
}

// MARK: - CompactPlayerActionButton

/// Fixed-size lock-screen-style action button for compact mode.
@available(macOS 26.0, *)
struct CompactPlayerActionButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 4) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))

                Text(self.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 44)
        }
        .buttonStyle(.glass)
        .foregroundStyle(self.isActive ? Color.red : Color.primary)
        .accessibilityIdentifier(self.accessibilityIdentifier)
        .accessibilityLabel(self.title)
        .accessibilityValue(self.isActive ? String(localized: "On") : String(localized: "Off"))
    }
}

// MARK: - NowPlayingVolumeControl

/// Shared volume control for now-playing presentation surfaces.
@available(macOS 26.0, *)
struct NowPlayingVolumeControl: View {
    private static let brandAccent = PackageResourceLookup.brandAccent

    @Environment(PlayerService.self) private var playerService

    @State private var volumeValue: Double = 1.0
    @State private var isAdjustingVolume = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await self.playerService.toggleMute() }
            } label: {
                Image(systemName: self.volumeIcon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.playerService.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))

            Slider(value: self.$volumeValue, in: 0 ... 1) { editing in
                if editing {
                    self.isAdjustingVolume = true
                } else {
                    self.isAdjustingVolume = false
                    Task { await self.playerService.setVolume(self.volumeValue) }
                }
            }
            .tint(Self.brandAccent)
            .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayerVolumeSlider)
            .accessibilityLabel(String(localized: "Volume"))
        }
        .foregroundStyle(.secondary)
        .onAppear {
            self.volumeValue = self.playerService.volume
        }
        .onChange(of: self.playerService.volume) { _, newValue in
            guard !self.isAdjustingVolume else { return }
            self.volumeValue = newValue
        }
        .onChange(of: self.volumeValue) { oldValue, newValue in
            guard self.isAdjustingVolume else { return }

            if (oldValue > 0 && newValue == 0) || (oldValue < 1 && newValue == 1) {
                HapticService.sliderBoundary()
            }

            Task { await self.playerService.setVolume(newValue) }
        }
    }

    private var volumeIcon: String {
        let currentVolume = self.isAdjustingVolume ? self.volumeValue : self.playerService.volume

        if currentVolume == 0 {
            return "speaker.slash.fill"
        } else if currentVolume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

// MARK: - NowPlayingArtworkView

/// Shared square artwork for player presentation surfaces.
@available(macOS 26.0, *)
struct NowPlayingArtworkView: View {
    @Environment(PlayerService.self) private var playerService

    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let track = self.playerService.currentTrack {
                SongThumbnailView(song: track, size: self.size, cornerRadius: self.cornerRadius)
            } else {
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .fill(.quaternary)
                    .overlay {
                        CassetteIcon(size: self.size * 0.38)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: self.size, height: self.size)
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
    }
}

// MARK: - NowPlayingTitleBlock

/// Shared title/artist block for player presentation surfaces.
@available(macOS 26.0, *)
struct NowPlayingTitleBlock: View {
    @Environment(PlayerService.self) private var playerService

    let titleFont: Font
    let artistFont: Font

    var body: some View {
        VStack(spacing: 6) {
            Text(self.playerService.currentTrack?.title ?? String(localized: "Nothing Playing"))
                .font(self.titleFont.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(self.artistName)
                .font(self.artistFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: 460)
    }

    private var artistName: String {
        guard let track = self.playerService.currentTrack else {
            return String(localized: "Choose something to play")
        }

        return track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay
    }
}

// MARK: - NowPlayingTransportControls

/// Shared previous/play-next transport controls for expanded player surfaces.
@available(macOS 26.0, *)
struct NowPlayingTransportControls: View {
    enum Size {
        case regular
        case large

        var playFontSize: CGFloat {
            switch self {
            case .regular:
                32
            case .large:
                40
            }
        }

        var sideFontSize: CGFloat {
            switch self {
            case .regular:
                22
            case .large:
                28
            }
        }
    }

    @Environment(PlayerService.self) private var playerService

    let size: Size

    var body: some View {
        HStack(spacing: 30) {
            Button {
                HapticService.playback()
                Task { await self.playerService.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: self.size.sideFontSize, weight: .medium))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(String(localized: "Previous track"))

            Button {
                HapticService.playback()
                Task { await self.playerService.playPause() }
            } label: {
                Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: self.size.playFontSize, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel(self.playerService.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            Button {
                HapticService.playback()
                Task { await self.playerService.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: self.size.sideFontSize, weight: .medium))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(String(localized: "Next track"))
        }
        .disabled(self.playerService.currentTrack == nil)
    }
}

@available(macOS 26.0, *)
#Preview("Focus Player") {
    FocusPlayerView()
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.focus))
}

@available(macOS 26.0, *)
#Preview("Compact Player") {
    CompactPlayerView()
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.compact))
}
