import Foundation

// MARK: - SearchResponse

/// Response from a YouTube Music search query.
struct SearchResponse {
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]
    let playlists: [Playlist]
    let podcastShows: [PodcastShow]
    /// Shelves in the order YouTube returned them. Used by the "All" filter to
    /// preserve YT Music's authoritative result ordering (Top result → Songs →
    /// Albums → Community playlists → Artists → …). Empty when constructed from
    /// a filtered-tab response (those keep the flat arrays as their source).
    let sections: [SearchSection]
    /// Continuation token for loading more results (only present for filtered searches).
    let continuationToken: String?

    /// All results as a flat array of items.
    /// When `sections` is populated, the order follows YT Music's shelf order.
    /// Otherwise items are concatenated by type as a fallback.
    var allItems: [SearchResultItem] {
        if !self.sections.isEmpty {
            return self.sections.flatMap(\.items)
        }
        var items: [SearchResultItem] = []
        items.append(contentsOf: self.songs.map { .song($0) })
        items.append(contentsOf: self.albums.map { .album($0) })
        items.append(contentsOf: self.artists.map { .artist($0) })
        items.append(contentsOf: self.playlists.map { .playlist($0) })
        items.append(contentsOf: self.podcastShows.map { .podcastShow($0) })
        return items
    }

    /// Whether the search returned any results.
    var isEmpty: Bool {
        self.songs.isEmpty && self.albums.isEmpty && self.artists.isEmpty && self.playlists.isEmpty && self.podcastShows.isEmpty
    }

    /// Whether more results are available to load.
    var hasMore: Bool {
        self.continuationToken != nil
    }

    static let empty = SearchResponse(
        songs: [],
        albums: [],
        artists: [],
        playlists: [],
        podcastShows: [],
        sections: [],
        continuationToken: nil
    )

    /// Creates a SearchResponse without continuation token (backward compatibility).
    init(songs: [Song], albums: [Album], artists: [Artist], playlists: [Playlist]) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.podcastShows = []
        self.sections = []
        self.continuationToken = nil
    }

    /// Creates a SearchResponse with optional continuation token (backward compatibility).
    init(songs: [Song], albums: [Album], artists: [Artist], playlists: [Playlist], continuationToken: String?) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.podcastShows = []
        self.sections = []
        self.continuationToken = continuationToken
    }

    /// Creates a SearchResponse with podcast shows and optional continuation token.
    init(
        songs: [Song],
        albums: [Album],
        artists: [Artist],
        playlists: [Playlist],
        podcastShows: [PodcastShow],
        continuationToken: String?
    ) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.podcastShows = podcastShows
        self.sections = []
        self.continuationToken = continuationToken
    }

    /// Creates a SearchResponse with shelf sections, used for ordered "All" search results.
    init(
        songs: [Song],
        albums: [Album],
        artists: [Artist],
        playlists: [Playlist],
        podcastShows: [PodcastShow],
        sections: [SearchSection],
        continuationToken: String?
    ) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.podcastShows = podcastShows
        self.sections = sections
        self.continuationToken = continuationToken
    }
}

// MARK: - SearchSection

/// One shelf inside a YouTube Music "All" search response (e.g. "Songs",
/// "Albums", or the unlabeled top-result card). Preserves YouTube's own
/// ordering so the UI can mirror it instead of grouping by type.
struct SearchSection: Identifiable {
    let id: String
    /// Shelf title from YouTube ("Songs", "Albums", "Community playlists"…).
    /// `nil` for the top-result card, which renders prominently.
    let title: String?
    /// True for `musicCardShelfRenderer` — the prominent top-result hero.
    let isTopResult: Bool
    let items: [SearchResultItem]
}

// MARK: - SearchResultItem

/// A search result item (can be any content type).
enum SearchResultItem: Identifiable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case podcastShow(PodcastShow)

    var id: String {
        switch self {
        case let .song(song):
            "song-\(song.id)"
        case let .album(album):
            "album-\(album.id)"
        case let .artist(artist):
            "artist-\(artist.id)"
        case let .playlist(playlist):
            "playlist-\(playlist.id)"
        case let .podcastShow(show):
            "podcast-\(show.id)"
        }
    }

    var title: String {
        switch self {
        case let .song(song):
            song.title
        case let .album(album):
            album.title
        case let .artist(artist):
            artist.name
        case let .playlist(playlist):
            playlist.title
        case let .podcastShow(show):
            show.title
        }
    }

    var subtitle: String? {
        switch self {
        case let .song(song):
            let display = song.artistsDisplay
            return display.isEmpty ? nil : display
        case let .album(album):
            let display = album.artistsDisplay
            return display.isEmpty ? nil : display
        case .artist:
            // No additional subtitle needed - resultType already shows "Artist"
            return nil
        case let .playlist(playlist):
            // Strip "Playlist • " prefix since resultType already shows "Playlist"
            guard let author = playlist.author else { return nil }
            let stripped = author
                .replacingOccurrences(of: "Playlist • ", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? nil : stripped
        case let .podcastShow(show):
            return show.author
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case let .song(song):
            song.thumbnailURL
        case let .album(album):
            album.thumbnailURL
        case let .artist(artist):
            artist.thumbnailURL
        case let .playlist(playlist):
            playlist.thumbnailURL
        case let .podcastShow(show):
            show.thumbnailURL
        }
    }

    var resultType: String {
        switch self {
        case .song:
            "Song"
        case .album:
            "Album"
        case .artist:
            "Artist"
        case .playlist:
            "Playlist"
        case .podcastShow:
            "Podcast"
        }
    }

    /// Returns the video ID if this item is directly playable.
    var videoId: String? {
        switch self {
        case let .song(song):
            song.videoId
        default:
            nil
        }
    }
}
