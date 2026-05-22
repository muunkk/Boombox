import Foundation
import Observation
import os

/// View model for the AllAlbumsView.
@MainActor
@Observable
final class AllAlbumsViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// All loaded albums.
    private(set) var albums: [Album] = []

    private let destination: AllAlbumsDestination
    let client: any YTMusicClientProtocol
    private let logger = DiagnosticsLogger.api

    init(destination: AllAlbumsDestination, client: any YTMusicClientProtocol) {
        self.destination = destination
        self.client = client
        self.albums = destination.albums
    }

    /// Loads all albums if a browse ID is available.
    func load() async {
        guard let browseId = destination.albumsBrowseId else {
            self.loadingState = .loaded
            return
        }

        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        self.logger.info("Loading all artist albums: \(browseId)")

        do {
            let allAlbums = try await client.getArtistAlbums(
                browseId: browseId,
                params: self.destination.albumsParams
            )

            if !allAlbums.isEmpty {
                self.albums = allAlbums
            }
            self.loadingState = .loaded
            let albumCount = self.albums.count
            self.logger.info("Loaded \(albumCount) artist albums")
        } catch is CancellationError {
            self.logger.debug("Artist albums load cancelled")
            // Cancellation isn't a user-facing error; keep whatever albums we
            // already had (from the destination's seed) and stay loaded.
            self.loadingState = .loaded
        } catch {
            let errorMessage = error.localizedDescription
            self.logger.error("Failed to load artist albums: \(errorMessage)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }
}
