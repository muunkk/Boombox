import Foundation

/// Parser for search responses from YouTube Music API.
enum SearchResponseParser {
    private static let logger = DiagnosticsLogger.api

    /// Parses a search response.
    ///
    /// Builds an ordered list of `SearchSection`s in the order YouTube returned
    /// them (Top result → Songs → Albums → Community playlists → Artists → …).
    /// The flat `songs/albums/artists/playlists/podcastShows` arrays are then
    /// derived from those sections so filtered tabs continue to work unchanged.
    static func parse(_ data: [String: Any]) -> SearchResponse {
        guard let contents = data["contents"] as? [String: Any],
              let tabbedSearchResults = contents["tabbedSearchResultsRenderer"] as? [String: Any],
              let tabs = tabbedSearchResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            self.logger.debug("SearchResponseParser: Failed to parse response structure. Top keys: \(data.keys.sorted())")
            return SearchResponse.empty
        }

        var draftSections: [DraftSection] = []
        for sectionData in sectionContents {
            draftSections.append(contentsOf: Self.parseSearchSections(sectionData))
        }

        // Stamp ids after the full ordered list is known so they don't depend
        // on the first item's id (which YT may reshuffle across personalized
        // re-queries, causing SwiftUI to tear down sections instead of diff).
        // Shelf titles ("Songs", "Albums", "Community playlists", …) are
        // normally unique per response, so we use them directly to keep ids
        // stable across re-queries. The "Top result" card is at most one per
        // response, so a fixed `"top"` is stable. YouTube can, however, return
        // two shelves with the same title (e.g. duplicate "Songs" wrapped in
        // separate itemSectionRenderers); we only suffix the 2nd+ occurrence of
        // a repeated title so single-occurrence ids stay unchanged while
        // duplicates remain distinct for SwiftUI identity. The index fallback
        // only kicks in for the unexpected untitled-shelf case.
        var seenTitles: [String: Int] = [:]
        let sections: [SearchSection] = draftSections.enumerated().map { index, draft in
            let id: String
            if draft.isTopResult {
                id = "top"
            } else if let title = draft.title, !title.isEmpty {
                let occurrence = seenTitles[title, default: 0]
                seenTitles[title] = occurrence + 1
                id = occurrence == 0 ? title : "\(title)#\(occurrence)"
            } else {
                id = "shelf-\(index)"
            }
            return SearchSection(id: id, title: draft.title, isTopResult: draft.isTopResult, items: draft.items)
        }

        var buckets = SearchResultBuckets()
        for section in sections {
            for item in section.items {
                buckets.append(item)
            }
        }

        return SearchResponse(
            songs: buckets.songs,
            albums: buckets.albums,
            artists: buckets.artists,
            playlists: buckets.playlists,
            podcastShows: buckets.podcastShows,
            sections: sections,
            continuationToken: nil
        )
    }

    /// Intermediate shape between parsing and final `SearchSection`. Lets the
    /// outer `parse(...)` assign ids once the full ordered list is known,
    /// keeping ids decoupled from item content for stability across re-queries.
    private struct DraftSection {
        let title: String?
        let isTopResult: Bool
        let items: [SearchResultItem]
    }

    /// Collected results by type. Lifts the previously six-arg `appendItem` into
    /// a single value, which keeps the parameter count down and makes adding new
    /// result types in the future a one-line change.
    private struct SearchResultBuckets {
        var songs: [Song] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var playlists: [Playlist] = []
        var podcastShows: [PodcastShow] = []

        mutating func append(_ item: SearchResultItem) {
            switch item {
            case let .song(song): self.songs.append(song)
            case let .album(album): self.albums.append(album)
            case let .artist(artist): self.artists.append(artist)
            case let .playlist(playlist): self.playlists.append(playlist)
            case let .podcastShow(show): self.podcastShows.append(show)
            }
        }
    }

    /// Parses one section of the search response into zero or more `SearchSection`s.
    ///
    /// "All" search results arrive as a mix of `musicCardShelfRenderer` (Top result),
    /// `musicShelfRenderer` (Songs / Albums / Artists / Playlists shelves), and
    /// occasionally `itemSectionRenderer` wrappers around either. An itemSectionRenderer
    /// returns the recursively-parsed inner sections so order is preserved through wrappers.
    private static func parseSearchSections(_ sectionData: [String: Any], depth: Int = 0) -> [DraftSection] {
        // Real responses nest itemSectionRenderer wrappers one or two levels; cap
        // descent so an adversarial deeply-nested response can't overflow the stack.
        guard depth < 16 else {
            self.logger.debug("SearchResponseParser: itemSectionRenderer nesting exceeded depth cap; ignoring deeper wrappers")
            return []
        }

        var sections: [DraftSection] = []

        if let cardShelfRenderer = sectionData["musicCardShelfRenderer"] as? [String: Any] {
            var items: [SearchResultItem] = []
            if let topItem = parseCardShelfRenderer(cardShelfRenderer) {
                items.append(topItem)
            }
            // The top-result card also carries a `contents` array of related songs
            // underneath the headline result; without this they were dropped.
            if let cardContents = cardShelfRenderer["contents"] as? [[String: Any]] {
                for itemData in cardContents {
                    if let item = parseSearchResultItem(itemData) {
                        items.append(item)
                    }
                }
            }
            if !items.isEmpty {
                sections.append(DraftSection(title: nil, isTopResult: true, items: items))
            }
        }

        if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any] {
            let shelfTitle = ParsingHelpers.extractTitle(from: shelfRenderer)
            var items: [SearchResultItem] = []
            if let shelfContents = shelfRenderer["contents"] as? [[String: Any]] {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData) {
                        items.append(item)
                    }
                }
            }
            if !items.isEmpty {
                sections.append(DraftSection(title: shelfTitle, isTopResult: false, items: items))
            }
        }

        if let itemSection = sectionData["itemSectionRenderer"] as? [String: Any],
           let inner = itemSection["contents"] as? [[String: Any]]
        {
            for nested in inner {
                sections.append(contentsOf: Self.parseSearchSections(nested, depth: depth + 1))
            }
        }

        return sections
    }

    /// Parses a filtered songs-only search response.
    /// Filtered searches have a simpler structure without tabs.
    static func parseSongsOnly(_ data: [String: Any]) -> [Song] {
        var songs: [Song] = []

        // Filtered search has a simpler structure - no tabs
        guard let contents = data["contents"] as? [String: Any],
              let sectionListRenderer = contents["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            // Try tabbed structure as fallback
            let response = self.parse(data)
            return response.songs
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData),
                       case let .song(song) = item
                    {
                        songs.append(song)
                    }
                }
            }
        }

        return songs
    }

    // MARK: - Item Parsing

    /// Parses a musicCardShelfRenderer (Top Result section).
    /// This renderer contains a single prominent result with title, subtitle, and browse endpoint.
    private static func parseCardShelfRenderer(_ data: [String: Any]) -> SearchResultItem? {
        // Extract title and navigation from the title runs
        guard let titleData = data["title"] as? [String: Any],
              let runs = titleData["runs"] as? [[String: Any]],
              let firstRun = runs.first,
              let title = firstRun["text"] as? String,
              let navigationEndpoint = firstRun["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String
        else {
            return nil
        }

        // Extract thumbnail
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

        // Extract subtitle
        var subtitle: String?
        if let subtitleData = data["subtitle"] as? [String: Any],
           let subtitleRuns = subtitleData["runs"] as? [[String: Any]]
        {
            subtitle = subtitleRuns.compactMap { $0["text"] as? String }.joined()
        }

        let pageType = ParsingHelpers.extractPageType(from: browseEndpoint)
        return self.createItemFromBrowseEndpoint(
            browseId: browseId,
            pageType: pageType,
            title: title,
            thumbnailURL: thumbnailURL,
            subtitle: subtitle
        )
    }

    private static func parseSearchResultItem(_ data: [String: Any]) -> SearchResultItem? {
        guard let responsiveRenderer = data["musicResponsiveListItemRenderer"] as? [String: Any] else {
            return nil
        }

        // Try to get videoId for songs
        if let playlistItemData = responsiveRenderer["playlistItemData"] as? [String: Any],
           let videoId = playlistItemData["videoId"] as? String
        {
            return self.parseSongFromResponsiveRenderer(responsiveRenderer, videoId: videoId)
        }

        // Check navigation endpoint for other types
        if let navigationEndpoint = responsiveRenderer["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
           let browseId = browseEndpoint["browseId"] as? String
        {
            let thumbnails = ParsingHelpers.extractThumbnails(from: responsiveRenderer)
            let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
            let title = ParsingHelpers.extractTitleFromFlexColumns(responsiveRenderer) ?? "Unknown"
            let subtitle = ParsingHelpers.extractSubtitleFromFlexColumns(responsiveRenderer)

            let pageType = ParsingHelpers.extractPageType(from: browseEndpoint)
            return self.createItemFromBrowseEndpoint(
                browseId: browseId,
                pageType: pageType,
                title: title,
                thumbnailURL: thumbnailURL,
                subtitle: subtitle
            )
        }

        return nil
    }

    // MARK: - Helpers

    private static func createItemFromBrowseEndpoint(
        browseId: String,
        pageType: String?,
        title: String,
        thumbnailURL: URL?,
        subtitle: String?
    ) -> SearchResultItem? {
        if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPRE") || browseId.hasPrefix("OLAK") {
            let album = Album(
                id: browseId,
                title: title,
                artists: nil,
                thumbnailURL: thumbnailURL,
                year: nil,
                trackCount: nil
            )
            return .album(album)
        }

        if ParsingHelpers.isArtistPageType(pageType) || Artist.isNavigableId(browseId) {
            let artist = Artist(id: browseId, name: title, thumbnailURL: thumbnailURL)
            return .artist(artist)
        }

        if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" || browseId.hasPrefix("VL") || browseId.hasPrefix("PL") {
            let playlist = Playlist(
                id: browseId,
                title: title,
                description: nil,
                thumbnailURL: thumbnailURL,
                trackCount: nil,
                author: subtitle
            )
            return .playlist(playlist)
        }

        if pageType == "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE" || browseId.hasPrefix("MPSPP") {
            let show = PodcastShow(
                id: browseId,
                title: title,
                author: subtitle,
                description: nil,
                thumbnailURL: thumbnailURL,
                episodeCount: nil
            )
            return .podcastShow(show)
        }

        return nil
    }

    private static func parseSongFromResponsiveRenderer(
        _ data: [String: Any],
        videoId: String
    ) -> SearchResultItem? {
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        let title = ParsingHelpers.extractTitleFromFlexColumns(data) ?? "Unknown"
        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)
        let album = ParsingHelpers.extractAlbumFromFlexColumns(data)

        let song = Song(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            duration: nil,
            thumbnailURL: thumbnailURL,
            videoId: videoId
        )
        return .song(song)
    }

    // MARK: - Filtered Search Parsing

    /// Extracts the continuation token from a filtered search response.
    private static func extractContinuationToken(from sectionListRenderer: [String: Any]) -> String? {
        // Legacy format: continuations[].nextContinuationData.continuation
        if let continuations = sectionListRenderer["continuations"] as? [[String: Any]],
           let firstContinuation = continuations.first,
           let nextContinuationData = firstContinuation["nextContinuationData"] as? [String: Any],
           let token = nextContinuationData["continuation"] as? String
        {
            return token
        }

        // 2025 format: a trailing continuationItemRenderer is appended to the
        // section contents instead of a continuations array.
        if let contents = sectionListRenderer["contents"] as? [[String: Any]],
           let token = Self.extractTokenFromContents(contents)
        {
            return token
        }
        return nil
    }

    /// Extracts a continuation token from the trailing `continuationItemRenderer`
    /// in a contents array (2025 format), mirroring the playlist parser.
    private static func extractTokenFromContents(_ contents: [[String: Any]]) -> String? {
        guard let lastItem = contents.last,
              let continuationItemRenderer = lastItem["continuationItemRenderer"] as? [String: Any],
              let continuationEndpoint = continuationItemRenderer["continuationEndpoint"] as? [String: Any],
              let continuationCommand = continuationEndpoint["continuationCommand"] as? [String: Any],
              let token = continuationCommand["token"] as? String
        else {
            return nil
        }
        return token
    }

    /// Helper to get sectionListRenderer from filtered search response.
    private static func getSectionListRenderer(from data: [String: Any]) -> [String: Any]? {
        // Try filtered search structure first (no tabs)
        if let contents = data["contents"] as? [String: Any],
           let sectionListRenderer = contents["sectionListRenderer"] as? [String: Any]
        {
            return sectionListRenderer
        }

        // Try tabbed structure as fallback
        if let contents = data["contents"] as? [String: Any],
           let tabbedSearchResults = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbedSearchResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any]
        {
            return sectionListRenderer
        }

        return nil
    }

    /// Parses albums from a filtered search response with continuation token.
    static func parseAlbumsOnly(_ data: [String: Any]) -> ([Album], String?) {
        var albums: [Album] = []

        guard let sectionListRenderer = getSectionListRenderer(from: data),
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return ([], nil)
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData),
                       case let .album(album) = item
                    {
                        albums.append(album)
                    }
                }
            }
        }

        let token = Self.extractContinuationToken(from: sectionListRenderer)
        return (albums, token)
    }

    /// Parses artists from a filtered search response with continuation token.
    static func parseArtistsOnly(_ data: [String: Any]) -> ([Artist], String?) {
        var artists: [Artist] = []

        guard let sectionListRenderer = getSectionListRenderer(from: data),
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return ([], nil)
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData),
                       case let .artist(artist) = item
                    {
                        artists.append(artist)
                    }
                }
            }
        }

        let token = Self.extractContinuationToken(from: sectionListRenderer)
        return (artists, token)
    }

    /// Parses playlists from a filtered search response with continuation token.
    static func parsePlaylistsOnly(_ data: [String: Any]) -> ([Playlist], String?) {
        var playlists: [Playlist] = []

        guard let sectionListRenderer = getSectionListRenderer(from: data),
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return ([], nil)
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData),
                       case let .playlist(playlist) = item
                    {
                        playlists.append(playlist)
                    }
                }
            }
        }

        let token = Self.extractContinuationToken(from: sectionListRenderer)
        return (playlists, token)
    }

    /// Parses podcasts from a filtered search response with continuation token.
    static func parsePodcastsOnly(_ data: [String: Any]) -> ([PodcastShow], String?) {
        var podcasts: [PodcastShow] = []

        guard let sectionListRenderer = getSectionListRenderer(from: data),
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return ([], nil)
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let show = Self.parsePodcastShowFromSearchResult(itemData) {
                        podcasts.append(show)
                    }
                }
            }
        }

        let token = Self.extractContinuationToken(from: sectionListRenderer)
        return (podcasts, token)
    }

    /// Parses a podcast show from a search result item.
    private static func parsePodcastShowFromSearchResult(_ data: [String: Any]) -> PodcastShow? {
        guard let responsiveRenderer = data["musicResponsiveListItemRenderer"] as? [String: Any] else {
            return nil
        }

        // Check navigation endpoint for browse ID
        guard let navigationEndpoint = responsiveRenderer["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String,
              browseId.hasPrefix("MPSPP")
        else {
            return nil
        }

        let thumbnails = ParsingHelpers.extractThumbnails(from: responsiveRenderer)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        let title = ParsingHelpers.extractTitleFromFlexColumns(responsiveRenderer) ?? "Unknown Podcast"
        let author = ParsingHelpers.extractSubtitleFromFlexColumns(responsiveRenderer)

        return PodcastShow(
            id: browseId,
            title: title,
            author: author,
            description: nil,
            thumbnailURL: thumbnailURL,
            episodeCount: nil
        )
    }

    /// Parses songs from a filtered search response with continuation token.
    static func parseSongsWithContinuation(_ data: [String: Any]) -> ([Song], String?) {
        var songs: [Song] = []

        guard let sectionListRenderer = getSectionListRenderer(from: data),
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return ([], nil)
        }

        for sectionData in sectionContents {
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for itemData in shelfContents {
                    if let item = parseSearchResultItem(itemData),
                       case let .song(song) = item
                    {
                        songs.append(song)
                    }
                }
            }
        }

        let token = Self.extractContinuationToken(from: sectionListRenderer)
        return (songs, token)
    }

    /// Parses a search continuation response.
    /// Returns a SearchResponse with all item types and optional continuation token.
    static func parseContinuation(_ data: [String: Any]) -> SearchResponse {
        var buckets = SearchResultBuckets()
        var continuationToken: String?

        // Legacy continuation structure: continuationContents.musicShelfContinuation
        if let continuationContents = data["continuationContents"] as? [String: Any],
           let musicShelfContinuation = continuationContents["musicShelfContinuation"] as? [String: Any]
        {
            // Parse items
            if let contents = musicShelfContinuation["contents"] as? [[String: Any]] {
                for itemData in contents {
                    // Try to parse as podcast show first (for podcast search continuation)
                    if let show = Self.parsePodcastShowFromSearchResult(itemData) {
                        buckets.podcastShows.append(show)
                    } else if let item = parseSearchResultItem(itemData) {
                        buckets.append(item)
                    }
                }
            }

            // Extract next continuation token
            if let continuations = musicShelfContinuation["continuations"] as? [[String: Any]],
               let firstContinuation = continuations.first,
               let nextContinuationData = firstContinuation["nextContinuationData"] as? [String: Any],
               let token = nextContinuationData["continuation"] as? String
            {
                continuationToken = token
            }
        } else if let onResponseReceivedActions = data["onResponseReceivedActions"] as? [[String: Any]],
                  let firstAction = onResponseReceivedActions.first,
                  let appendAction = firstAction["appendContinuationItemsAction"] as? [String: Any],
                  let continuationItems = appendAction["continuationItems"] as? [[String: Any]]
        {
            // 2025 continuation structure: onResponseReceivedActions ->
            // appendContinuationItemsAction -> continuationItems, with a trailing
            // continuationItemRenderer carrying the next token.
            for itemData in continuationItems {
                if let show = Self.parsePodcastShowFromSearchResult(itemData) {
                    buckets.podcastShows.append(show)
                } else if let item = parseSearchResultItem(itemData) {
                    buckets.append(item)
                }
            }
            continuationToken = Self.extractTokenFromContents(continuationItems)
        }

        return SearchResponse(
            songs: buckets.songs,
            albums: buckets.albums,
            artists: buckets.artists,
            playlists: buckets.playlists,
            podcastShows: buckets.podcastShows,
            continuationToken: continuationToken
        )
    }
}
