import CryptoKit
import Foundation

// MARK: - ParsingHelpers

/// Provides common utility methods for parsing YouTube Music API responses.
enum ParsingHelpers {
    private static let artistPageTypes: Set<String> = [
        "MUSIC_PAGE_TYPE_ARTIST",
        "MUSIC_PAGE_TYPE_USER_CHANNEL",
        "MUSIC_PAGE_TYPE_LIBRARY_ARTIST",
    ]

    // MARK: - Stable ID Generation

    /// Generates a stable, deterministic ID from content components.
    /// This avoids SwiftUI identity churn caused by UUID() regeneration on refresh.
    /// - Parameters:
    ///   - title: Primary identifying text (section/item title)
    ///   - components: Additional identifying components (first item ID, index, etc.)
    /// - Returns: A stable hex string ID derived from the content hash
    static func stableId(title: String, components: String...) -> String {
        var combined = title
        for component in components {
            combined += "|" + component
        }
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        // Use first 16 bytes (32 hex chars) for a compact but collision-resistant ID
        return hash.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Keywords used to identify chart sections for special rendering.
    static let chartKeywords = [
        "chart",
        "charts",
        "top 100",
        "top 50",
        "trending",
        "daily top",
        "weekly top",
    ]

    /// Checks if a section title indicates a chart section.
    static func isChartSection(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        return self.chartKeywords.contains { lowercased.contains($0) }
    }

    /// Normalizes a URL string by adding https: prefix to protocol-relative URLs.
    static func normalizeURL(_ urlString: String) -> String {
        if urlString.hasPrefix("//") {
            return "https:" + urlString
        }
        return urlString
    }

    /// Extracts thumbnail URLs from various YouTube Music API data structures.
    static func extractThumbnails(from data: [String: Any]) -> [String] {
        if let thumbnail = data["thumbnail"] as? [String: Any] {
            // Try musicThumbnailRenderer (most common)
            if let musicThumbnailRenderer = thumbnail["musicThumbnailRenderer"] as? [String: Any],
               let thumbData = musicThumbnailRenderer["thumbnail"] as? [String: Any],
               let thumbnails = thumbData["thumbnails"] as? [[String: Any]]
            {
                return thumbnails.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }

            // Try croppedSquareThumbnailRenderer (used in library playlists)
            if let croppedRenderer = thumbnail["croppedSquareThumbnailRenderer"] as? [String: Any],
               let thumbnails = croppedRenderer["thumbnail"] as? [String: Any],
               let thumbList = thumbnails["thumbnails"] as? [[String: Any]]
            {
                return thumbList.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }

            // Direct thumbnails array
            if let thumbnails = thumbnail["thumbnails"] as? [[String: Any]] {
                return thumbnails.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }
        }

        // Try thumbnailRenderer at top level (some playlist formats)
        if let thumbnailRenderer = data["thumbnailRenderer"] as? [String: Any] {
            if let musicThumbnailRenderer = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
               let thumbData = musicThumbnailRenderer["thumbnail"] as? [String: Any],
               let thumbnails = thumbData["thumbnails"] as? [[String: Any]]
            {
                return thumbnails.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }

            if let croppedRenderer = thumbnailRenderer["croppedSquareThumbnailRenderer"] as? [String: Any],
               let thumbnails = croppedRenderer["thumbnail"] as? [String: Any],
               let thumbList = thumbnails["thumbnails"] as? [[String: Any]]
            {
                return thumbList.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }
        }

        // Try foregroundThumbnail (used by some album/artist headers)
        if let foregroundThumbnail = data["foregroundThumbnail"] as? [String: Any] {
            if let musicThumbnailRenderer = foregroundThumbnail["musicThumbnailRenderer"] as? [String: Any],
               let thumbData = musicThumbnailRenderer["thumbnail"] as? [String: Any],
               let thumbnails = thumbData["thumbnails"] as? [[String: Any]]
            {
                return thumbnails.compactMap { $0["url"] as? String }.map(self.normalizeURL)
            }
        }

        // Try direct thumbnails array at top level
        if let thumbnails = data["thumbnails"] as? [[String: Any]] {
            return thumbnails.compactMap { $0["url"] as? String }.map(self.normalizeURL)
        }

        return []
    }

    /// Extracts artists from subtitle data.
    static func extractArtists(from data: [String: Any]) -> [Artist] {
        var artists: [Artist] = []

        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]]
        {
            for run in runs {
                if let text = run["text"] as? String,
                   text != " • ", text != " & ", text != ", "
                {
                    if let endpoint = run["navigationEndpoint"] as? [String: Any],
                       let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
                       let artistId = browseEndpoint["browseId"] as? String
                    {
                        artists.append(Artist(id: artistId, name: text))
                    } else if !text.isEmpty {
                        // Generate stable ID from artist name when no browse ID available
                        let stableArtistId = Self.stableId(title: "artist", components: text)
                        artists.append(Artist(id: stableArtistId, name: text))
                    }
                }
            }
        }

        return artists
    }

    /// Extracts subtitle text from data.
    /// Returns the full subtitle text including song counts (e.g., "Playlist • YouTube Music • 145 songs").
    static func extractSubtitle(from data: [String: Any]) -> String? {
        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]]
        {
            let texts = runs.compactMap { $0["text"] as? String }
            let subtitle = texts.joined()
            return subtitle.isEmpty ? nil : subtitle
        }
        return nil
    }

    /// Extracts song count from subtitle data (e.g., "Playlist • 145 songs" → 145).
    static func extractSongCountFromSubtitle(from data: [String: Any]) -> Int? {
        guard let subtitle = extractSubtitle(from: data) else { return nil }
        return Self.extractSongCount(from: subtitle)
    }

    /// Extracts title from runs data.
    static func extractTitle(from data: [String: Any], key: String = "title") -> String? {
        if let titleData = data[key] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String
        {
            return text
        }
        return nil
    }

    /// Extracts video ID from various data structures.
    static func extractVideoId(from data: [String: Any]) -> String? {
        // Try playlistItemData
        if let playlistItemData = data["playlistItemData"] as? [String: Any],
           let videoId = playlistItemData["videoId"] as? String
        {
            return videoId
        }

        // Try navigationEndpoint
        if let endpoint = data["navigationEndpoint"] as? [String: Any],
           let watchEndpoint = endpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String
        {
            return videoId
        }

        // Try overlay
        if let overlay = data["overlay"] as? [String: Any],
           let playButton = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = playButton["content"] as? [String: Any],
           let musicPlayButtonRenderer = content["musicPlayButtonRenderer"] as? [String: Any],
           let endpoint = musicPlayButtonRenderer["playNavigationEndpoint"] as? [String: Any],
           let watchEndpoint = endpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String
        {
            return videoId
        }

        return nil
    }

    /// Extracts browse ID from navigation endpoint.
    static func extractBrowseId(from data: [String: Any]) -> String? {
        if let endpoint = data["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
           let browseId = browseEndpoint["browseId"] as? String
        {
            return browseId
        }
        return nil
    }

    /// Extracts page type from a browse endpoint.
    static func extractPageType(from browseEndpoint: [String: Any]) -> String? {
        if let contextConfigs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
           let musicConfig = contextConfigs["browseEndpointContextMusicConfig"] as? [String: Any],
           let type = musicConfig["pageType"] as? String
        {
            return type
        }
        return nil
    }

    /// Returns whether the page type represents an artist destination.
    static func isArtistPageType(_ pageType: String?) -> Bool {
        guard let pageType else { return false }
        return Self.artistPageTypes.contains(pageType)
    }

    /// Extracts duration from flex columns or fixed columns.
    static func extractDurationFromFlexColumns(_ data: [String: Any]) -> TimeInterval? {
        // Try fixedColumns first (most common for playlist/album tracks)
        if let fixedColumns = data["fixedColumns"] as? [[String: Any]] {
            for column in fixedColumns {
                if let renderer = column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                   let text = renderer["text"] as? [String: Any],
                   let runs = text["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let durationText = firstRun["text"] as? String
                {
                    return self.parseDuration(durationText)
                }
            }
        }

        // Try flexColumns (artist page top songs often have duration in a combined column)
        if let flexColumns = data["flexColumns"] as? [[String: Any]] {
            for column in flexColumns.reversed() {
                if let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let text = renderer["text"] as? [String: Any],
                   let runs = text["runs"] as? [[String: Any]]
                {
                    // Check all runs (duration is often the last run in "Artist • Album • 3:45")
                    // Skip runs with navigationEndpoint to avoid matching album titles like "4:44"
                    for run in runs.reversed() {
                        if let durationText = run["text"] as? String,
                           run["navigationEndpoint"] == nil,
                           let duration = self.parseDuration(durationText)
                        {
                            return duration
                        }
                    }
                }
            }
        }

        // Try overlay play button for duration (used on some artist pages)
        if let overlay = data["overlay"] as? [String: Any],
           let musicItemThumbnailOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = musicItemThumbnailOverlay["content"] as? [String: Any],
           let musicPlayButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let accessibilityData = musicPlayButton["accessibilityPlayData"] as? [String: Any],
           let accessibilityLabel = accessibilityData["accessibilityData"] as? [String: Any],
           let label = accessibilityLabel["label"] as? String
        {
            // Extract duration from accessibility label like "Play Billie Jean by Michael Jackson, 4 minutes, 55 seconds"
            if let duration = extractDurationFromAccessibilityLabel(label) {
                return duration
            }
        }

        return nil
    }

    /// Extracts duration from accessibility label text.
    /// Handles formats like "4 minutes, 55 seconds" or "4:55"
    private static func extractDurationFromAccessibilityLabel(_ label: String) -> TimeInterval? {
        // Try "X minutes, Y seconds" format
        let minutePattern = #"(\d+)\s*minutes?"#
        let secondPattern = #"(\d+)\s*seconds?"#

        var minutes = 0
        var seconds = 0

        if let minuteRegex = try? NSRegularExpression(pattern: minutePattern, options: .caseInsensitive),
           let minuteMatch = minuteRegex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let minuteRange = Range(minuteMatch.range(at: 1), in: label)
        {
            minutes = Int(label[minuteRange]) ?? 0
        }

        if let secondRegex = try? NSRegularExpression(pattern: secondPattern, options: .caseInsensitive),
           let secondMatch = secondRegex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let secondRange = Range(secondMatch.range(at: 1), in: label)
        {
            seconds = Int(label[secondRange]) ?? 0
        }

        if minutes > 0 || seconds > 0 {
            return TimeInterval(minutes * 60 + seconds)
        }

        return nil
    }

    /// Parses a duration string (e.g., "3:45") into seconds.
    static func parseDuration(_ text: String) -> TimeInterval? {
        let components = text.split(separator: ":").compactMap { Int($0) }
        if components.count == 2 {
            return TimeInterval(components[0] * 60 + components[1])
        } else if components.count == 3 {
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        }
        return nil
    }

    /// Extracts subtitle from flex columns.
    /// Returns the full subtitle text including song counts (e.g., "Playlist • YouTube Music • 145 songs").
    static func extractSubtitleFromFlexColumns(_ data: [String: Any]) -> String? {
        if let flexColumns = data["flexColumns"] as? [[String: Any]],
           flexColumns.count > 1,
           let secondColumn = flexColumns[safe: 1],
           let renderer = secondColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let text = renderer["text"] as? [String: Any],
           let runs = text["runs"] as? [[String: Any]]
        {
            let subtitle = runs.compactMap { $0["text"] as? String }.joined()
            return subtitle.isEmpty ? nil : subtitle
        }
        return nil
    }

    /// Extracts song count from flex columns subtitle (e.g., "Playlist • 145 songs" → 145).
    static func extractSongCountFromFlexColumns(_ data: [String: Any]) -> Int? {
        guard let subtitle = extractSubtitleFromFlexColumns(data) else { return nil }
        return Self.extractSongCount(from: subtitle)
    }

    /// Strips song count patterns from a string (e.g., " • 145 songs" or " • 2,429 tracks").
    /// The song count is typically displayed separately in the UI from the actual parsed count.
    static func stripSongCountPattern(from text: String) -> String {
        var result = text.replacingOccurrences(
            of: #" • [\d,]+ (?:songs?|tracks?)"#,
            with: "",
            options: .regularExpression
        )

        // Also strip leading " • " if the result starts with it
        if result.hasPrefix(" • ") {
            result = String(result.dropFirst(3))
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Extracts song count from subtitle text (e.g., "Playlist • YouTube Music • 145 songs" → 145).
    static func extractSongCount(from text: String) -> Int? {
        // Match patterns like "145 songs", "1 song", or "2,429 tracks"
        guard let regex = try? NSRegularExpression(
            pattern: #"([\d,]+)\s+(?:songs?|tracks?)"#,
            options: .caseInsensitive
        ),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let countRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[countRange].replacingOccurrences(of: ",", with: ""))
    }

    /// Extracts title from flex columns.
    static func extractTitleFromFlexColumns(_ data: [String: Any]) -> String? {
        if let flexColumns = data["flexColumns"] as? [[String: Any]],
           let firstColumn = flexColumns.first,
           let renderer = firstColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let text = renderer["text"] as? [String: Any],
           let runs = text["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let title = firstRun["text"] as? String
        {
            return title
        }
        return nil
    }

    /// Known content type keywords that should not be treated as artist names.
    private static let contentTypeKeywords: Set<String> = [
        "Song", "Video", "Album", "Playlist", "Artist", "Episode", "Podcast",
    ]

    /// Extracts artists from flex columns.
    ///
    /// Album track rows on YT Music frequently render the artist as text-only
    /// (no `navigationEndpoint`), because the listing is already scoped to the
    /// album. Returning an empty array in that case made the now-playing card
    /// read "Unknown Artist" even though the artist name was right there. So
    /// when we don't find any navigable artist run, we fall back to the
    /// surviving text-only runs.
    static func extractArtistsFromFlexColumns(_ data: [String: Any]) -> [Artist] {
        guard let flexColumns = data["flexColumns"] as? [[String: Any]],
              flexColumns.count > 1,
              let secondColumn = flexColumns[safe: 1],
              let renderer = secondColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = renderer["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else {
            return []
        }

        var navigableArtists: [Artist] = []
        var textOnlyNames: [String] = []

        for run in runs {
            guard let artistName = run["text"] as? String,
                  !artistName.isEmpty,
                  artistName != " • ", artistName != " & ", artistName != ", ",
                  !Self.contentTypeKeywords.contains(artistName),
                  !Self.looksLikeNonArtistMetadata(artistName)
            else {
                continue
            }

            if let endpoint = run["navigationEndpoint"] as? [String: Any],
               let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String,
               Artist.isNavigableId(browseId)
            {
                navigableArtists.append(Artist(id: browseId, name: artistName))
            } else {
                textOnlyNames.append(artistName)
            }
        }

        if !navigableArtists.isEmpty {
            return navigableArtists
        }

        // Stable hash-derived IDs preserve `Identifiable` uniqueness across multiple
        // text-only artists in the same row without colliding (an empty-string id
        // would). They still fail `hasNavigableId` (no UC/MPLAUC prefix), so any
        // "Go to artist" path correctly stays disabled.
        return textOnlyNames.map {
            Artist(id: Self.stableId(title: "artist", components: $0), name: $0)
        }
    }

    /// Heuristic guard for things that appear in flex columns but are not artists:
    /// durations like "3:45", years like "2024", view counts like "1.2M views".
    /// Used to keep stray subtitle bits from being treated as artist names when
    /// we fall back to text-only runs.
    ///
    /// Anchored on the full trimmed string rather than substring matches — band
    /// names like "Reviews" or "Displays" would otherwise be silently dropped
    /// by a naive `.contains("views")` / `.contains("plays")` check.
    private static func looksLikeNonArtistMetadata(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if self.parseDuration(trimmed) != nil { return true }
        // Plain 4-digit year.
        if trimmed.count == 4, Int(trimmed) != nil { return true }
        // Stat strings like "1.2M views", "234K plays", "12,345 views" —
        // anchored at the end so band names containing "views" don't trip.
        if let regex = try? NSRegularExpression(
            pattern: #"^[\d,.]+\s*[KMB]?\s+(views?|plays?|streams?)$"#,
            options: .caseInsensitive
        ),
            regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
        {
            return true
        }
        return false
    }

    /// Extracts album from flex columns.
    /// Album info is typically in the second or third flex column with a browseId starting with MPRE or OLAK.
    static func extractAlbumFromFlexColumns(_ data: [String: Any]) -> Album? {
        guard let flexColumns = data["flexColumns"] as? [[String: Any]] else {
            return nil
        }

        // Album is typically in the second or third column
        // Look through columns 1, 2, and 3 (indices 1, 2, 3) for album data
        for columnIndex in 1 ..< min(4, flexColumns.count) {
            guard let column = flexColumns[safe: columnIndex],
                  let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                  let text = renderer["text"] as? [String: Any],
                  let runs = text["runs"] as? [[String: Any]]
            else {
                continue
            }

            // Look for a run with a navigation endpoint pointing to an album
            for run in runs {
                guard let albumName = run["text"] as? String,
                      !albumName.isEmpty,
                      albumName != " • ", albumName != " & ", albumName != ", ",
                      let endpoint = run["navigationEndpoint"] as? [String: Any],
                      let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
                      let browseId = browseEndpoint["browseId"] as? String,
                      browseId.hasPrefix("MPRE") || browseId.hasPrefix("OLAK")
                else {
                    continue
                }

                return Album(
                    id: browseId,
                    title: albumName,
                    artists: nil,
                    thumbnailURL: nil,
                    year: nil,
                    trackCount: nil
                )
            }
        }

        return nil
    }
}
