import Foundation
import SwiftUI

// MARK: - PlayerPresentationChromeLayout

private enum PlayerPresentationChromeLayout {
    static let artworkCornerRadius: CGFloat = 12
    static let trafficLightReserveHeight: CGFloat = 36
    static let exitButtonInset: CGFloat = 16
    static let compactIconButtonSize: CGFloat = 34
    static let focusIconButtonSize: CGFloat = 40
}

// MARK: - FocusPlayerView

/// Full-window now-playing surface used by Focus Player mode.
@available(macOS 26.0, *)
struct FocusPlayerView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    let client: any YTMusicClientProtocol

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AccentBackground(imageURL: self.playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()

                HStack(alignment: .center, spacing: self.layoutSpacing(for: geometry.size)) {
                    NowPlayingArtworkView(
                        size: self.artworkSize(for: geometry.size),
                        cornerRadius: PlayerPresentationChromeLayout.artworkCornerRadius
                    )

                    self.detailColumn
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, self.horizontalPadding(for: geometry.size))
                .padding(.top, PlayerPresentationChromeLayout.trafficLightReserveHeight)
                .padding(.bottom, 32)
            }
            .overlay(alignment: .trailing) {
                PlayerPresentationSidebarOverlay(client: self.client)
                    .padding(.trailing, 16)
                    .padding(.vertical, 16)
            }
            .overlay(alignment: .topTrailing) {
                self.exitButton
                    .padding(.top, PlayerPresentationChromeLayout.exitButtonInset)
                    .padding(.trailing, PlayerPresentationChromeLayout.exitButtonInset)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .ignoresSafeArea()
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Focus Player"))
    }

    private var exitButton: some View {
        Button {
            self.exitToStandard()
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: PlayerPresentationChromeLayout.focusIconButtonSize,
                    height: PlayerPresentationChromeLayout.focusIconButtonSize
                )
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
        .help(String(localized: "Return to Full App"))
        .accessibilityLabel(String(localized: "Return to Full App"))
        .accessibilityIdentifier(AccessibilityID.MainWindow.focusPlayerExitButton)
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
        static let bottomPadding: CGFloat = 14
    }

    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    let client: any YTMusicClientProtocol

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = self.artworkSize(for: proxy.size)

            ZStack {
                AccentBackground(imageURL: self.playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 4)

                    NowPlayingArtworkView(
                        size: artworkSize,
                        cornerRadius: PlayerPresentationChromeLayout.artworkCornerRadius
                    )
                    .accessibilityHidden(self.playerService.currentTrack == nil)

                    Spacer(minLength: 8)

                    NowPlayingTitleBlock(titleFont: .title3, artistFont: .callout)

                    Spacer(minLength: 6)

                    NowPlayingProgressView(accessibilityIdentifier: AccessibilityID.MainWindow.compactPlayerSeekSlider)

                    Spacer(minLength: 10)

                    NowPlayingTransportControls(size: .regular)

                    Spacer(minLength: 10)

                    CompactPlayerActionRow()

                    Spacer(minLength: 6)

                    NowPlayingVolumeControl()
                }
                .padding(.horizontal, Self.Layout.horizontalPadding)
                .padding(.top, PlayerPresentationChromeLayout.trafficLightReserveHeight)
                .padding(.bottom, Self.Layout.bottomPadding)
            }
            .overlay(alignment: .trailing) {
                PlayerPresentationSidebarOverlay(client: self.client)
                    .padding(.trailing, 12)
                    .padding(.vertical, 12)
            }
            .overlay(alignment: .topTrailing) {
                self.backButton
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .frame(
            minWidth: Self.Layout.minimumSize.width,
            idealWidth: Self.Layout.idealSize.width,
            minHeight: Self.Layout.minimumSize.height,
            idealHeight: Self.Layout.idealSize.height
        )
        .ignoresSafeArea()
        .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayer)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Small Player"))
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.playerPresentationMode.wrappedValue = .standard
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
        .help(String(localized: "Back to Full App"))
        .accessibilityLabel(String(localized: "Back to Full App"))
        .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayerBackButton)
    }

    private func artworkSize(for availableSize: CGSize) -> CGFloat {
        min(max(availableSize.height * 0.38, 198), availableSize.width - 64, 292)
    }
}

// MARK: - CompactPlayerActionRow

/// Secondary actions for Small Player mode.
@available(macOS 26.0, *)
struct CompactPlayerActionRow: View {
    @Environment(PlayerService.self) private var playerService

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
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
                    systemImage: self.playerService.showLyrics ? "quote.bubble.fill" : "quote.bubble",
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
                    systemImage: self.playerService.showQueue ? "list.bullet.rectangle.fill" : "list.bullet",
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
            .glassEffect(.regular.interactive(), in: .capsule)
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
            Image(systemName: self.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(self.isActive ? Color.red : Color.primary.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(
                    width: PlayerPresentationChromeLayout.compactIconButtonSize,
                    height: PlayerPresentationChromeLayout.compactIconButtonSize
                )
        }
        .buttonStyle(.pressable)
        .help(self.title)
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
                    Task {
                        await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: self.volumeValue))
                    }
                }
            }
            .tint(Self.brandAccent)
            .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayerVolumeSlider)
            .accessibilityLabel(String(localized: "Volume"))
        }
        .foregroundStyle(.secondary)
        .onAppear {
            self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: self.playerService.volume)
        }
        .onChange(of: self.playerService.volume) { _, newValue in
            guard !self.isAdjustingVolume else { return }
            self.volumeValue = VolumeCurve.sliderValue(forOutputVolume: newValue)
        }
        .onChange(of: self.volumeValue) { oldValue, newValue in
            guard self.isAdjustingVolume else { return }

            if (oldValue > 0 && newValue == 0) || (oldValue < 1 && newValue == 1) {
                HapticService.sliderBoundary()
            }

            Task {
                await self.playerService.setVolume(VolumeCurve.outputVolume(forSliderValue: newValue))
            }
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

        var spacing: CGFloat {
            switch self {
            case .regular:
                12
            case .large:
                16
            }
        }

        var playFontSize: CGFloat {
            switch self {
            case .regular:
                22
            case .large:
                26
            }
        }

        var sideFontSize: CGFloat {
            switch self {
            case .regular:
                17
            case .large:
                20
            }
        }

        var playHitSize: CGFloat {
            switch self {
            case .regular:
                54
            case .large:
                58
            }
        }

        var sideHitSize: CGFloat {
            switch self {
            case .regular:
                42
            case .large:
                46
            }
        }
    }

    @Environment(PlayerService.self) private var playerService

    let size: Size

    var body: some View {
        GlassEffectContainer(spacing: self.size.spacing) {
            HStack(spacing: self.size.spacing) {
                self.transportButton(
                    systemImage: "backward.fill",
                    fontSize: self.size.sideFontSize,
                    hitSize: self.size.sideHitSize,
                    accessibilityLabel: String(localized: "Previous track")
                ) {
                    Task { await self.playerService.previous() }
                }

                self.transportButton(
                    systemImage: self.playerService.isPlaying ? "pause.fill" : "play.fill",
                    fontSize: self.size.playFontSize,
                    hitSize: self.size.playHitSize,
                    accessibilityLabel: self.playerService.isPlaying ? String(localized: "Pause") : String(localized: "Play")
                ) {
                    Task { await self.playerService.playPause() }
                }

                self.transportButton(
                    systemImage: "forward.fill",
                    fontSize: self.size.sideFontSize,
                    hitSize: self.size.sideHitSize,
                    accessibilityLabel: String(localized: "Next track")
                ) {
                    Task { await self.playerService.next() }
                }
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .disabled(self.playerService.currentTrack == nil)
    }

    private func transportButton(
        systemImage: String,
        fontSize: CGFloat,
        hitSize: CGFloat,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticService.playback()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: hitSize, height: hitSize)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - NowPlayingFocusActions

/// Shared Focus Player secondary actions.
@available(macOS 26.0, *)
struct NowPlayingFocusActions: View {
    @Environment(PlayerService.self) private var playerService

    var body: some View {
        @Bindable var player = self.playerService

        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                self.actionButton(
                    title: String(localized: "Like"),
                    systemImage: self.playerService.currentTrackLikeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isActive: self.playerService.currentTrackLikeStatus == .like,
                    accessibility: .init(
                        identifier: AccessibilityID.MainWindow.focusPlayerLikeButton,
                        value: self.likeAccessibilityValue
                    )
                ) {
                    self.playerService.likeCurrentTrack()
                }

                self.actionButton(
                    title: String(localized: "Lyrics"),
                    systemImage: self.playerService.showLyrics ? "quote.bubble.fill" : "quote.bubble",
                    isActive: self.playerService.showLyrics,
                    accessibility: .init(
                        identifier: AccessibilityID.MainWindow.focusPlayerLyricsButton,
                        value: self.playerService.showLyrics ? String(localized: "Showing") : String(localized: "Hidden")
                    )
                ) {
                    withAnimation(AppAnimation.standard) {
                        player.showLyrics.toggle()
                    }
                }

                self.actionButton(
                    title: String(localized: "Queue"),
                    systemImage: self.playerService.showQueue ? "list.bullet.rectangle.fill" : "list.bullet",
                    isActive: self.playerService.showQueue,
                    accessibility: .init(
                        identifier: AccessibilityID.MainWindow.focusPlayerQueueButton,
                        value: self.playerService.showQueue ? String(localized: "Showing") : String(localized: "Hidden")
                    )
                ) {
                    withAnimation(AppAnimation.standard) {
                        player.showQueue.toggle()
                    }
                }
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .disabled(self.playerService.currentTrack == nil)
    }

    private struct ActionButtonAccessibility {
        let identifier: String
        let value: String
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        accessibility: ActionButtonAccessibility,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticService.toggle()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? Color.red : Color.primary.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(
                    width: PlayerPresentationChromeLayout.focusIconButtonSize,
                    height: PlayerPresentationChromeLayout.focusIconButtonSize
                )
        }
        .buttonStyle(.pressable)
        .help(title)
        .accessibilityIdentifier(accessibility.identifier)
        .accessibilityLabel(title)
        .accessibilityValue(accessibility.value)
    }

    private var likeAccessibilityValue: String {
        self.playerService.currentTrackLikeStatus == .like ? String(localized: "Liked") : String(localized: "Not liked")
    }
}

// MARK: - PlayerPresentationSidebarOverlay

@available(macOS 26.0, *)
private struct PlayerPresentationSidebarOverlay: View {
    @Environment(PlayerService.self) private var playerService

    let client: any YTMusicClientProtocol

    var body: some View {
        if self.playerService.showLyrics || self.playerService.showQueue {
            Group {
                if self.playerService.showLyrics {
                    LyricsView(client: self.client)
                } else if self.playerService.queueDisplayMode == .sidepanel {
                    QueueSidePanelView()
                } else {
                    QueueView()
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

@available(macOS 26.0, *)
#Preview("Focus Player") {
    FocusPlayerView(client: MockUITestYTMusicClient())
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.focus))
}

@available(macOS 26.0, *)
#Preview("Compact Player") {
    CompactPlayerView(client: MockUITestYTMusicClient())
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.compact))
}
