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
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text(PlayerPresentationMode.compact.displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playerPresentationMode.wrappedValue = .standard
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.glass)
                .accessibilityLabel(String(localized: "Back to Full App"))
            }

            Spacer(minLength: 0)
            NowPlayingArtworkView(size: 260, cornerRadius: 10)
            NowPlayingTitleBlock(titleFont: .title3, artistFont: .headline)
            NowPlayingTransportControls(size: .regular)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 360, minHeight: 540)
        .background {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
        .accessibilityIdentifier(AccessibilityID.MainWindow.compactPlayer)
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
