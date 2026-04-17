import Foundation
import SwiftUI

// MARK: - FocusPlayerView

/// Full-window now-playing surface used by Focus Player mode.
@available(macOS 26.0, *)
struct FocusPlayerView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AccentBackground(imageURL: self.playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL)
                    .ignoresSafeArea()

                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.18)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    self.header

                    Spacer(minLength: 24)

                    HStack(alignment: .center, spacing: self.layoutSpacing(for: geometry.size)) {
                        NowPlayingArtworkView(size: self.artworkSize(for: geometry.size), cornerRadius: 18)

                        self.detailColumn
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, self.horizontalPadding(for: geometry.size))
                .padding(.vertical, 30)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .focusable()
        .focused(self.$hasKeyboardFocus)
        .onAppear {
            self.hasKeyboardFocus = true
        }
        .onKeyPress(.escape) {
            self.exitToStandard()
            return .handled
        }
        .background {
            Button("") {
                self.exitToStandard()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayer)
    }

    private var header: some View {
        HStack {
            Text(PlayerPresentationMode.focus.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                self.exitToStandard()
            } label: {
                Label("Return to Full App", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayerExitButton)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 24) {
            NowPlayingTitleBlock(titleFont: .largeTitle, artistFont: .title2, maxWidth: 560)

            NowPlayingProgressView(accessibilityIdentifier: AccessibilityID.MainWindow.focusPlayerProgressSlider)
                .frame(maxWidth: 520)

            NowPlayingTransportControls(size: .large)

            NowPlayingFocusActions()
        }
        .frame(maxWidth: 560)
    }

    private func exitToStandard() {
        withAnimation(AppAnimation.standard) {
            self.playerPresentationMode.wrappedValue = .standard
        }
    }

    private func artworkSize(for size: CGSize) -> CGFloat {
        min(max(min(size.height * 0.58, size.width * 0.38), 300), 460)
    }

    private func horizontalPadding(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.06, 36), 72)
    }

    private func layoutSpacing(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.045, 36), 72)
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

// MARK: - ExpandedNowPlayingPopoverView

/// Medium now-playing popover opened from the bottom player bar.
@available(macOS 26.0, *)
struct ExpandedNowPlayingPopoverView: View {
    @Binding var isPresented: Bool

    @Environment(\.playerPresentationMode) private var playerPresentationMode

    @State private var isHovering = false

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 18) {
                    NowPlayingArtworkView(size: 220, cornerRadius: 12)

                    NowPlayingTitleBlock(titleFont: .title3, artistFont: .subheadline, maxWidth: 280)

                    NowPlayingProgressView(accessibilityIdentifier: AccessibilityID.PlayerBar.expandedPopoverProgressSlider)
                        .frame(width: 280)

                    NowPlayingTransportControls(size: .regular)
                }
                .padding(.top, self.isHovering ? 34 : 10)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(width: 324)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))

                self.hoverActions
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHovering = hovering
            }
        }
        .accessibilityIdentifier(AccessibilityID.PlayerBar.expandedPopover)
    }

    private var hoverActions: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(AppAnimation.standard) {
                    self.playerPresentationMode.wrappedValue = .focus
                    self.isPresented = false
                }
            } label: {
                Label("Focus Player", systemImage: "rectangle.expand.vertical")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.expandedPopoverFocusButton)

            Button {
                withAnimation(AppAnimation.quick) {
                    self.isPresented = false
                }
            } label: {
                Label("Collapse", systemImage: "chevron.down")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.expandedPopoverCollapseButton)
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .opacity(self.isHovering ? 1 : 0)
        .allowsHitTesting(self.isHovering)
        .accessibilityHidden(!self.isHovering)
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
    var maxWidth: CGFloat = 460

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
        .frame(maxWidth: self.maxWidth)
    }

    private var artistName: String {
        guard let track = self.playerService.currentTrack else {
            return String(localized: "Choose something to play")
        }

        return track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay
    }
}

// MARK: - NowPlayingProgressView

/// Shared progress and seek control for expanded player surfaces.
@available(macOS 26.0, *)
struct NowPlayingProgressView: View {
    private static let brandAccent = PackageResourceLookup.brandAccent

    @Environment(PlayerService.self) private var playerService

    let accessibilityIdentifier: String?

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    init(accessibilityIdentifier: String? = nil) {
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: self.$seekValue, in: 0 ... 1) { editing in
                if editing {
                    self.isSeeking = true
                } else {
                    self.performSeek()
                }
            }
            .controlSize(.small)
            .tint(Self.brandAccent)
            .disabled(!self.canSeek)
            .ifLet(self.accessibilityIdentifier) { view, identifier in
                view.accessibilityIdentifier(identifier)
            }

            HStack {
                Text(self.formattedTime(self.displayedProgress))
                    .frame(minWidth: 44, alignment: .leading)

                Spacer()

                Text("-\(self.formattedTime(self.remainingTime))")
                    .frame(minWidth: 44, alignment: .trailing)
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
        .onChange(of: self.playerService.currentTrack?.videoId) { _, _ in
            self.syncSeekValue()
        }
    }

    private var canSeek: Bool {
        self.playerService.currentTrack != nil && self.playerService.duration > 0
    }

    private var displayedProgress: TimeInterval {
        if self.isSeeking {
            return self.seekValue * self.playerService.duration
        }

        return self.playerService.progress
    }

    private var remainingTime: TimeInterval {
        max(self.playerService.duration - self.displayedProgress, 0)
    }

    private func syncSeekValue() {
        guard !self.isSeeking else { return }
        guard self.playerService.duration > 0 else {
            self.seekValue = 0
            return
        }

        self.seekValue = min(max(self.playerService.progress / self.playerService.duration, 0), 1)
    }

    private func performSeek() {
        guard self.isSeeking else { return }
        guard self.canSeek else {
            self.isSeeking = false
            self.seekValue = 0
            return
        }

        let seekTime = self.seekValue * self.playerService.duration
        Task {
            await self.playerService.seek(to: seekTime)
            self.isSeeking = false
            self.syncSeekValue()
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return seconds.formattedDuration
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

// MARK: - NowPlayingFocusActions

/// Shared Focus Player secondary actions.
@available(macOS 26.0, *)
struct NowPlayingFocusActions: View {
    @Environment(PlayerService.self) private var playerService

    var body: some View {
        @Bindable var player = self.playerService

        return HStack(spacing: 12) {
            Button {
                HapticService.toggle()
                self.playerService.likeCurrentTrack()
            } label: {
                Label("Like", systemImage: self.playerService.currentTrackLikeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .foregroundStyle(self.playerService.currentTrackLikeStatus == .like ? .red : .primary)
            .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayerLikeButton)
            .accessibilityValue(self.playerService.currentTrackLikeStatus == .like ? String(localized: "Liked") : String(localized: "Not liked"))
            .disabled(self.playerService.currentTrack == nil)

            Button {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    player.showLyrics.toggle()
                }
            } label: {
                Label("Lyrics", systemImage: self.playerService.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .foregroundStyle(self.playerService.showLyrics ? .red : .primary)
            .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayerLyricsButton)
            .accessibilityValue(self.playerService.showLyrics ? String(localized: "Showing") : String(localized: "Hidden"))
            .disabled(self.playerService.currentTrack == nil)

            Button {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    player.showQueue.toggle()
                }
            } label: {
                Label("Queue", systemImage: self.playerService.showQueue ? "list.bullet.rectangle.fill" : "list.bullet")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .foregroundStyle(self.playerService.showQueue ? .red : .primary)
            .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayerQueueButton)
            .accessibilityValue(self.playerService.showQueue ? String(localized: "Showing") : String(localized: "Hidden"))
        }
        .font(.system(size: 14, weight: .medium))
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

@available(macOS 26.0, *)
#Preview("Expanded Now Playing Popover") {
    @Previewable @State var isPresented = true

    ExpandedNowPlayingPopoverView(isPresented: $isPresented)
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.standard))
}
