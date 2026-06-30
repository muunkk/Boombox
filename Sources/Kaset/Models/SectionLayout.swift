import Foundation

// MARK: - SectionLayout

/// How a home section should be laid out on screen.
enum SectionLayout: Equatable {
    /// Quick Picks — multi-row horizontal carousel of compact song rows.
    case quickPicks
    /// Recommendation shelf of albums/playlists/artists — horizontal card carousel.
    case cardShelf
    /// Predominantly songs — vertical list (in list mode) of `MusicListRow`s.
    case songList
}

extension HomeSection {
    /// Whether this section is the "Quick Picks" shelf (matched by title).
    var isQuickPicks: Bool {
        self.title.localizedLowercase.contains("quick pick")
    }

    /// Derived layout classification driving Home rendering.
    var layout: SectionLayout {
        if self.isQuickPicks { return .quickPicks }
        let songCount = self.items.reduce(into: 0) { count, item in
            if case .song = item { count += 1 }
        }
        let nonSongCount = self.items.count - songCount
        // Only treat as a card shelf when non-song items are the strict majority;
        // ties and song-majority sections render as vertical song lists.
        return nonSongCount > songCount ? .cardShelf : .songList
    }
}
