import Foundation
import Observation

// MARK: - GlobalNavigationCoordinator

/// Cross-tab navigation requests. Used by views that live outside any
/// `NavigationStack` (e.g. the sidebar now-playing card) to push onto the
/// Library tab's stack.
///
/// Producers set `pendingArtist` or `pendingPlaylist` and `pendingTab`.
/// `MainWindow` observes the tab and switches selection; `LibraryView`
/// observes the destinations and appends them to its navigation path,
/// clearing the pending state once consumed.
@MainActor
@Observable
final class GlobalNavigationCoordinator {
    var pendingArtist: Artist?
    var pendingPlaylist: Playlist?
    var pendingTab: NavigationItem?

    /// Request opening an artist in the Library tab.
    func openArtist(_ artist: Artist) {
        self.pendingArtist = artist
        self.pendingTab = .library
    }

    /// Request opening an album. Albums navigate as Playlist destinations
    /// in this codebase, so we wrap accordingly.
    func openAlbum(_ album: Album, fallbackThumbnail: URL? = nil) {
        let playlist = Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL ?? fallbackThumbnail,
            trackCount: album.trackCount,
            author: album.artistsDisplay
        )
        self.pendingPlaylist = playlist
        self.pendingTab = .library
    }
}
