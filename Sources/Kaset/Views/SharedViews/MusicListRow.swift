import SwiftUI

/// A reusable list row with a play-on-hover thumbnail overlay.
/// Used by Home song-list sections, the Quick Picks carousel, and Liked Songs.
///
/// The caller supplies `thumbnail` already sized to `thumbSize` and clipped to
/// `thumbnailCornerRadius`; this view overlays a dim + play glyph on hover.
@available(macOS 26.0, *)
struct MusicListRow<Thumbnail: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    var rank: Int?
    var thumbSize: CGFloat
    var thumbnailCornerRadius: CGFloat
    var verticalPadding: CGFloat
    var cornerRadius: CGFloat
    let onPlay: () -> Void
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String?,
        rank: Int? = nil,
        thumbSize: CGFloat = 48,
        thumbnailCornerRadius: CGFloat = 6,
        verticalPadding: CGFloat = 6,
        cornerRadius: CGFloat = 6,
        onPlay: @escaping () -> Void,
        @ViewBuilder thumbnail: @escaping () -> Thumbnail,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rank = rank
        self.thumbSize = thumbSize
        self.thumbnailCornerRadius = thumbnailCornerRadius
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.onPlay = onPlay
        self.thumbnail = thumbnail
        self.trailing = trailing
    }

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 12) {
                if let rank = self.rank {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                        .monospacedDigit()
                }

                ZStack {
                    self.thumbnail()
                    if self.isHovering {
                        RoundedRectangle(cornerRadius: self.thumbnailCornerRadius)
                            .fill(.black.opacity(0.45))
                            .frame(width: self.thumbSize, height: self.thumbSize)
                        Image(systemName: "play.fill")
                            .font(.system(size: self.thumbSize * 0.34, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .pointingHandCursor()

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = self.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                self.trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, self.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow(cornerRadius: self.cornerRadius))
        .animation(.easeInOut(duration: 0.12), value: self.isHovering)
        .onHover { hovering in
            self.isHovering = hovering
        }
    }
}
