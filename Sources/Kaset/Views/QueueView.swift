import SwiftUI

// MARK: - QueueDisplayEntry

/// Stable, unique identity for a queue row at a given position.
///
/// A playlist or album may legitimately contain the same track more than once,
/// so neither `Song.videoId` nor `Song.id` is unique within a queue. Driving
/// `ForEach` off a bare videoId collides (dropped rows, wrong row highlighted as
/// current, tap/remove targeting the wrong copy). Keying on position+videoId
/// keeps rendering correct even with duplicate tracks. See P2F035.
@available(macOS 26.0, *)
struct QueueDisplayEntry: Identifiable {
    /// Composite "index-videoId" key, unique and stable for a given snapshot.
    let id: String
    let index: Int
    let song: Song

    /// Builds display entries for a queue snapshot.
    static func entries(for queue: [Song]) -> [QueueDisplayEntry] {
        queue.enumerated().map { index, song in
            QueueDisplayEntry(id: "\(index)-\(song.videoId)", index: index, song: song)
        }
    }
}

// MARK: - QueueView

/// Right sidebar panel displaying the playback queue.
@available(macOS 26.0, *)
struct QueueView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(\.showCommandBar) private var showCommandBar

    /// Namespace for glass effect morphing.
    @Namespace private var queueNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                // Header
                self.headerView

                Divider()
                    .opacity(0.3)

                // Content
                self.contentView
            }
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .glassEffectID("queuePanel", in: self.queueNamespace)
        }
        .glassEffectTransition(.materialize)
        .accessibilityIdentifier(AccessibilityID.Queue.container)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Up Next")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Clear queue button (only show if there are items beyond the current track)
            if self.playerService.queue.count > 1 {
                Button {
                    self.playerService.clearQueue()
                } label: {
                    Text("Clear")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.Queue.clearButton)
            }

            Button {
                self.playerService.toggleQueueDisplayMode()
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open queue in side panel"))
            .accessibilityLabel(String(localized: "Open queue in side panel"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if self.playerService.queue.isEmpty {
            self.emptyQueueView
        } else {
            self.queueListView
        }
    }

    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Queue")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Play songs from a playlist or album to build your queue.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.Queue.emptyState)
    }

    /// Stable per-position+videoId identities for the queue. A playlist/album
    /// may legitimately repeat a track, so videoId alone is not unique and
    /// collides under ForEach. See P2F035.
    private var queueEntries: [QueueDisplayEntry] {
        QueueDisplayEntry.entries(for: self.playerService.queue)
    }

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Composite position+videoId identity: a playlist/album may
                // legitimately repeat a track, so videoId alone is not unique
                // and collides under ForEach (dropped rows, wrong highlight).
                // See P2F035.
                ForEach(self.queueEntries) { entry in
                    let index = entry.index
                    let song = entry.song
                    QueueRowView(
                        song: song,
                        isCurrentTrack: index == self.playerService.currentIndex,
                        index: index,
                        favoritesManager: self.favoritesManager,
                        playerService: self.playerService,
                        onRemove: {
                            self.playerService.removeFromQueue(videoIds: Set([song.videoId]))
                        },
                        onTap: {
                            Task {
                                await self.playerService.playFromQueue(at: index)
                            }
                        }
                    )
                    .accessibilityIdentifier(AccessibilityID.Queue.row(index: index))
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier(AccessibilityID.Queue.scrollView)
    }
}

// MARK: - QueueRowView

@available(macOS 26.0, *)
private struct QueueRowView: View {
    let song: Song
    let isCurrentTrack: Bool
    let index: Int
    let favoritesManager: FavoritesManager
    let playerService: PlayerService
    let onRemove: () -> Void
    let onTap: () -> Void

    @Environment(GlobalNavigationCoordinator.self) private var globalNavigation

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Now Playing indicator or track number
            self.leadingIndicator
                .frame(width: 24)

            // Thumbnail
            SongThumbnailView(song: self.song, size: 40, cornerRadius: 4)

            // Track info — title and artist are clickable for navigation.
            VStack(alignment: .leading, spacing: 2) {
                self.titleText
                self.artistText
            }

            Spacer()

            // Duration
            if let duration = song.duration {
                Text(self.formatDuration(duration))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(self.backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture {
            self.onTap()
        }
        .onHover { hovering in
            self.isHovering = hovering
        }
        .contextMenu {
            // Play Next / Add to Queue first per user request.
            AddToQueueContextMenu(song: self.song, playerService: self.playerService)

            Divider()

            if let album = self.albumDestination {
                Button {
                    self.globalNavigation.openAlbum(album, fallbackThumbnail: self.song.thumbnailURL)
                } label: {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }

            if let artist = self.artistDestination {
                Button {
                    self.globalNavigation.openArtist(artist)
                } label: {
                    Label("Go to Artist", systemImage: "person")
                }
            }

            if self.albumDestination != nil || self.artistDestination != nil {
                Divider()
            }

            FavoritesContextMenu.menuItem(for: self.song, manager: self.favoritesManager)

            Divider()

            StartRadioContextMenu.menuItem(for: self.song, playerService: self.playerService)

            Divider()

            ShareContextMenu.menuItem(for: self.song)

            if !self.isCurrentTrack {
                Button(role: .destructive) {
                    self.onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
        // VoiceOver: the row is tap-to-play but onTapGesture is not promoted to
        // an accessible action, so expose play/remove explicitly. Use .contain
        // so the nested Go-to-Album / Go-to-Artist buttons stay reachable.
        // See P2F020.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(self.song.title + ", " + (self.song.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : self.song.artistsDisplay)))
        .accessibilityValue(self.isCurrentTrack ? Text(String(localized: "Now Playing")) : Text(""))
        .accessibilityAction { self.onTap() }
        .accessibilityAction(named: Text(String(localized: "Remove from Queue"))) {
            if !self.isCurrentTrack { self.onRemove() }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        let titleView = Text(self.song.title)
            .font(.system(size: 13, weight: self.isCurrentTrack ? .semibold : .regular))
            .lineLimit(1)
            .foregroundStyle(self.isCurrentTrack ? Color.red : .primary)

        if let album = self.albumDestination {
            Button {
                self.globalNavigation.openAlbum(album, fallbackThumbnail: self.song.thumbnailURL)
            } label: {
                titleView.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(String(localized: "Go to Album"))
        } else {
            titleView
        }
    }

    @ViewBuilder
    private var artistText: some View {
        let artistView = Text(self.song.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : self.song.artistsDisplay)
            .font(.system(size: 11))
            .lineLimit(1)
            .foregroundStyle(.secondary)

        if let artist = self.artistDestination {
            Button {
                self.globalNavigation.openArtist(artist)
            } label: {
                artistView.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(String(localized: "Go to Artist"))
        } else {
            artistView
        }
    }

    private var albumDestination: Album? {
        guard let album = self.song.album, album.hasNavigableId else { return nil }
        return album
    }

    private var artistDestination: Artist? {
        self.song.artists.first(where: { $0.hasNavigableId })
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if self.isCurrentTrack {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.playerService.isPlaying ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating,
                    isActive: self.playerService.isPlaying
                )
        } else {
            Text("\(self.index + 1)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var backgroundColor: Color {
        if self.isCurrentTrack {
            return Color.red.opacity(0.1)
        } else if self.isHovering {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@available(macOS 26.0, *)
#Preview("Queue View") {
    let playerService = PlayerService()
    QueueView()
        .environment(playerService)
        .environment(FavoritesManager.shared)
        .frame(height: 600)
}

@available(macOS 26.0, *)
#Preview("Queue View with Items") {
    let playerService = PlayerService()
    // Note: In real use, queue would be populated via playQueue()
    QueueView()
        .environment(playerService)
        .environment(FavoritesManager.shared)
        .frame(height: 600)
}
