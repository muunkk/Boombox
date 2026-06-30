# Home & Lists UX Pass — Design

**Date:** 2026-06-30
**Status:** Approved (pending spec review)
**Branch:** `feature/home-lists-ux-pass`

## Goal

Bring Boombox's Home screen and list views closer to Spotify/Apple Music UX parity.
Recommendations should read as distinct, well-separated **shelves** rather than everything
plopped into cramped multi-column grids; list rows should have play-on-hover parity with
grid cards; and Liked Songs should gain search + sort.

Scope was confirmed with the maintainer as four related workstreams (A–D), built in
dependency order because B is a building block reused by A and C.

## Non-goals

- No changes to playback, the player bar, or queue.
- No AirPods/system-control work (separately determined infeasible).
- No server-side search API work (none exists for within-liked-playlist search).
- Playlists management is explicitly out of scope per maintainer.

## Current state (as-built)

- `HomeView.swift` renders sections from `HomeViewModel.displaySections` inside a
  `LazyVStack` (spacing 32). Each section switches on `settings.displayMode`:
  - **grid mode** → horizontal `ScrollView`/`LazyHStack` of `HomeSectionItemCard` (carousel).
  - **list mode** → adaptive multi-column `LazyVGrid` of bespoke `sectionListRow`s.
    This is the cramped "Quick Picks as 3 columns" the maintainer flagged.
- `HomeSectionItemCard.swift` already has a **play-on-hover overlay** for songs
  (`isHovering` → `play.fill`, scale+opacity transition). List rows do **not**.
- `HomeSection` (`Models/HomeSection.swift`) carries `id`, `title`, `items`, `isChart`.
  `HomeSectionItem` is `.song | .album | .playlist | .artist`.
- Quick Picks is identified by `HomeViewModel.isQuickPicks` (title contains "quick pick"),
  hoisted to the top of `displaySections`.
- `LikedMusicView.swift` is a `LazyVStack` of bespoke `songRow`s with a play-all header;
  **no search, no sort**. `LikedMusicViewModel.songs` is **paginated** (`hasMore`,
  `loadMore()`, auto-loads near list end).
- `displayMode` / `displayDensity` are global `SettingsManager` prefs, toggled in
  `MainWindow.swift:327`, also consumed by `LibraryView`.

## Design

### Shared building blocks (built first)

#### 1. `SectionLayout` classification

Add a computed classification for a home section (in `HomeSection.swift`, or a small
helper next to it):

```
enum SectionLayout {
    case quickPicks   // title matches isQuickPicks → multi-row song carousel
    case cardShelf    // items are album/playlist/artist → horizontal card carousel
    case songList     // song items, not Quick Picks → vertical list of MusicListRow
}
```

Classification rule:
- `.quickPicks` if the existing Quick Picks title match holds.
- else `.cardShelf` if the section's items are predominantly non-`.song`
  (album/playlist/artist).
- else `.songList`.

`isQuickPicks` logic moves to / is shared with this classifier so there is a single
source of truth (HomeViewModel keeps using it for pinning).

#### 2. `MusicListRow` (workstream B)

A single reusable SwiftUI row used by Home `songList` sections, the Quick Picks carousel
cells, and Liked Songs. Responsibilities:

- Leading: optional rank number **or** thumbnail (`thumbSize` configurable for
  compact/regular density).
- **Play-on-hover overlay on the thumbnail**: on hover, artwork dims and a `play.fill`
  fades in (mirrors `HomeSectionItemCard` language: scale + opacity transition). Click =
  play. Hover state is local `@State`.
- Center: title + optional subtitle, single-line, density-aware fonts.
- Trailing: kind icon and/or action affordance (context menu remains via `.contextMenu`).
- Uses the existing `.interactiveRow(cornerRadius:)` button style for consistent hover bg.

This replaces the bespoke rows in `HomeView.sectionListRow` and `LikedMusicView.songRow`
so hover-play parity lands everywhere from one component.

### A — Home list restructure

#### 3. `QuickPicksCarousel`

- Chunks the section's songs into **columns of 4** `MusicListRow`s.
- Lays columns out in a horizontal `ScrollView(.horizontal)` / `LazyHStack`, each column a
  fixed-width `VStack` of up to 4 compact rows.
- `.scrollClipDisabled()` to match existing carousels; column width tuned to density.
- Used in **both** display modes (strictly better than the current grid-card treatment of
  Quick Picks).

#### 4. Section rendering switch in `HomeView`

Replace the `displayMode`-only branch with a layout-aware switch:

- **list mode:** `.quickPicks` → `QuickPicksCarousel`; `.cardShelf` → existing horizontal
  card carousel; `.songList` → vertical `LazyVStack` of `MusicListRow`.
- **grid mode:** `.quickPicks` → `QuickPicksCarousel`; everything else unchanged (existing
  card carousels).

Net effect: list mode stops cramming shelves into columns; recommendations surface as
distinct shelves with vertical breathing room.

### D — Home polish

#### 5. Section header + shelf affordances

- Consistent header typography/weight and spacing across all sections.
- Optional **"See all ›"** trailing affordance when a section has a navigable detail
  destination (only shown when such a destination exists; no dead chevrons).
- Carousel scroll-edge clipping/insets tuned so shelves align with the 24px content gutter.

Keep within the existing visual system (Liquid Glass / `.glassEffect()` where relevant);
no new color or type scales.

### B + C — Liked Songs search + sort

#### 6. `LikedMusicView` + `LikedMusicViewModel`

- Add a **search field** and a **sort menu** to the header
  (Recently added / Title / Artist / Duration).
- ViewModel gains `searchQuery`, `sortOrder`, and a derived `displaySongs` computed from
  `songs` (filter by query over title/artist, then sort).
- **Auto-load-all on search** (maintainer-approved): when `searchQuery` becomes non-empty,
  kick off loading all remaining pages (`loadMore()` in a loop until `!hasMore`), guarded
  so it runs once per active search; show a subtle progress indicator while loading so
  results are complete, not just the loaded window. When the query clears, normal
  pagination resumes.
- Rows switch to `MusicListRow` (hover-play + parity). Existing divider styling preserved.

## Data flow

API → `HomeViewModel.sections` → `displaySections` (Quick Picks pinned) → `HomeView`
classifies each via `SectionLayout` → renders carousel / card shelf / vertical list.
Liked: API (paginated) → `LikedMusicViewModel.songs` → `displaySongs` (filter+sort, with
auto-load-all when searching) → `LikedMusicView` rows.

## Error / edge handling

- Empty sections: keep existing `ContentUnavailableView` paths.
- Quick Picks with < 4 songs: carousel renders a single short column (no padding rows).
- Liked search with no matches: show a lightweight "No matching songs" state within the
  list region; play-all header reflects the filtered set or is disabled.
- Auto-load-all on a very large library: incremental, cancellable when the query clears;
  never blocks the main actor (uses existing async `loadMore`).
- Density (`compact`) respected by `MusicListRow` and the carousel column sizing.

## Testing

- **Unit (Swift Testing):**
  - `SectionLayout` classification: quick-picks title, card-shelf (album/playlist/artist
    items), song-list (song items) → expected cases, including mixed-item tie-breaks.
  - Liked `displaySongs`: filter matches title/artist case-insensitively; each sort order
    produces expected ordering; empty query returns source order.
- **Manual QA (serial, per AGENTS.md):** Home in list vs grid mode (Quick Picks carousel,
  shelves, vertical song lists); hover-play on Home list rows and Liked rows; Liked search
  (auto-load-all completeness) + each sort; compact vs regular density.
- `swift build`, `swiftlint --strict`, `swiftformat .`, `swift test --skip KasetUITests`.

## Build sequence

1. `SectionLayout` classification + unit tests.
2. `MusicListRow` (B) — extract/replace bespoke Home + Liked rows; hover-play.
3. `QuickPicksCarousel` + Home rendering switch (A).
4. Liked search/sort + auto-load-all (C) + unit tests.
5. Header/shelf polish (D).
6. Full QA pass; update `docs/progress.md` and `docs/user-stories.csv`.

## Open questions

None outstanding. Layout approach (section-type-aware) and Liked search behavior
(auto-load-all) confirmed with maintainer.
