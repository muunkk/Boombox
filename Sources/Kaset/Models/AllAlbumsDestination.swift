import Foundation

// MARK: - AllAlbumsDestination

/// Navigation destination for viewing all albums of an artist.
struct AllAlbumsDestination: Hashable {
    let artistId: String
    let artistName: String
    let albums: [Album]
    /// Browse ID for loading all albums (if more are available).
    let albumsBrowseId: String?
    /// Params for loading all albums.
    let albumsParams: String?
}
