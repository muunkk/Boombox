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
    /// Increments to request the Search tab pop its NavigationStack to root.
    /// Observed by `SearchView`; producers call `popSearchToRoot()`.
    var popSearchToRootSignal: Int = 0

    /// Request opening an artist in the Library tab.
    func openArtist(_ artist: Artist) {
        self.pendingArtist = artist
        self.pendingTab = .library
    }

    /// Request the Search tab clear its navigation stack so the user lands on the
    /// search root (search bar + results), not whatever detail page they last opened.
    func popSearchToRoot() {
        self.popSearchToRootSignal &+= 1
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
