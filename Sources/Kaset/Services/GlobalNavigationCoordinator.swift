import Foundation
import Observation

// MARK: - GlobalNavigationCoordinator

/// Cross-tab navigation requests.
///
/// Two roles:
///
/// 1. **Push onto Library:** views that live outside any `NavigationStack`
///    (e.g. the sidebar now-playing card) set `pendingArtist`/`pendingPlaylist`
///    plus `pendingTab = .library`. `MainWindow` observes the tab and switches
///    selection; `LibraryView` observes the destinations, appends them to its
///    navigation path, and clears the pending state.
///
/// 2. **Reset Search:** the command bar and the ⌘F handler call
///    `popSearchToRoot()` so the Search tab pops its `NavigationStack` back to
///    the search root before a new query runs. `SearchView` observes
///    `popSearchToRootSignal` and clears its local navigation path.
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
        self.pendingPlaylist = album.asPlaylistDestination(fallbackThumbnail: fallbackThumbnail)
        self.pendingTab = .library
    }
}
