# Boombox — Audit Findings (P2 → P4 RESOLVED)

All findings below were confirmed by adversarial verification and **fixed** in P4 (each batch built + linted + unit-tested green; integrated branch passes **926 unit tests**, 0 failures; UI tests run in CI). 1 of 36 original findings (F006) was refuted and dropped.

**Status: ✅ 35/35 fixed** — high 1, medium 13, low 21.

| Batch | Commit | Findings |
|---|---|---|
| `fix/playback` | `defcec4` | F001, F002, F003, F004, F005 |
| `fix/ui` | `7848ab7` | F017, F018, F019, F020, F021, F022, F024, F025, F026 |
| `fix/systems` | `e0b6ccb` | F027, F028, F029, F030, F031, F032, F033, F034, F035, F036 |
| `fix/data` | `eb12d83` | F007, F008, F009, F010, F011, F012, F013, F014, F015, F016, F023 |


## HIGH severity

### F028 · ✅ Chinese/Bengali/Hindi romanizers index a Swift String with UTF-16 tokenizer offsets → wrong output and out-of-bounds crash
- **File:** `Sources/Kaset/Services/Lyrics/Romanization/Romanizers/ChineseRomanizer.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** GAP-06
- **Problem:** CFStringTokenizer reports token ranges (CFRange.location/length) in UTF-16 code units. ChineseRomanizer, BengaliRomanizer and HindiRomanizer feed those UTF-16 offsets into `text.index(text.startIndex, offsetBy: tokenRange.location)` / `offs
- **Fix applied:** In each of ChineseRomanizer.swift, BengaliRomanizer.swift, and HindiRomanizer.swift, mirror the Thai/Japanese implementation. Add `let nsText = text as NSString` right after the `let cfText = text as CFString` line (around line 6), then replace the three-line else-branch body (lines 34-36) with: `le


## MEDIUM severity

### F001 · ✅ Shuffle Next can replay the current track and never reach some songs (random index includes current index)
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Fixed in** `fix/playback` (`defcec4`)
- **Affected stories:** PLAY-02, PLAY-03, PLAY-07
- **Problem:** In next() the shuffle branch picks `let randomIndex = Int.random(in: 0 ..< self.queue.count)` with no exclusion of the current index and no memory of already-played tracks. The chosen index can equal currentIndex, so pressing Next (button o
- **Fix applied:** In the shuffle branch at PlayerService.swift:593, exclude the current index when the queue has more than one song. Minimal change:  ```swift if self.shuffleEnabled {     let randomIndex: Int     if self.queue.count > 1 {         let r = Int.random(in: 0 ..< self.queue.count - 1)         randomIndex 

### F005 · ✅ WebView content-process crash recovery leaves PlayerService state stale and double-navigates
- **File:** `Sources/Kaset/Views/SingletonPlayerWebView.swift` · **Fixed in** `fix/playback` (`defcec4`)
- **Affected stories:** WEB-17
- **Problem:** webViewWebContentProcessDidTerminate calls `webView.reload()` and then, 1s later, resets currentVideoId=nil and calls loadVideo(videoId:) — two separate navigations that race. It never updates PlayerService.state, so the UI keeps showing `.
- **Fix applied:** In webViewWebContentProcessDidTerminate (SingletonPlayerWebView.swift:366), (1) immediately reflect the interruption in user-visible state by setting the player to a loading/error state on the main actor, e.g. `Task { @MainActor in SingletonPlayerWebView.shared.coordinator?.playerService.state = .lo

### F007 · ✅ Single shared continuation tokens for playlist / liked songs / filtered search cause cross-context pagination contamination
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-15, API-11
- **Problem:** YTMusicClient stores pagination state in single instance vars (`playlistContinuationToken` line 730, `likedSongsContinuationToken` line 659, `searchContinuationToken` line 374) shared across ALL playlists/searches. `getPlaylistContinuation(
- **Fix applied:** Scope the playlist continuation token per request instead of in shared client state. Minimal change: change getPlaylistContinuation() to accept the caller-held token: `func getPlaylistContinuation(token: String) async throws -> PlaylistContinuationResponse?` and stop reading/writing self.playlistCon

### F009 · ✅ Favorites decode is all-or-nothing — one incompatible/corrupt entry wipes ALL favorites on disk
- **File:** `Sources/Kaset/Services/FavoritesManager.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** LIB-28
- **Problem:** FavoritesManager.load() decodes the whole file as `[FavoriteItem].self` (line 70). FavoriteItem.ItemType wraps full Song/Album/Playlist/Artist/PodcastShow Codable structs, all with non-optional `let` fields and no CodingKeys/default-toleran
- **Fix applied:** In load(), decode tolerantly instead of all-or-nothing so a single bad element cannot destroy the collection. Concretely, decode an array of element decoders and try? each: replace line 70-75 with something like `let containers = try JSONDecoder().decode([FailableDecodable<FavoriteItem>].self, from:

### F017 · ✅ Search filter chips vanish when a filtered search returns zero results, trapping the user on the empty filter
- **File:** `Sources/Kaset/Views/SearchView.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** SRCH-09
- **Problem:** The filter chip row is only rendered when `!self.viewModel.results.isEmpty` (searchBar, line 83). When the user picks a filter (e.g. Podcasts / Community playlists) whose query returns no results, `SearchViewModel.performSearch` assigns an 
- **Fix applied:** In SearchView.swift:83, replace the condition `if !self.viewModel.results.isEmpty` with a gate that reflects whether a search has been performed/displayed, so chips persist on zero-result filters. Cleanest option using existing state: `if self.viewModel.loadingState == .loaded || self.viewModel.load

### F020 · ✅ Switching sidebar tabs destroys each tab's NavigationStack, losing the user's drill-down position
- **File:** `Sources/Kaset/Views/MainWindow.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** NAV-01, API-25, NAV-11
- **Problem:** `viewForNavigationItem` selects the active tab with a `switch` inside a `Group` (MainWindow.swift:471-493). Because each case is a distinct view type, changing `navigationSelection` tears down the previous tab's view and builds a fresh one.
- **Fix applied:** Persist each tab's navigation position across selection changes. Lowest-risk approach: in MainWindow, hold one `@State private var <tab>Path = NavigationPath()` per NavigationItem (or a `[NavigationItem: NavigationPath]` dictionary) and pass the relevant one down as a `@Binding` into each tab view, 

### F021 · ✅ PodcastShowView has no error state — a failed load shows a title with an empty episode list and no retry
- **File:** `Sources/Kaset/Views/PodcastDetailViews.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** DET-22
- **Problem:** `PodcastShowView.loadShow()` sets `loadingState = .error(...)` on failure (line 200-203), but the view body never inspects `.error`. The body unconditionally renders header + episodesList; episodesList only shows a spinner while `.loading` 
- **Fix applied:** Wrap the body content in a branch on loadingState. Minimal approach: in `var body`, before the ScrollView, add an `if case let .error(error) = self.loadingState { ... } else { <existing ScrollView> }`. The error branch should render `ErrorView(error: error) { self.loadingState = .idle; Task { await 

### F022 · ✅ "Add to Library" on a song force-plays that song, hijacking current playback
- **File:** `Sources/Kaset/Views/SharedViews/SongActionsHelper.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** XCUT-26
- **Problem:** `SongActionsHelper.addToLibrary(_ song:)` calls `playerService.play(song:)`, sleeps 100ms, then `toggleLibraryStatus()` because library toggling operates on the current track. This helper is wired to the 'Add to Library' context-menu item i
- **Fix applied:** Add a non-playing library-add path that uses the existing direct API. Change addToLibrary to accept the YTMusicClientProtocol client and, when the Song's feedbackTokens are absent, fetch them by videoId before adding: 1) if song.feedbackTokens?.add exists, call `try await client.editSongLibraryStatu

### F023 · ✅ Playlist pagination relies on a single shared continuation token on the client, corrupting page loads when two playlist/album detail views are on the stack
- **File:** `Sources/Kaset/ViewModels/PlaylistDetailViewModel.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** DET-16
- **Problem:** `PlaylistDetailViewModel.loadMore()` calls `client.getPlaylistContinuation()` which takes no playlist identifier (Protocols.swift:197) — the continuation cursor is stored on the shared YTMusicClient and is (re)set by the most recent `getPla
- **Fix applied:** Scope the continuation cursor per request instead of a single shared client field. Minimal approach: (1) Surface the continuation token in the response objects already returned — PlaylistTracksResponse/PlaylistDetail and PlaylistContinuationResponse already carry `continuationToken` (used at YTMusic

### F024 · ✅ Global PlayerBar key shortcuts (Space, ⌘←/→/↑/↓) can intercept text editing in the Search field
- **File:** `Sources/Kaset/Views/PlayerBar.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** QUE-01, PLAY-01
- **Problem:** PlayerBar installs hidden zero-opacity buttons bound to `.space` (play/pause), `⌘→`/`⌘←` (next/previous) and `⌘↑`/`⌘↓` (volume) with no focus guard (PlayerBar.swift:71-122). PlayerBar is injected via `.safeAreaInset(edge:.bottom)` on every 
- **Fix applied:** Gate the hidden shortcut buttons so they are inert while a text field is focused. Add an EnvironmentKey (e.g. isTextEntryFocused) that SearchView (and any other text-entry views) sets from its @FocusState, read it in PlayerBar (@Environment(\.isTextEntryFocused) private var isTextEntryFocused), and 

### F025 · ✅ Swipe-back scroll tracking may capture horizontal carousel scrolls inside pushed detail views
- **File:** `Sources/Kaset/Views/SharedViews/NavigationSwipeGestures.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** NAV-13
- **Problem:** `handleScrollWheel` promotes any predominantly-horizontal precise scroll whose phase is `.began` into `NSEvent.trackSwipeEvent` whenever there is somewhere to navigate (`canBack = !path.isEmpty`). Detail views pushed onto the stack (ArtistD
- **Fix applied:** Tighten the promotion heuristic in handleScrollWheel so carousel scrolls are not hijacked. Practical options grounded in the current code: (1) Require a stronger horizontal dominance ratio and minimum magnitude before tracking, e.g. abs(scrollingDeltaX) > 2.5 * abs(scrollingDeltaY) and abs(scrolling

### F029 · ✅ ar.lproj and tr.lproj are stale 2-key stubs duplicating Localizable.xcstrings; risk of shadowing the complete Arabic/Turkish translations
- **File:** `Sources/Kaset/Resources/ar.lproj/Localizable.strings` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** _(infra/doc)_
- **Problem:** Resources are declared with `.process("Resources")` (Package.swift:24) and contain both `Localizable.xcstrings` (full, correct ar/tr ≈263 keys) AND hand-committed per-language `*.lproj/Localizable.strings` exports. fr/ko/id .lproj have ~263
- **Fix applied:** Regenerate complete ar.lproj/Localizable.strings and tr.lproj/Localizable.strings from Localizable.xcstrings, matching the existing fr/ko/id .lproj exports (same "/* Generated from Localizable.xcstrings. */" header and ~263 keys each). Do NOT simply delete the two stub directories: because SwiftPM .

### F030 · ✅ GlobalHotkeyService never removes its installed Carbon event handler and has no deinit (handler leak + use-after-free risk)
- **File:** `Sources/Kaset/Services/GlobalHotkeyService.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** SET-07
- **Problem:** installEventHandlerIfNeeded() installs an application-level Carbon handler via InstallEventHandler with userInfo = Unmanaged.passUnretained(self). There is no RemoveEventHandler call anywhere (unregister() only removes the hot-key, not the 
- **Fix applied:** In unregister(), also tear down the installed handler so an instance never outlives its handler: after removing the hot-key, add `if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }`. RemoveEventHandler and UnregisterEventHotKey are plain C calls with no actor requireme


## LOW severity

### F002 · ✅ MenuBar queue list uses unstable `id: \.offset` identity (the repo's own documented anti-pattern)
- **File:** `Sources/Kaset/Views/MenuBarPlayerView.swift` · **Fixed in** `fix/playback` (`defcec4`)
- **Affected stories:** PLAY-17, SET-05, PLAY-18
- **Problem:** The menu-bar popover queue uses `ForEach(Array(self.playerService.queue.enumerated()), id: \.offset)`. docs/common-bug-patterns.md explicitly flags index/offset-based identity as BAD because it recreates identity on every change, causing wr
- **Fix applied:** In MenuBarPlayerView.swift:396 change `id: \.offset` to `id: \.element.videoId`, exactly matching QueueView.swift:107. One-line change, no other code depends on offset identity (the row still uses its own `index` for isCurrent and playFromQueue(at:)). Caveat consistent with QueueView: if the queue e

### F003 · ✅ Untracked reconciliation Tasks in WebQueueSync can double-act (advance + re-play) across consecutive STATE_UPDATEs, desyncing the queue
- **File:** `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift` · **Fixed in** `fix/playback` (`defcec4`)
- **Affected stories:** PLAY-23
- **Problem:** Several reconciliation handlers schedule fire-and-forget `Task { await self.next() }` / `Task { await self.play(song:...) }` WITHOUT first synchronously moving the queue pointer. Each STATE_UPDATE from the WebView is delivered as its own `T
- **Fix applied:** Introduce a single in-flight reconciliation guard on PlayerService (a `@MainActor var isReconcilingWebQueue = false`, or a monotonically increasing generation counter). Set it synchronously at the top of each branch that schedules a corrective `Task { next()/play() }` in handleNearEndTrackChangeIfNe

### F004 · ✅ Live observer updates overwrite a known duration with 0 during track transitions (inconsistent with the restore path)
- **File:** `Sources/Kaset/Services/Player/PlayerService+PlaybackRestoration.swift` · **Fixed in** `fix/playback` (`defcec4`)
- **Affected stories:** WEB-11
- **Problem:** applyObservedPlaybackState assigns `self.duration = duration` unconditionally. The observer script reports `duration: progressBar ? parseInt(aria-valuemax) : 0`, so whenever the `#progress-bar` element is briefly absent (track change / SPA 
- **Fix applied:** In applyObservedPlaybackState, mirror the restore path: replace `self.duration = duration` (line 118) with `if duration > 0 { self.duration = duration }`. This keeps the last known duration when the observer transiently reports 0. Leave progress alone (the live path intentionally tracks live progres

### F008 · ✅ Sign-out does not clear APICache/URLCache; cross-account stale data leak when account identity can't be resolved
- **File:** `Sources/Kaset/Services/Auth/AuthService.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** AUTH-09
- **Problem:** AuthService.signOut() (line 105) clears WebKit cookies via `webKitManager.clearAllData()` but never clears APICache or URLCache. The only place per-account caches are invalidated is the View layer: MainWindow.swift:187-192 `onChange(of: acc
- **Fix applied:** Make cache invalidation part of the auth lifecycle rather than relying solely on the View observer. In AuthService.signOut() add, before/after clearAllData: `await MainActor.run { APICache.shared.invalidateAll(); URLCache.shared.removeAllCachedResponses() }` (APICache.invalidateAll is at APICache.sw

### F010 · ✅ Cancelled requests are treated as retryable and mis-surfaced as network errors
- **File:** `Sources/Kaset/Utilities/RetryPolicy.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-06
- **Problem:** RetryPolicy.execute only short-circuits errors that are YTMusicError with isRetryable==false (line 28). When a Swift-concurrency Task is cancelled, URLSession.data(for:) throws URLError(.cancelled), which performRequest wraps as `YTMusicErr
- **Fix applied:** In RetryPolicy.execute, immediately rethrow cancellation before the isRetryable check. Add at the top of the catch block (RetryPolicy.swift, after line 25): `if error is CancellationError { throw error }` and treat wrapped URLError.cancelled as cancellation: `if let ytError = error as? YTMusicError,

### F011 · ✅ Rating actions are not serialized per song; overlapping like/unlike can leave server state inconsistent with UI
- **File:** `Sources/Kaset/Services/SongLikeStatusManager.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** LIB-29
- **Problem:** SongLikeStatusManager.rate() (line 165) performs an optimistic synchronous cache update then awaits `client.rateSong` with no per-song task tracking or cancellation of a prior in-flight rate. Rapid like→unlike on the same song fires two ind
- **Fix applied:** Add per-videoId in-flight Task tracking inside SongLikeStatusManager (the @MainActor serialization point), keyed by resolved (accountID, videoId). At the top of rate(), before the optimistic update, look up any existing in-flight Task for that key and `await`/cancel it (cancel previous, then start n

### F012 · ✅ ParsingHelpers.extractArtists lacks the non-artist filtering used elsewhere; stray subtitle tokens become fake artists
- **File:** `Sources/Kaset/Services/API/Parsers/ParsingHelpers.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-26
- **Problem:** extractArtists(from:) (subtitle-runs based, line 119) only skips the separators ' • ', ' & ', ', ' and then generates a stable hash ID for any remaining text run that has no navigationEndpoint. Unlike extractArtistsFromFlexColumns (line 416
- **Fix applied:** In extractArtists (ParsingHelpers.swift:125-139), extend the run filter to mirror the flex-column path. Change the guard at line 126-127 to also reject content-type keywords and non-artist metadata before the navigationEndpoint branch, e.g.: `if let text = run["text"] as? String, text != " • ", text

### F013 · ✅ History continuation pages are cached for 5 minutes despite history being intentionally uncached
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-10
- **Problem:** getHistory() deliberately passes ttl:nil so the first history page is never cached (line 218-219, comment 'No cache — history changes with every song played'). But getHistoryContinuation() → fetchContinuation(type:.history) → requestContinu
- **Fix applied:** Thread a per-type TTL through fetchContinuation. Add a ttl parameter to fetchContinuation (defaulting to APICache.TTL.home to preserve current behavior for home/explore/etc.) and pass it to requestContinuation(token, ttl:). Then in getHistoryContinuation() (line 224) call fetchContinuation(type:.his

### F014 · ✅ Queue-endpoint track parsing keeps only the first artist and uses empty-string artist IDs
- **File:** `Sources/Kaset/Services/API/Parsers/PlaylistParser.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-15
- **Problem:** parseQueueItem (line 1329) reads only `shortBylineText.runs.first` for the artist name (line 1342) and `Artist(id: artistId ?? "", ...)` (line 1356). This path backs getPlaylistAllTracks (YTMusicClient.swift:774), used for radio/RDCLAK play
- **Fix applied:** Replace the single-run artist extraction in parseQueueItem with a multi-run parse. Add a helper that iterates `artistRuns`, skipping separator runs (text "•", "&", ",", or whitespace-only), and for each name run pairs it with the browseId from that run's navigationEndpoint.browseEndpoint.browseId wh

### F015 · ✅ Podcast shows are silently dropped from combined ('All') search results
- **File:** `Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** SRCH-16, SRCH-10
- **Problem:** The combined search path parse() → parseSearchSections → parseSearchResultItem → createItemFromBrowseEndpoint (line 260) handles album (MPRE/OLAK), artist (UC/MPLAUC), and playlist (VL/PL) browse IDs but has NO branch for podcast shows (MPS
- **Fix applied:** In createItemFromBrowseEndpoint (Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift, before the final `return nil` at line 296), add a podcast branch mirroring parsePodcastShowFromSearchResult: `if pageType == "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE" || browseId.hasPrefix("MPSPP") { ret

### F016 · ✅ InnerTube API key is cached permanently with no invalidation on auth/API failure
- **File:** `Sources/Kaset/Services/API/YTMusicAPIKeyProvider.swift` · **Fixed in** `fix/data` (`eb12d83`)
- **Affected stories:** API-02
- **Problem:** Once fetched, the bootstrap INNERTUBE_API_KEY is stored in `cachedAPIKey` (line 48) and returned for the rest of the process lifetime (line 30-32) with no expiry or invalidation hook. If YouTube rotates the key or the cached key becomes inv
- **Fix applied:** Add an invalidate() method to the YTMusicAPIKeyProviding protocol and YTMusicAPIKeyProvider that sets cachedAPIKey = nil (and clears any in-flight apiKeyTask). Then in YTMusicClient.performRequest, before re-throwing on the key-related failure paths, call self.apiKeyProvider.invalidate() so the next

### F018 · ✅ History list ForEach uses index-based identity (id: \.offset), the documented unstable-identity anti-pattern
- **File:** `Sources/Kaset/Views/HistoryView.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** LIB-21, LIB-22
- **Problem:** The per-section song list uses `ForEach(Array(songs.enumerated()), id: \.offset)` — exactly the index-identity anti-pattern called out in docs/common-bug-patterns.md ('ForEach with Unstable Identity'). History is refreshed on playback chang
- **Fix applied:** Replace the unstable offset identity with a stable composite key that tolerates duplicate videoIds within a section. Since Song.id equals videoId and a song may repeat in a day's history, use a videoId+index composite as the ForEach id: `ForEach(Array(songs.enumerated()), id: \.0) { ... }` is still 

### F019 · ✅ History page shows two Refresh buttons in the toolbar (MainWindow + HistoryView each add one)
- **File:** `Sources/Kaset/Views/HistoryView.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** LIB-20
- **Problem:** MainWindow's detail toolbar adds a global Refresh button for every refreshable page, and `currentPageSupportsRefresh` returns true for `.history` (MainWindow.swift:557-564, button at 287-297). HistoryView's own NavigationStack additionally 
- **Fix applied:** Pick one source of truth. Recommended (matches all other tabs): delete HistoryView's own ToolbarItem block (HistoryView.swift:41-54) so only MainWindow's shared button renders; the page's refresh still works via MainWindow.refreshCurrentPage -> historyViewModel.refresh (MainWindow.swift:594) and via

### F026 · ✅ NewReleasesView (and History container) lack accessibility identifiers used by UI tests
- **File:** `Sources/Kaset/Views/NewReleasesView.swift` · **Fixed in** `fix/ui` (`7848ab7`)
- **Affected stories:** EXPL-16, EXPL-08, EXPL-19
- **Problem:** Most tab roots set `.accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.<Tab>.container)` (Home, Explore, Library, Search, LikedMusic). NewReleasesView sets none and there is no `AccessibilityID.NewReleases` en
- **Fix applied:** In AccessibilityIdentifiers.swift add `enum NewReleases { static let container = "newReleasesView" }` and add `static let container = "historyView"` to the existing `enum History`. In NewReleasesView.swift, apply `.accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.NewR

### F027 · ✅ French (fr) and Indonesian (id) translations are entirely scrambled — every key maps to an unrelated value
- **File:** `Sources/Kaset/Resources/Localizable.xcstrings` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** _(infra/doc)_
- **Problem:** In Localizable.xcstrings the `fr` and `id` localizations are misaligned by an offset, so nearly every key is paired with the translation that belongs to a different key. ko/ar/tr are correct; only fr and id are corrupted. The committed `fr.
- **Fix applied:** This is a latent data-integrity/tooling hazard, not a runtime bug, so fix at low priority. Two options: (1) Repair the fr and id localizations inside Localizable.xcstrings so each key maps to its own translation (the correct values already exist in fr.lproj/id.lproj/Localizable.strings — re-import t

### F031 · ✅ ImageCache memory cache is keyed by URL only, ignoring targetSize → wrong-resolution image served
- **File:** `Sources/Kaset/Utilities/ImageCache.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** XCUT-08
- **Problem:** image(for:targetSize:) stores and looks up NSImages in memoryCache keyed solely by the URL (`memoryCache.object(forKey: url as NSURL)`), but the cached image is downsampled to whatever targetSize the FIRST requester asked for. A later reque
- **Fix applied:** Incorporate targetSize into the memory cache key at all three NSCache sites. Add a private helper: `private func memoryKey(for url: URL, targetSize: CGSize?) -> NSString { if let s = targetSize { return "\(url.absoluteString)#\(Int(s.width))x\(Int(s.height))" as NSString } else { return url.absolute

### F032 · ✅ Romanization (with per-line NLLanguageRecognizer) runs synchronously on the MainActor during lyric resolution
- **File:** `Sources/Kaset/Services/Lyrics/SyncedLyricsService.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** LYR-14, LYR-13
- **Problem:** When synced lyrics resolve, applyResolvedLyrics (MainActor) calls displayLyrics → RomanizationService.romanizeAll, which iterates every line and runs the romanizer synchronously on the main thread. For CJK detection, ScriptDetector.isJapane
- **Fix applied:** Offload romanizeAll off the MainActor in the two callers. The romanization work (ScriptDetector + romanizers + NLLanguageRecognizer + CFStringTokenizer) is all pure/value-based, so it can run nonisolated. Simplest minimal change: make ScriptDetector statics and the Romanizer statics nonisolated (the

### F033 · ✅ MenuBarController popover event/scroll monitors leak when the transient popover auto-closes
- **File:** `Sources/Kaset/Services/MenuBarController.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** PLAY-17, SET-05, NAV-23
- **Problem:** presentPopover() installs a global mouse-down monitor (eventMonitor) and a local scrollWheel monitor (scrollMonitor); both are removed only in dismissPopover(). The NSPopover uses .transient behavior and the controller does not adopt NSPopo
- **Fix applied:** Two complementary minimal options, grounded in the current code:  1) Idempotent guard (simplest, trivial): At the very top of presentPopover() (after the guard at lines 105-110, before creating the new NSPopover at line 119), remove any stale monitors so a second pair can never stack:    if let moni

### F034 · ✅ AccentBackground downloads album art directly (bypassing ImageCache) and re-extracts palette on every URL change with no caching
- **File:** `Sources/Kaset/Views/AccentBackground.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** XCUT-04
- **Problem:** loadPalette() fetches the image via URLSession.shared.data(from:) directly rather than ImageCache, so the same album art is downloaded a second time (once for display through ImageCache, once here). The extracted ColorPalette is not cached 
- **Fix applied:** In loadPalette(), replace the direct URLSession download with `ImageCache.shared.image(for: url)` (returns a cached NSImage from memory/disk, avoiding the second network round-trip) and call the existing NSImage overload `ColorExtractor.extractPalette(from: image)` (ColorExtractor.swift:36). Add a s

### F035 · ✅ In-app shortcut recorder lets users bind reserved macOS shortcuts (⌘Q/⌘W/⌘M/⌘,) with no warning
- **File:** `Sources/Kaset/Views/HotkeysSettingsView.swift` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** SET-09
- **Problem:** Per-action recorders use requireModifiers:false and KeyboardShortcutsManager.conflict(for:excluding:) only checks for collisions among ShortcutAction cases — never against standard system shortcuts. A user can record ⌘Q, ⌘W, ⌘M, ⌘H or ⌘, fo
- **Fix applied:** Add a reserved-shortcut set and surface a non-blocking warning (mirroring the existing conflict caption) rather than hard-refusing, so power users who explicitly want it are not blocked. In HotkeyShortcut.swift add a computed `isReservedSystemShortcut` that returns true for command-only combos match

### F036 · ✅ docs/keyboard-shortcuts.md omits the Toggle Sidebar (⌃⌘S) shortcut that exists in code
- **File:** `docs/keyboard-shortcuts.md` · **Fixed in** `fix/systems` (`e0b6ccb`)
- **Affected stories:** _(infra/doc)_
- **Problem:** ShortcutAction defines a `toggleSidebar` action (Window category) with default ⌃⌘S, but docs/keyboard-shortcuts.md documents only Playback and Navigation sections and never lists Toggle Sidebar / the Window category. AGENTS.md requires keep
- **Fix applied:** Append a Window section to docs/keyboard-shortcuts.md (after the Navigation table, around line 39):  ## Window  | Shortcut | Action         | | -------- | -------------- | | `⌃⌘S`    | Toggle Sidebar |  This matches ShortcutAction.swift:147-148 (kVK_ANSI_S + cmdKey|controlKey) and the Category.windo
