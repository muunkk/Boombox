# Home & Lists UX Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Boombox's Home read as distinct recommendation shelves, give list rows play-on-hover parity, and add search/sort to Liked Songs.

**Architecture:** A computed `SectionLayout` classifies each `HomeSection` into `quickPicks` / `cardShelf` / `songList`, driving Home rendering. A reusable `MusicListRow` (with a play-on-hover thumbnail overlay) backs Home song-list rows, the new `QuickPicksCarousel`, and Liked Songs. `LikedMusicViewModel` gains client-side search/sort with auto-load-all-on-search.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, Swift Testing.

## Global Constraints

- Target Swift 6.0+, macOS 26.0+. All new SwiftUI types annotated `@available(macOS 26.0, *)`.
- No third-party dependencies.
- `@Observable` classes are `@MainActor`. No `DispatchQueue`; use `async`/`await`.
- No `print()` — use `DiagnosticsLogger`. No force-unwraps.
- SwiftFormat `--self insert` is on: in instance methods use `self.property`; in static methods call siblings via `Self.method()`.
- New unit tests use Swift Testing (`@Test`, `#expect`) with an existing tag (`.model` or `.viewModel`), mirroring `Tests/KasetTests/NewReleasesViewModelTests.swift`.
- Verify each task with: `swift build`, `swiftlint --strict`, `swiftformat .`, and (for logic tasks) `swift test --skip KasetUITests`. Never combine unit and UI tests.
- Commit after each task. End commit messages with `Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc`.
- Branch: `feature/home-lists-ux-pass` (already created).

---

### Task 1: `SectionLayout` classification

**Files:**
- Create: `Sources/Kaset/Models/SectionLayout.swift`
- Modify: `Sources/Kaset/ViewModels/HomeViewModel.swift:17-25` (use the model's `isQuickPicks`)
- Test: `Tests/KasetTests/SectionLayoutTests.swift`

**Interfaces:**
- Produces: `enum SectionLayout { case quickPicks, cardShelf, songList }`;
  `extension HomeSection { var isQuickPicks: Bool; var layout: SectionLayout }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/KasetTests/SectionLayoutTests.swift
import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.model), .timeLimit(.minutes(1)))
struct SectionLayoutTests {
    private func section(title: String, items: [HomeSectionItem]) -> HomeSection {
        HomeSection(id: title, title: title, items: items)
    }

    @Test("Quick Picks title classifies as quickPicks even with song items")
    func quickPicksByTitle() {
        let items = TestFixtures.makeSongs(count: 4).map { HomeSectionItem.song($0) }
        #expect(self.section(title: "Quick picks", items: items).layout == .quickPicks)
    }

    @Test("Predominantly non-song items classify as cardShelf")
    func cardShelfForNonSongs() {
        let items: [HomeSectionItem] = [
            .album(TestFixtures.makeAlbum(id: "a1")),
            .playlist(TestFixtures.makePlaylist(id: "p1")),
            .artist(TestFixtures.makeArtist(id: "ar1")),
        ]
        #expect(self.section(title: "Mixed for you", items: items).layout == .cardShelf)
    }

    @Test("Predominantly song items classify as songList")
    func songListForSongs() {
        let items = TestFixtures.makeSongs(count: 5).map { HomeSectionItem.song($0) }
        #expect(self.section(title: "Listen again", items: items).layout == .songList)
    }

    @Test("Equal song/non-song counts tie-break to songList")
    func tieBreakToSongList() {
        let items: [HomeSectionItem] = [
            .song(TestFixtures.makeSong(id: "s1")),
            .album(TestFixtures.makeAlbum(id: "a1")),
        ]
        #expect(self.section(title: "Mix", items: items).layout == .songList)
    }

    @Test("isQuickPicks is case-insensitive and substring-based")
    func isQuickPicksMatch() {
        #expect(self.section(title: "Your QUICK PICKS", items: []).isQuickPicks)
        #expect(!self.section(title: "Listen again", items: []).isQuickPicks)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --skip KasetUITests --filter SectionLayoutTests`
Expected: FAIL — `value of type 'HomeSection' has no member 'layout'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Kaset/Models/SectionLayout.swift
import Foundation

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
```

- [ ] **Step 4: Point HomeViewModel at the shared `isQuickPicks`**

In `Sources/Kaset/ViewModels/HomeViewModel.swift`, delete the private `isQuickPicks(_:)` (lines 23-25) and update `displaySections` (lines 17-21):

```swift
    var displaySections: [HomeSection] {
        let pinned = self.sections.filter { $0.isQuickPicks }
        let rest = self.sections.filter { !$0.isQuickPicks }
        return pinned + rest
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --skip KasetUITests --filter SectionLayoutTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add Sources/Kaset/Models/SectionLayout.swift Sources/Kaset/ViewModels/HomeViewModel.swift Tests/KasetTests/SectionLayoutTests.swift
git commit -m "feat(home): add SectionLayout classification for home sections

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 2: `MusicListRow` reusable hover-play row

**Files:**
- Create: `Sources/Kaset/Views/SharedViews/MusicListRow.swift`

**Interfaces:**
- Produces: `MusicListRow<Thumbnail: View, Trailing: View>` with initializer
  parameters `title: String`, `subtitle: String?`, `rank: Int? = nil`,
  `thumbSize: CGFloat = 48`, `thumbnailCornerRadius: CGFloat = 6`,
  `verticalPadding: CGFloat = 6`, `cornerRadius: CGFloat = 6`,
  `onPlay: () -> Void`, `@ViewBuilder thumbnail: () -> Thumbnail`,
  `@ViewBuilder trailing: () -> Trailing`.
- Contract: the caller's `thumbnail()` is responsible for its own size/clip
  (sized to `thumbSize`, clipped to `thumbnailCornerRadius`); `MusicListRow`
  draws the hover dim + `play.fill` overlay sized to match.

**Note:** SwiftUI views are not unit-tested in this codebase; verify via build + `#Preview` + manual QA in later tasks.

- [ ] **Step 1: Create the component**

```swift
// Sources/Kaset/Views/SharedViews/MusicListRow.swift
import SwiftUI

/// A reusable list row with a play-on-hover thumbnail overlay.
/// Used by Home song-list sections, the Quick Picks carousel, and Liked Songs.
///
/// The caller supplies `thumbnail` already sized to `thumbSize` and clipped to
/// `thumbnailCornerRadius`; this view overlays a dim + play glyph on hover.
@available(macOS 26.0, *)
struct MusicListRow<Thumbnail: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    var rank: Int?
    var thumbSize: CGFloat
    var thumbnailCornerRadius: CGFloat
    var verticalPadding: CGFloat
    var cornerRadius: CGFloat
    let onPlay: () -> Void
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String?,
        rank: Int? = nil,
        thumbSize: CGFloat = 48,
        thumbnailCornerRadius: CGFloat = 6,
        verticalPadding: CGFloat = 6,
        cornerRadius: CGFloat = 6,
        onPlay: @escaping () -> Void,
        @ViewBuilder thumbnail: @escaping () -> Thumbnail,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rank = rank
        self.thumbSize = thumbSize
        self.thumbnailCornerRadius = thumbnailCornerRadius
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.onPlay = onPlay
        self.thumbnail = thumbnail
        self.trailing = trailing
    }

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 12) {
                if let rank = self.rank {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                        .monospacedDigit()
                }

                ZStack {
                    self.thumbnail()
                    if self.isHovering {
                        RoundedRectangle(cornerRadius: self.thumbnailCornerRadius)
                            .fill(.black.opacity(0.45))
                            .frame(width: self.thumbSize, height: self.thumbSize)
                        Image(systemName: "play.fill")
                            .font(.system(size: self.thumbSize * 0.34, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .pointingHandCursor()

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = self.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                self.trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, self.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow(cornerRadius: self.cornerRadius))
        .animation(.easeInOut(duration: 0.12), value: self.isHovering)
        .onHover { hovering in
            self.isHovering = hovering
        }
    }
}
```

- [ ] **Step 2: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors. (A generic SwiftUI view with no usages yet still compiles.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Kaset/Views/SharedViews/MusicListRow.swift
git commit -m "feat(ui): add reusable MusicListRow with play-on-hover overlay

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 3: Adopt `MusicListRow` in Home song-list rows (fix hover gap)

**Files:**
- Modify: `Sources/Kaset/Views/HomeView.swift:180-223` (replace `sectionListRow` body)

**Interfaces:**
- Consumes: `MusicListRow` (Task 2); existing `self.listThumbnail(for:size:)`
  (HomeView.swift:226-247, already frames+clips, artist = circle) and
  `self.listKindIcon(for:)` (HomeView.swift:249-256).
- Produces: unchanged `sectionListRow(item:rank:thumbSize:verticalPadding:action:)` signature.

**Note:** View change — verify via build + manual QA (Home in list mode shows play.fill on row hover).

- [ ] **Step 1: Replace `sectionListRow`**

Replace the whole `private func sectionListRow(...)` (HomeView.swift:180-223) with:

```swift
    private func sectionListRow(
        item: HomeSectionItem,
        rank: Int?,
        thumbSize: CGFloat,
        verticalPadding: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        let thumbCorner: CGFloat = {
            if case .artist = item { return thumbSize / 2 }
            return 6
        }()

        return MusicListRow(
            title: item.title,
            subtitle: item.subtitle,
            rank: rank,
            thumbSize: thumbSize,
            thumbnailCornerRadius: thumbCorner,
            verticalPadding: verticalPadding,
            onPlay: action,
            thumbnail: { self.listThumbnail(for: item, size: thumbSize) },
            trailing: {
                Image(systemName: self.listKindIcon(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        )
    }
```

- [ ] **Step 2: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors.

- [ ] **Step 3: Manual verification**

Run the app (`Scripts/compile_and_run.sh`). Switch to list mode (Display Mode picker in the window toolbar / `MainWindow.swift:327`). On Home, hover a song row in a list-mode section → the thumbnail dims and a white `play.fill` appears; clicking plays. Confirm grid mode is unaffected.

- [ ] **Step 4: Commit**

```bash
git add Sources/Kaset/Views/HomeView.swift
git commit -m "feat(home): play-on-hover for list-mode song rows via MusicListRow

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 4: `QuickPicksCarousel` + layout-aware section switch

**Files:**
- Modify: `Sources/Kaset/Views/HomeView.swift:102-141` (rework `sectionView`, add carousel)

**Interfaces:**
- Consumes: `HomeSection.layout` (Task 1), `sectionListRow(...)` (Task 3),
  existing `sectionGridView(_:)` (HomeView.swift:111), `sectionListView(_:)`
  (HomeView.swift:143), `sectionHeader(_:)` (HomeView.swift:174),
  `playItem(_:in:at:)`, `contextMenuItems(for:in:at:)`,
  `self.settings.displayDensity`.

**Note:** View change — verify via build + manual QA.

- [ ] **Step 1: Rework `sectionView` to switch on layout**

Replace `sectionView` (HomeView.swift:102-109) with:

```swift
    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section.layout {
        case .quickPicks:
            self.quickPicksCarousel(section)
        case .cardShelf:
            self.sectionGridView(section)
        case .songList:
            if self.settings.displayMode == .list {
                self.sectionListView(section)
            } else {
                self.sectionGridView(section)
            }
        }
    }
```

- [ ] **Step 2: Add the carousel below `sectionView`**

Insert this method immediately after `sectionView`:

```swift
    /// Quick Picks as a multi-row horizontal carousel of compact song rows,
    /// keeping the shelf vertically compact while staying horizontally scannable.
    private func quickPicksCarousel(_ section: HomeSection) -> some View {
        let isCompact = self.settings.displayDensity == .compact
        let thumbSize: CGFloat = isCompact ? 36 : 44
        let columnWidth: CGFloat = isCompact ? 260 : 300
        let rowsPerColumn = 4

        let columns = stride(from: 0, to: section.items.count, by: rowsPerColumn).map { start in
            Array(section.items[start ..< min(start + rowsPerColumn, section.items.count)])
        }

        return VStack(alignment: .leading, spacing: 12) {
            self.sectionHeader(section)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, column in
                        VStack(spacing: 2) {
                            ForEach(Array(column.enumerated()), id: \.element.id) { rowIndex, item in
                                let globalIndex = columnIndex * rowsPerColumn + rowIndex
                                self.sectionListRow(
                                    item: item,
                                    rank: nil,
                                    thumbSize: thumbSize,
                                    verticalPadding: isCompact ? 4 : 6,
                                    action: { self.playItem(item, in: section, at: globalIndex) }
                                )
                                .contextMenu {
                                    self.contextMenuItems(for: item, in: section, at: globalIndex)
                                }
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
```

- [ ] **Step 3: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors.

- [ ] **Step 4: Manual verification**

Run the app. In **list mode**: Quick Picks renders as a horizontal multi-row carousel (≤4 rows per column, scrolls sideways); album/playlist sections stay horizontal card shelves; song sections (e.g. "Listen again") render as vertical lists. In **grid mode**: Quick Picks also shows the carousel; all other sections unchanged. Verify compact vs regular density both look right.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kaset/Views/HomeView.swift
git commit -m "feat(home): section-type-aware layout + Quick Picks carousel

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 5: Liked Songs search/sort + auto-load-all (view model)

**Files:**
- Modify: `Sources/Kaset/ViewModels/LikedMusicViewModel.swift` (add search/sort state + `displaySongs` + load-all)
- Test: `Tests/KasetTests/LikedMusicSearchSortTests.swift`

**Interfaces:**
- Produces on `LikedMusicViewModel`:
  - `enum SortOrder: String, CaseIterable, Identifiable { case dateAdded, title, artist, duration }` with `var label: String`.
  - `private(set) var searchQuery: String` (default `""`).
  - `var sortOrder: SortOrder` (default `.dateAdded`).
  - `private(set) var isLoadingAll: Bool` (default `false`).
  - `var displaySongs: [Song]` (filter by `searchQuery` over title/artist, then sort by `sortOrder`).
  - `func setSearchQuery(_ query: String)` (stores query; starts/cancels load-all).
  - `func loadAllRemaining() async` (loops `loadMore()` while `hasMore`).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/KasetTests/LikedMusicSearchSortTests.swift
import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct LikedMusicSearchSortTests {
    private func makeViewModel(songs: [Song], pages: [[Song]] = []) async -> LikedMusicViewModel {
        let client = MockYTMusicClient()
        client.likedSongs = songs
        client.likedSongsContinuationSongs = pages
        let viewModel = LikedMusicViewModel(client: client)
        await viewModel.load()
        return viewModel
    }

    @Test("Empty query returns all songs in source order")
    func emptyQueryReturnsSourceOrder() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Banana"),
            TestFixtures.makeSong(id: "s2", title: "Apple"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        #expect(viewModel.displaySongs.map(\.id) == ["s1", "s2"])
    }

    @Test("Search filters by title and artist case-insensitively")
    func searchFilters() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Hello World", artistName: "Adele"),
            TestFixtures.makeSong(id: "s2", title: "Other", artistName: "ADELE"),
            TestFixtures.makeSong(id: "s3", title: "Nope", artistName: "Someone"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.setSearchQuery("adele")
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s1", "s2"])

        viewModel.setSearchQuery("hello")
        #expect(viewModel.displaySongs.map(\.id) == ["s1"])
    }

    @Test("Sort by title orders alphabetically")
    func sortByTitle() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "Banana"),
            TestFixtures.makeSong(id: "s2", title: "apple"),
            TestFixtures.makeSong(id: "s3", title: "Cherry"),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.sortOrder = .title
        #expect(viewModel.displaySongs.map(\.id) == ["s2", "s1", "s3"])
    }

    @Test("Sort by duration orders ascending")
    func sortByDuration() async {
        let songs = [
            TestFixtures.makeSong(id: "s1", title: "A", duration: 300),
            TestFixtures.makeSong(id: "s2", title: "B", duration: 120),
            TestFixtures.makeSong(id: "s3", title: "C", duration: 200),
        ]
        let viewModel = await self.makeViewModel(songs: songs)
        viewModel.sortOrder = .duration
        #expect(viewModel.displaySongs.map(\.id) == ["s2", "s3", "s1"])
    }

    @Test("loadAllRemaining drains all continuation pages")
    func loadAllDrainsPages() async {
        let page0 = [TestFixtures.makeSong(id: "s0", title: "Zero")]
        let page1 = [TestFixtures.makeSong(id: "s1", title: "One")]
        let page2 = [TestFixtures.makeSong(id: "s2", title: "Two")]
        let viewModel = await self.makeViewModel(songs: page0, pages: [page1, page2])
        #expect(viewModel.hasMore == true)

        await viewModel.loadAllRemaining()

        #expect(viewModel.hasMore == false)
        #expect(viewModel.isLoadingAll == false)
        #expect(Set(viewModel.displaySongs.map(\.id)) == ["s0", "s1", "s2"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --skip KasetUITests --filter LikedMusicSearchSortTests`
Expected: FAIL — `value of type 'LikedMusicViewModel' has no member 'displaySongs'`.

- [ ] **Step 3: Implement search/sort/load-all**

In `Sources/Kaset/ViewModels/LikedMusicViewModel.swift`, add the sort enum at the top of the class body (after the `LiveSyncTask` struct), the new stored state near `songs`, and the methods. Concretely:

```swift
    /// Sort orders offered in the Liked Songs UI.
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateAdded
        case title
        case artist
        case duration

        var id: String { self.rawValue }

        var label: String {
            switch self {
            case .dateAdded: String(localized: "Recently Added")
            case .title: String(localized: "Title")
            case .artist: String(localized: "Artist")
            case .duration: String(localized: "Duration")
            }
        }
    }

    /// Active search query (filters title/artist). Set via `setSearchQuery`.
    private(set) var searchQuery: String = ""

    /// Active sort order.
    var sortOrder: SortOrder = .dateAdded

    /// Whether a background "load all pages for search" pass is running.
    private(set) var isLoadingAll = false

    @ObservationIgnored
    private var loadAllTask: Task<Void, Never>?

    /// Songs after applying the active search filter and sort order.
    var displaySongs: [Song] {
        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let filtered: [Song]
        if query.isEmpty {
            filtered = self.songs
        } else {
            filtered = self.songs.filter { song in
                song.title.localizedLowercase.contains(query)
                    || song.artistsDisplay.localizedLowercase.contains(query)
            }
        }

        switch self.sortOrder {
        case .dateAdded:
            return filtered
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted { $0.artistsDisplay.localizedCaseInsensitiveCompare($1.artistsDisplay) == .orderedAscending }
        case .duration:
            return filtered.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    /// Updates the search query. When non-empty, drains all remaining pages in
    /// the background so results are complete (the liked feed is paginated and
    /// has no server-side within-playlist search). When cleared, cancels that pass.
    func setSearchQuery(_ query: String) {
        self.searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.loadAllTask?.cancel()
            self.loadAllTask = nil
            self.isLoadingAll = false
        } else if self.hasMore, self.loadAllTask == nil {
            self.loadAllTask = Task { [weak self] in
                await self?.loadAllRemaining()
            }
        }
    }

    /// Loads every remaining liked-songs page by repeatedly calling `loadMore`.
    func loadAllRemaining() async {
        guard self.hasMore else { return }
        self.isLoadingAll = true
        defer {
            self.isLoadingAll = false
            self.loadAllTask = nil
        }
        while self.hasMore, !Task.isCancelled {
            await self.loadMore()
        }
    }
```

Also cancel the load-all pass in `refresh()` — update `refresh()` (around line 166) to add `self.loadAllTask?.cancel(); self.loadAllTask = nil; self.isLoadingAll = false; self.searchQuery = ""` before `await self.load()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --skip KasetUITests --filter LikedMusicSearchSortTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Kaset/ViewModels/LikedMusicViewModel.swift Tests/KasetTests/LikedMusicSearchSortTests.swift
git commit -m "feat(liked): search + sort with auto-load-all in view model

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 6: Liked Songs UI — search field, sort menu, adopt `MusicListRow`

**Files:**
- Modify: `Sources/Kaset/Views/LikedMusicView.swift` (header controls; switch rows to `displaySongs` + `MusicListRow`)

**Interfaces:**
- Consumes: `LikedMusicViewModel.displaySongs`, `.searchQuery`, `.setSearchQuery(_:)`,
  `.sortOrder`, `.isLoadingAll` (Task 5); `MusicListRow` (Task 2);
  existing `SongThumbnailView(song:)`, `playerService.playQueue(_:startingAt:)`.

**Note:** View change — verify via build + manual QA.

- [ ] **Step 1: Add search + sort controls to the header**

In `LikedMusicView`, add local search state near the other `@State` (after line 13):

```swift
    @State private var searchText = ""
```

Add a controls row. Insert a new `searchAndSortBar` view and place it under the header in `contentView` (after the `headerView` block, before "Songs list"):

```swift
    private var searchAndSortBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search liked songs"), text: self.$searchText)
                    .textFieldStyle(.plain)
                if self.viewModel.isLoadingAll {
                    ProgressView().controlSize(.small)
                } else if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            .frame(maxWidth: 320)

            Spacer()

            Menu {
                Picker(String(localized: "Sort By"), selection: self.$viewModel.sortOrder) {
                    ForEach(LikedMusicViewModel.SortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Label(self.viewModel.sortOrder.label, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .onChange(of: self.searchText) { _, newValue in
            self.viewModel.setSearchQuery(newValue)
        }
    }
```

Note: `self.$viewModel.sortOrder` requires the view model to be observable-bindable; `@State var viewModel` of an `@Observable` type supports `$` bindings in macOS 26 SwiftUI. If the compiler rejects the `Picker` binding, wrap with `@Bindable var viewModel = self.viewModel` inside `searchAndSortBar`.

Insert into `contentView`'s `LazyVStack` right after the `headerView` modifier block:

```swift
                self.searchAndSortBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
```

- [ ] **Step 2: Drive the list from `displaySongs` and switch rows to `MusicListRow`**

In `contentView`, replace `self.viewModel.songs` with `self.viewModel.displaySongs` in the `isEmpty` check, the `ForEach`, the pagination `.task` (`index >= self.viewModel.displaySongs.count - 3`), and the divider bound. Replace the `songRow(_:index:)` body's row label with `MusicListRow` while keeping the existing `.contextMenu`. Concretely, replace `songRow` (lines 179-299) with:

```swift
    private func songRow(_ song: Song, index: Int) -> some View {
        MusicListRow(
            title: song.title,
            subtitle: song.artistsDisplay,
            thumbSize: 48,
            verticalPadding: 8,
            onPlay: {
                Task {
                    await self.playerService.playQueue(self.viewModel.displaySongs, startingAt: index)
                }
            },
            thumbnail: { SongThumbnailView(song: song) },
            trailing: {
                Text(song.durationDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        )
        .contextMenu {
            AddToQueueContextMenu(song: song, playerService: self.playerService)

            Divider()

            Button {
                Task { await self.playerService.play(song: song) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: song, manager: self.favoritesManager)

            Divider()

            Button {
                SongActionsHelper.unlikeSong(song, likeStatusManager: self.likeStatusManager)
            } label: {
                Label("Unlike", systemImage: "hand.thumbsup.fill")
            }

            Divider()

            StartRadioContextMenu.menuItem(for: song, playerService: self.playerService)

            Divider()

            ShareContextMenu.menuItem(for: song)

            Divider()

            if let artist = song.artists.first(where: { $0.hasNavigableId }) {
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "person")
                }
            }

            if let album = song.album, album.hasNavigableId {
                let playlist = Playlist(
                    id: album.id,
                    title: album.title,
                    description: nil,
                    thumbnailURL: album.thumbnailURL ?? song.thumbnailURL,
                    trackCount: album.trackCount,
                    author: album.artistsDisplay
                )
                NavigationLink(value: playlist) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
    }
```

Then delete the now-unused `@State private var hoveredSongId: String?` (line 13) — hover is handled inside `MusicListRow`.

- [ ] **Step 3: Add a "no matches" state when search yields nothing**

In `contentView`, change the empty branch so an active search shows a distinct message. Replace `if self.viewModel.displaySongs.isEmpty {` body to:

```swift
                if self.viewModel.displaySongs.isEmpty {
                    if self.viewModel.searchQuery.isEmpty {
                        self.emptyStateView
                    } else {
                        ContentUnavailableView.search(text: self.viewModel.searchQuery)
                            .frame(minHeight: 200)
                    }
                } else {
```

- [ ] **Step 4: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors. (If the `Picker` binding fails to compile, apply the `@Bindable` workaround noted in Step 1.)

- [ ] **Step 5: Manual verification**

Run the app → Liked Music. Type in the search box: results filter live; on a large library a spinner appears while it loads all pages, then matches from deep in the list appear. Clear search → full list returns. Change the sort menu (Recently Added / Title / Artist / Duration) → order updates. Hover a row → play overlay; click → plays from that row within the filtered/sorted set. "No matching songs" shows for a non-matching query.

- [ ] **Step 6: Commit**

```bash
git add Sources/Kaset/Views/LikedMusicView.swift
git commit -m "feat(liked): search field, sort menu, MusicListRow rows

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 7: Home shelf polish (headers + spacing)

**Files:**
- Modify: `Sources/Kaset/Views/HomeView.swift:174-178` (`sectionHeader`)

**Interfaces:**
- Consumes: existing `sectionHeader(_:)`.

**Scope note:** A "See all ›" affordance is **deferred** — `HomeSection` carries no
per-section browse destination, so there is nothing to navigate to. Adding that
requires model/API plumbing out of scope here. This task does header/spacing polish only.

**Note:** View change — verify via build + manual QA.

- [ ] **Step 1: Refine the section header**

Replace `sectionHeader` (HomeView.swift:174-178) with:

```swift
    private func sectionHeader(_ section: HomeSection) -> some View {
        Text(section.title)
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
```

- [ ] **Step 2: Lint, format, build**

Run: `swiftformat . && swiftlint --strict && swift build`
Expected: no errors.

- [ ] **Step 3: Manual verification**

Run the app. Home section headers read as bold, single-line titles with consistent spacing above each shelf; carousels still scroll cleanly to the content gutter. VoiceOver announces headers as headings.

- [ ] **Step 4: Commit**

```bash
git add Sources/Kaset/Views/HomeView.swift
git commit -m "style(home): consistent bold section headers with heading trait

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

### Task 8: Full QA pass + docs

**Files:**
- Modify: `docs/progress.md`, `docs/user-stories.csv`

- [ ] **Step 1: Full unit + lint + build gate**

Run: `swiftformat . && swiftlint --strict && swift build && swift test --skip KasetUITests`
Expected: build succeeds; all unit tests pass (including `SectionLayoutTests`, `LikedMusicSearchSortTests`).

- [ ] **Step 2: Manual QA matrix (serial; kill stray Boombox/Kaset processes first)**

Run via `Scripts/compile_and_run.sh`. Verify:
- Home **list mode**: Quick Picks carousel; card shelves horizontal; song sections vertical with hover-play.
- Home **grid mode**: Quick Picks carousel; everything else unchanged.
- Density **compact** vs **regular**: both modes render correctly.
- Liked: search (auto-load-all completeness), each sort order, hover-play, "no matches" state, clear-search restores list.

- [ ] **Step 3: Update progress docs**

Add a dated entry to `docs/progress.md` summarizing the Home & Lists UX pass (workstreams A–D, with "See all" deferred), and update the relevant rows in `docs/user-stories.csv`.

- [ ] **Step 4: Commit**

```bash
git add docs/progress.md docs/user-stories.csv
git commit -m "docs: record Home & Lists UX pass QA + status

Claude-Session: https://claude.ai/code/session_0168rgPZJNsgfhqwMN1fK2uc"
```

---

## Self-Review

**Spec coverage:**
- A (home restructure) → Tasks 1 (classification), 4 (carousel + switch). ✓
- B (list hover overlay) → Tasks 2 (component), 3 (Home adoption), 6 (Liked adoption). ✓
- C (Liked search/sort) → Tasks 5 (logic), 6 (UI). ✓
- D (home polish) → Task 7. "See all" explicitly deferred (no destination data) — spec D updated to match.
- Testing/build/QA → each task + Task 8. ✓

**Placeholder scan:** No TBD/TODO; all code shown in full; no "similar to Task N".

**Type consistency:** `SectionLayout`/`isQuickPicks`/`layout` (Task 1) consumed in Task 4; `MusicListRow` initializer params (Task 2) match call sites in Tasks 3, 4, 6; `displaySongs`/`setSearchQuery`/`sortOrder`/`isLoadingAll`/`loadAllRemaining`/`SortOrder` (Task 5) match usages in Task 6 and tests. ✓
