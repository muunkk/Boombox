import SwiftUI

// MARK: - NowPlayingSidebarPanel

/// Toggleable sidebar now-playing artwork panel.
@available(macOS 26.0, *)
struct NowPlayingSidebarPanel: View {
    private enum Layout {
        static let artworkSize: CGFloat = 156
        static let cornerRadius: CGFloat = 12
    }

    @Environment(PlayerService.self) private var playerService
    @Environment(\.playerPresentationMode) private var playerPresentationMode

    @State private var settings = SettingsManager.shared
    @State private var isHoveringArtwork = false

    var body: some View {
        VStack(spacing: 10) {
            self.artwork

            VStack(spacing: 3) {
                Text(self.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .accessibilityIdentifier(AccessibilityID.Sidebar.nowPlayingPanel)
    }

    private var artwork: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let track = self.playerService.currentTrack {
                    SongThumbnailView(song: track, size: Self.Layout.artworkSize, cornerRadius: Self.Layout.cornerRadius)
                } else {
                    RoundedRectangle(cornerRadius: Self.Layout.cornerRadius)
                        .fill(.quaternary)
                        .overlay {
                            CassetteIcon(size: Self.Layout.artworkSize * 0.38)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: Self.Layout.artworkSize, height: Self.Layout.artworkSize)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)

            self.hoverActions
                .padding(8)
        }
        .frame(width: Self.Layout.artworkSize, height: Self.Layout.artworkSize)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHoveringArtwork = hovering
            }
        }
        .accessibilityIdentifier(AccessibilityID.Sidebar.nowPlayingArtwork)
        .accessibilityLabel(self.artworkAccessibilityLabel)
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button {
                HapticService.navigation()
                withAnimation(AppAnimation.standard) {
                    self.playerPresentationMode.wrappedValue = .focus
                }
            } label: {
                Label("Focus", systemImage: "rectangle.expand.vertical")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.Sidebar.nowPlayingFocusButton)
            .accessibilityLabel(String(localized: "Focus Player"))
            .disabled(self.playerService.currentTrack == nil)

            Button {
                HapticService.toggle()
                withAnimation(AppAnimation.standard) {
                    self.settings.showSidebarNowPlayingPanel = false
                }
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.Sidebar.nowPlayingHideButton)
            .accessibilityLabel(String(localized: "Hide Now Playing Panel"))
        }
        .font(.caption2.weight(.medium))
        .labelStyle(.titleAndIcon)
        .opacity(self.isHoveringArtwork ? 1 : 0)
        .allowsHitTesting(self.isHoveringArtwork)
        .accessibilityHidden(!self.isHoveringArtwork)
    }

    private var title: String {
        self.playerService.currentTrack?.title ?? String(localized: "Nothing Playing")
    }

    private var subtitle: String {
        guard let track = self.playerService.currentTrack else {
            return String(localized: "Choose something to play")
        }

        return track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay
    }

    private var artworkAccessibilityLabel: String {
        guard let track = self.playerService.currentTrack else {
            return String(localized: "No song playing")
        }

        let artist = track.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : track.artistsDisplay
        return String(localized: "Now playing artwork for \(track.title) by \(artist)")
    }
}

@available(macOS 26.0, *)
#Preview {
    NowPlayingSidebarPanel()
        .environment(PlayerService())
        .environment(\.playerPresentationMode, .constant(.standard))
        .frame(width: 220)
}
