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
