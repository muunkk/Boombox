# Boombox — Pass 2 Audit Findings (RESOLVED)

Second-pass deep audit on the post-pass-1 code. 54 findings from 8 lenses (concurrency, crash, error-state, ux/a11y, playback, data, memory, regression) -> **51 confirmed** after adversarial verification (3 refuted), **all fixed**. Integrated branch passes **981 unit tests** (0 failures, verified across 2 runs); CI runs UI tests.

**Status: ✅ 51/51 fixed** — high 3, medium 10, low 38. Fixes in commits 0cb06f1 (6 batches) + ed470ef (cross-batch completion).


## HIGH severity

### P2F017 · ✅ 59 user-facing strings are missing from the string catalog, so they never localize (English leaks into ar/fr/id/ko/tr)
- **File:** `Sources/Kaset/Resources/Localizable.xcstrings` · **Confidence:** high · **Risk:** low
- **Stories:** _(infra/cross-cutting)_
- **Problem:** A large set of user-facing strings used in newer Views are absent from Localizable.xcstrings (and therefore from the generated ar/tr/fr/id/ko .lproj files). SwiftUI Text("literal") and String(localized:) resolve through 
- **Fix:** Add the missing keys to Sources/Kaset/Resources/Localizable.xcstrings (en source units) and provide translations for ar/fr/id/ko/tr — either as new xcstrings localization units or by appending the keys to each Sources/Kaset/Resources/<local

### P2F032 · ✅ playWithMix overwrites rich first-song metadata with a "Loading..." stub and skips Kaset-initiated autoplay correction
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-21
- **Problem:** playWithMix sets `self.currentTrack = shuffledSongs[0]` (full title/artist/album/thumbnail) at line 78, then immediately calls `await self.play(videoId: shuffledSongs[0].videoId)` at line 81. `play(videoId:)` (PlayerServ
- **Fix:** In PlayerService+Queue.swift playWithMix, replace lines 78-81 (`self.currentTrack = shuffledSongs[0]` + `await self.play(videoId: shuffledSongs[0].videoId)`) with a single `await self.play(song: shuffledSongs[0])`. play(song:) assigns curre

### P2F041 · ✅ Artist duration-enrichment rebuilds ArtistDetail and drops all album-pagination fields, hiding "Show all albums"
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-16
- **Problem:** In getArtist(id:), when any of the artist's top songs lack a duration (the documented common case — see comment line 826 "Artist page top songs don't include duration"), the code fetches durations and rebuilds ArtistDeta
- **Fix:** In the ArtistDetail re-init at YTMusicClient.swift:848-862, add the three dropped fields, e.g. after songsParams: detail.songsParams add `hasMoreAlbums: detail.hasMoreAlbums, albumsBrowseId: detail.albumsBrowseId, albumsParams: detail.album


## MEDIUM severity

### P2F002 · ✅ WebQueueSync drift/repeat-one/safety-net handlers fire raw unstructured Task{} that bypass the isReconcilingWebQueue guard, allowing duplicate corrective play() calls
- **File:** `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift` · **Confidence:** medium · **Risk:** low
- **Stories:** PLAY-23
- **Problem:** Pass 1 added `scheduleWebQueueReconciliation` which sets `isReconcilingWebQueue = true` synchronously before scheduling advance/replay work, and `handleUnexpectedQueueDriftIfNeeded` checks that flag (line 314) to suppres
- **Fix:** Route the three genuinely-unguarded corrective re-plays through the existing reconciliation helper so the synchronous `isReconcilingWebQueue` flag suppresses a duplicate STATE_UPDATE, mirroring the Pass-1 fix for the scheduled paths. Replac

### P2F006 · ✅ Queue drag-reorder traps in Array.move when queue shrinks mid-drag (stale source / oversized destination index)
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-08
- **Problem:** reorderQueue(from:to:) calls newQueue.move(fromOffsets: source, toOffset: destination) with only two guards (source must not contain currentIndex; destination must not equal currentIndex). It never validates that source 
- **Fix:** Add a bounds guard at the top of reorderQueue(from:to:) in PlayerService+Queue.swift, before the existing currentIndex guards (or just before the move on line 288):  guard source.allSatisfy({ $0 >= 0 && $0 < self.queue.count }), destination

### P2F010 · ✅ ArtistDetailView 'Mix' button silently fails — playWithMix swallows all errors with only a log
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-06
- **Problem:** ArtistDetailView's 'Mix' button calls `playerService.playWithMix(playlistId:startVideoId:)`. In playWithMix, every failure path is silent: the `catch` only logs `logger.warning("Failed to fetch mix queue...")` (line 86),
- **Fix:** Make playWithMix report success/failure and have the caller surface it. Minimal approach: change the signature to `func playWithMix(...) async -> Bool` returning false on the no-client guard, empty-result guard, and catch (true on success a

### P2F019 · ✅ QueueTableCellView (AppKit side-panel queue rows) has zero accessibility — editable queue is invisible to VoiceOver, and 'Unknown Artist' is hardcoded English
- **File:** `Sources/Kaset/Views/QueueTableCellView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-04, QUE-24, QUE-13
- **Problem:** The side-panel/edit-mode queue is an NSTableView whose cells are custom NSViews (QueueTableCellView). The cell sets no NSAccessibility metadata at all: no setAccessibilityLabel, no setAccessibilityRole, no isAccessibilit
- **Fix:** Two minimal changes in QueueTableCellView.swift. (1) Line 172: replace the literal with localized: `self.artistLabel.stringValue = song.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : song.artistsDisplay`. (2) In configure(..

### P2F020 · ✅ QueueRowView is tap-to-play but exposes no button trait/label/action to VoiceOver
- **File:** `Sources/Kaset/Views/QueueView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-24, QUE-02, QUE-04
- **Problem:** Each queue row plays its song via a bare `.onTapGesture` on an HStack with no accessibility treatment — no .accessibilityElement(children: .combine), no .accessibilityAddTraits(.isButton), no .accessibilityAction. SwiftU
- **Fix:** Add accessibility to the HStack in QueueRowView.body (after line 181, alongside the existing modifiers), but use .contain rather than .combine so the inner Go-to-Album / Go-to-Artist Buttons remain reachable. Concretely, after .onHover add:

### P2F033 · ✅ play(videoId:) never resets per-track like/library/feedback-token state, leaking the previous track's status onto the new track
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-10
- **Problem:** play(videoId:) builds a fresh currentTrack but never calls resetTrackStatus() and never seeds like-status/feedbackTokens from any source. Therefore currentTrackLikeStatus, currentTrackInLibrary, and currentTrackFeedbackT
- **Fix:** In play(videoId:) (PlayerService.swift), immediately before assigning the minimal currentTrack at line 399, add: self.resetTrackStatus(); then optionally seed like status from cache: if let cached = SongLikeStatusManager.shared.status(for: 

### P2F034 · ✅ Shuffle + single-song queue with repeat off loops the same track forever at natural track end
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-02, PLAY-08
- **Problem:** canAdvanceNativeQueueAfterTrackEnd (PlayerService+WebQueueSync.swift:36-42) returns true whenever shuffleEnabled is true, regardless of repeat mode or queue size. On natural track end, handleTrackEnded (line 454) sees it
- **Fix:** In PlayerService+WebQueueSync.swift, change the shuffle term of canAdvanceNativeQueueAfterTrackEnd (line 37) from `self.shuffleEnabled` to `(self.shuffleEnabled && self.queue.count > 1)`. This makes a 1-song shuffle queue fall through to th

### P2F035 · ✅ Duplicate videoIds in a queue collide under ForEach(id: \.element.videoId) in both queue views
- **File:** `Sources/Kaset/Views/QueueView.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** QUE-06
- **Problem:** QueueView (line 107) and MenuBarPlayerView (MenuBarPlayerView.swift:396) both render the queue with `ForEach(Array(self.playerService.queue.enumerated()), id: \.element.videoId)`. The queue is built from arbitrary playli
- **Fix:** Give each queue entry a stable per-insertion identity since neither videoId nor Song.id is unique within a queue. Cleanest: wrap queue entries in a lightweight struct `struct QueueEntry: Identifiable { let id = UUID(); var song: Song }` sto

### P2F043 · ✅ Filtered-search continuation only parses the legacy nextContinuationData format, ignoring the 2025 continuationItemRenderer format
- **File:** `Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SRCH-16
- **Problem:** parseContinuation (line 542) only reads continuationContents.musicShelfContinuation and extracts the next token via continuations[].nextContinuationData.continuation. It has no branch for the modern onResponseReceivedAct
- **Fix:** In SearchResponseParser.swift add 2025-format fallbacks mirroring PlaylistParser. (1) Add a private helper extractTokenFromContents(_ contents: [[String: Any]]) -> String? that reads contents.last["continuationItemRenderer"]["continuationEn

### P2F044 · ✅ Home/Explore/Charts/NewReleases/Moods/History continuation extraction is legacy-only (no 2025 continuationItemRenderer support)
- **File:** `Sources/Kaset/Services/API/Parsers/HomeResponseParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** HOME-22
- **Problem:** HomeResponseParser.extractContinuationToken (line 67) and extractContinuationTokenFromContinuation (line 86) require sectionListRenderer.continuations[].nextContinuationData.continuation, and parseContinuation (line 39) 
- **Fix:** In HomeResponseParser.swift add 2025-format fallbacks mirroring PlaylistParser. (1) extractContinuationToken: after the legacy guard fails, also try onResponseReceivedActions/appendContinuationItemsAction continuation token, plus the contin


## LOW severity

### P2F001 · ✅ MenuBarController scroll-to-volume has a lost-update race: rapid scroll events read stale volume before prior setVolume completes
- **File:** `Sources/Kaset/Services/MenuBarController.swift` · **Confidence:** high · **Risk:** low
- **Stories:** P2NEW-09, PLAY-17, SET-06
- **Problem:** handleVolumeScroll() synchronously reads the current volume (`player.volume`), computes the new slider value from it, then dispatches the write into an unstructured `Task { await player.setVolume(...) }`. Because the rea
- **Fix:** Maintain a synchronously-updated running target on MenuBarController so each event accumulates off the in-progress value rather than the async-lagged player.volume. Add a stored property `private var pendingSliderTarget: Double?`. In handle

### P2F003 · ✅ play(videoId:) omits isKasetInitiatedPlayback flag, so mix/restore playback bypasses the Kaset-initiated queue-enforcement reconciliation
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-10
- **Problem:** play(song:) sets `self.isKasetInitiatedPlayback = true` (line 444) so updateTrackMetadata can run handleKasetInitiatedPlaybackMetadata and re-assert the intended track when YouTube's autoplay loads something else. The pa
- **Fix:** Add `self.isKasetInitiatedPlayback = true` in play(videoId:) right after setting state/currentTrack (e.g. just before `self.pendingPlayVideoId = videoId` at PlayerService.swift:409), mirroring play(song:) line 444. This closes the narrow in

### P2F004 · ✅ NotificationService.requestAuthorization() spawns an untracked fire-and-forget Task capturing self with no cancellation
- **File:** `Sources/Kaset/Services/Notification/NotificationService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SET-03, SET-02
- **Problem:** requestAuthorization() launches `Task { ... self.logger... }` that is not stored, not cancellable, and outlives nothing in particular — it captures `self` strongly (the closure is implicitly @MainActor and references sel
- **Fix:** Make the authorization Task tracked and weakly-capturing, consistent with observationTask. Add a stored handle and use [weak self]:  ```swift // add alongside observationTask nonisolated(unsafe) private var authorizationTask: Task<Void, Nev

### P2F005 · ✅ NotificationService runs a permanent 500ms MainActor polling loop instead of observation, busy-waking the main actor for the app lifetime
- **File:** `Sources/Kaset/Services/Notification/NotificationService.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** SET-02, SET-03
- **Problem:** startObserving() launches a @MainActor Task that loops forever, reading playerService.currentTrack/isPlaying and sleeping 500ms each iteration. This polls @Observable PlayerService state on a fixed timer on the main acto
- **Fix:** Replace the polling loop with a re-registering withObservationTracking observer mirroring NowPlayingManager.observeSettingsChanges. Move previousTrack/previousIsPlaying to instance state, and in startObserving() (NotificationService.swift:4

### P2F007 · ✅ ArtistDetailViewModel.subscriptionError is set on failure but never displayed — subscribe/unsubscribe failures are silent
- **File:** `Sources/Kaset/ViewModels/ArtistDetailViewModel.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-07
- **Problem:** ArtistDetailViewModel exposes `private(set) var subscriptionError: String?` (line 19) and sets it to a user-facing message when toggleSubscription() fails (line 133). However, ArtistDetailView never reads `viewModel.subs
- **Fix:** Mirror the PodcastShowView pattern by attaching an alert to the root view in ArtistDetailView.swift. Add after the existing `.refreshable { ... }` modifier (around line 49) on the `Group` in body:  .alert(     String(localized: "Subscriptio

### P2F008 · ✅ Home, Explore, and New Releases have no empty-state for a successful-but-empty load (blank screen, no message, no retry)
- **File:** `Sources/Kaset/Views/HomeView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** HOME-01
- **Problem:** On `.loaded`/`.loadingMore`, HomeView (line 28-29), ExploreView (ExploreView.swift:25-26), and NewReleasesView (NewReleasesView.swift:25-26) render their `contentView`, which is an unconditional `ScrollView { LazyVStack 
- **Fix:** Add an empty-state branch to each contentView, mirroring MoodCategoryDetailView.swift:46-53. For ExploreView and NewReleasesView wrap the existing ScrollView: `if self.viewModel.sections.isEmpty { ContentUnavailableView("Nothing here yet", 

### P2F009 · ✅ HistoryView has no empty-state — an empty history shows only a '0 songs listened today' header over a blank list
- **File:** `Sources/Kaset/Views/HistoryView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LIB-18
- **Problem:** HistoryView's `contentView` (line 105) always renders `headerView` followed by `ForEach(self.viewModel.sections)`. When `sections` is empty (history paused on the account, a fresh account, or history disabled), there is 
- **Fix:** In HistoryView.swift contentView, branch on self.viewModel.sections.isEmpty inside the LazyVStack after the headerView padding block: when empty, render a ContentUnavailableView (or a local emptyStateView matching LikedMusicView's pattern, 

### P2F012 · ✅ TopSongsViewModel swallows API errors into .loaded — inconsistent with AllAlbums; no error state ever shown
- **File:** `Sources/Kaset/ViewModels/TopSongsViewModel.swift` · **Confidence:** high · **Risk:** low
- **Stories:** EXPL-21
- **Problem:** TopSongsViewModel.load() catches every non-cancellation error and sets `loadingState = .loaded` (line 57-59), keeping only the seed songs and never entering `.error`. The screen therefore has NO error state at all: if th
- **Fix:** In TopSongsViewModel.swift, change the generic catch block (lines 54-59) to mirror AllAlbumsViewModel. Minimal version that preserves the soft-degrade when a seed exists but surfaces an error when there is nothing to show: replace `self.loa

### P2F013 · ✅ authExpired renders a non-retryable 'Authentication Required' ErrorView with no button; notAuthenticated path never triggers global re-login
- **File:** `Sources/Kaset/Models/YTMusicError.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-10
- **Problem:** When a screen's load() catches `YTMusicError.authExpired`, it stores `LoadingError(from:)` whose `isRetryable` is false (YTMusicError.isRetryable returns false for authExpired/notAuthenticated, lines 80-82). ErrorView on
- **Fix:** Make the early auth-failure throws route through the existing global recovery so the LoginSheet always appears. In YTMusicClient.buildAuthHeaders() (YTMusicClient.swift:1361-1364), before `throw YTMusicError.notAuthenticated`, call `self.au

### P2F014 · ✅ Library/like/queue/album content actions swallow all failures (log-only) — no toast on offline or API error
- **File:** `Sources/Kaset/Views/SharedViews/SongActionsHelper.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-08
- **Problem:** Most fire-and-forget actions in SongActionsHelper catch errors and only log via DiagnosticsLogger with no user feedback: addToLibrary (line 183), addPlaylistToLibrary (line 212), removePlaylistFromLibrary (line 241), pla
- **Fix:** Add a lightweight app-level error toast presenter and route the existing log-only catch blocks through it. Concretely: (1) Create a @MainActor @Observable ActionErrorPresenter with `var lastMessage: String?` and `var sequence: Int`, injecte

### P2F015 · ✅ PodcastShowView shows no 'no episodes' empty-state — a successful load with zero episodes renders a blank episode area
- **File:** `Sources/Kaset/Views/PodcastDetailViews.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-22
- **Problem:** PodcastShowView.episodesList renders a ProgressView while `.loading` and otherwise a `LazyVStack { ForEach(previewEpisodes) ... }` (lines 181-194). If loadShow() succeeds with `episodes == []` (a show with no published e
- **Fix:** In the loaded branch of episodesList (PodcastDetailViews.swift, the else block at lines 185-194), add an empty-state check before the LazyVStack: `} else if self.episodes.isEmpty { ContentUnavailableView("No Episodes", systemImage: "mic.sla

### P2F016 · ✅ Detail screens lack a proactive offline check — inconsistent with tab screens and no auto-recovery on reconnect
- **File:** `Sources/Kaset/Views/ArtistDetailView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-01, DET-02
- **Problem:** Top-level tab screens (Home, Explore, Library, LikedMusic, Search, History) begin their body with `if !networkMonitor.isConnected { ErrorView("No Connection"...) }`, giving an immediate clear offline state even before an
- **Fix:** For consistency, add the same proactive offline guard to detail views. In ArtistDetailView (and PlaylistDetailView, MoodCategoryDetailView, TopSongsView, AllAlbumsView, PodcastShowView): add `@State private var networkMonitor = NetworkMonit

### P2F018 · ✅ LoginSheet help text uses Text(String) with bare literals — can NEVER be localized even if added to the catalog
- **File:** `Sources/Kaset/Views/LoginSheet.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-20, AUTH-03
- **Problem:** loginHelpText is a computed property returning bare Swift String literals (not String(localized:)) and is rendered via Text(self.loginHelpText) at line 67. Text(String) is treated as verbatim (already-localized) content 
- **Fix:** Change `loginHelpText` to return a `LocalizedStringKey` so the Text call site auto-resolves it against the catalog. In Sources/Kaset/Views/LoginSheet.swift change line 74 to `private var loginHelpText: LocalizedStringKey {` (keep the same t

### P2F021 · ✅ Toolbar Display Mode / Density segmented pickers are icon-only with no per-segment accessibility label
- **File:** `Sources/Kaset/Views/MainWindow.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LIB-03
- **Problem:** Both segmented Pickers render their options as `Image(systemName: mode.systemImage).tag(mode)` only, discarding the localized displayName ('Grid'/'List', 'Default'/'Compact') that the enums already provide. A segmented c
- **Fix:** In MainWindow.swift, add a per-segment accessibility label, keeping the icon-only visual: line 318 -> `Image(systemName: mode.systemImage).tag(mode).accessibilityLabel(mode.displayName)`; line 330 -> `Image(systemName: density.systemImage).

### P2F022 · ✅ Hardcoded English accessibility labels in AccountRowView (VoiceOver-only strings never localize)
- **File:** `Sources/Kaset/Views/AccountRowView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-20
- **Problem:** AccountRowView builds VoiceOver strings from raw English literals with concatenation instead of String(localized:): the computed accessibilityLabel appends ', \(typeLabel) account' and ', currently selected' (lines 145, 
- **Fix:** Only the computed accessibilityLabel needs work (leave lines 53/68 as-is — they already localize). Build it from localized fragments. In AccountRowView.swift:138-152:    private var accessibilityLabel: String {       var label = self.accoun

### P2F023 · ✅ Hardcoded English accessibility label in SidebarProfileView.profileAccessibilityLabel
- **File:** `Sources/Kaset/Views/SidebarProfileView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-13, AUTH-20, AUTH-11
- **Problem:** profileAccessibilityLabel(for:) builds the VoiceOver label from raw English literals: `var label = "Profile: \(account.name)"`, then appends `". Multiple accounts available."`. Unlike the rest of this file (which correct
- **Fix:** Compose the label from localized fragments. Replace lines 200 and 205 with: line 200 -> var label = String(localized: "Profile: \(account.name)") and line 205 -> label += " " + String(localized: "Multiple accounts available.") (the leading 

### P2F024 · ✅ Hardcoded English accessibility label format in FavoriteItemCard
- **File:** `Sources/Kaset/Views/SharedViews/FavoritesSection.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LIB-24, HOME-16
- **Problem:** FavoriteItemCard composes its VoiceOver label via raw string interpolation `.accessibilityLabel("\(self.item.title), \(self.item.typeLabel), \(self.item.subtitle ?? "")")` with no String(localized:). The neighboring hint
- **Fix:** Localize typeLabel in Sources/Kaset/Models/FavoriteItem.swift:130-143 by wrapping each case in String(localized:), e.g. `case .song: String(localized: "Song")`, etc. This fixes the actual unlocalized token in the accessibility label and ben

### P2F025 · ✅ SafariSignInFallbackView import-status message is hardcoded English with interpolation
- **File:** `Sources/Kaset/Views/SafariSignInFallbackView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-20, AUTH-07
- **Problem:** On successful cookie import the visible status message is assigned a raw English string: `self.statusMessage = "Imported \(result.importedCount) auth cookies locally. Checking login..."`. This is shown via a green Label 
- **Fix:** At line 119 replace the raw assignment with a localized string: `self.statusMessage = String(localized: "Imported \(result.importedCount) auth cookies locally. Checking login…")` and add the corresponding key to Sources/Kaset/Resources/Loca

### P2F026 · ✅ Keyboard-selected suggestion rows use color-only highlight with no .isSelected accessibility trait (SearchView & CommandBarView)
- **File:** `Sources/Kaset/Views/SearchView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SRCH-07
- **Problem:** Arrow-key navigation moves selectedSuggestionIndex, and the highlighted row is indicated solely by a background fill (Color.accentColor.opacity(0.15)). The row Button gets no .accessibilityAddTraits(.isSelected) and ther
- **Fix:** In both suggestionRow builders, add the selection trait to the Button. In SearchView.swift after line 207 (`.buttonStyle(.plain)`) add: `.accessibilityAddTraits(index == self.selectedSuggestionIndex ? .isSelected : [])`. Apply the identical

### P2F027 · ✅ SyncedLineView lyric lines are tappable (seek) but have no accessibility traits/label/hint
- **File:** `Sources/Kaset/Views/SyncedLyricsDisplayView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-07
- **Problem:** Each synced lyric line uses `.contentShape(Rectangle()).onTapGesture { self.onTap() }` to seek to that line's timestamp, but the view exposes no accessibility button trait, no hint that tapping seeks, and the current-lin
- **Fix:** In SyncedLineView.body, replace the trailing modifier chain at lines 88-92 with an accessible button. Drop the separate onTapGesture in favor of grouping the element and adding traits/label/hint, e.g. after .lineLimit(nil): add .contentShap

### P2F028 · ✅ Error/info Toast is not announced to VoiceOver
- **File:** `Sources/Kaset/Views/ToastView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-16, NAV-18
- **Problem:** ToastView (and AccountErrorToast) appears transiently and auto-dismisses after ~4s, but it is not posted as a VoiceOver announcement (no AccessibilityNotification.Announcement / .accessibilityAddTraits) and carries no ro
- **Fix:** In AccountErrorToast.show() (ToastView.swift), after setting self.isVisible = true, post a VoiceOver announcement so it is read regardless of focus. Compute the message once and reuse it:  private func show() {     self.dismissTask?.cancel(

### P2F029 · ✅ Now-Playing panel chevron direction does not flip for RTL layouts
- **File:** `Sources/Kaset/Views/PlayerBar.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-14
- **Problem:** nowPlayingPanelChevronIcon hardcodes 'chevron.right'/'chevron.left' to indicate docking the now-playing panel toward the sidebar (which lives on the leading edge). In an RTL locale (ar) the NavigationSplitView sidebar mo
- **Fix:** In Sources/Kaset/Views/PlayerBar.swift:550, replace the fixed-direction glyphs with auto-mirroring ones: change `self.settings.showSidebarNowPlayingPanel ? "chevron.right" : "chevron.left"` to `self.settings.showSidebarNowPlayingPanel ? "ch

### P2F031 · ✅ HotkeyRecorderField recorder button lacks accessibility label/hint/value
- **File:** `Sources/Kaset/Views/HotkeyRecorderField.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SET-08
- **Problem:** The shortcut recorder is a Button whose only accessible content is its dynamic displayText (e.g. '⌘K', 'Set Shortcut', or 'Press shortcut…'). It has no .accessibilityLabel describing it as a shortcut recorder and no .acc
- **Fix:** Add three accessibility modifiers to the recorder Button at lines 23-28, after its closing brace: .accessibilityLabel(Text("Keyboard shortcut")), .accessibilityValue(Text(self.displayText)), and .accessibilityHint(Text("Activate to record a

### P2F036 · ✅ Unexpected-autoplay suppression fires a fire-and-forget Task { pause() } not protected by the reconciliation guard, allowing state thrash with incoming STATE_UPDATEs
- **File:** `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift` · **Confidence:** medium · **Risk:** medium
- **Stories:** PLAY-23
- **Problem:** suppressUnexpectedAutoplayAfterQueueEndIfNeeded (line 114-119) and the terminal branch of handleNearEndTrackChangeIfNeeded (line 242-246) call markPlaybackEnded() synchronously and then spawn a bare, untracked `Task { aw
- **Fix:** Do not rely solely on isReconcilingWebQueue around the pause Task, since applyObservedPlaybackState never reads it. The minimal robust fix is to make applyObservedPlaybackState (PlayerService+PlaybackRestoration.swift:125-129) not resurrect

### P2F037 · ✅ previous() no-local-queue fallback has dead duplicated branches (both call seek(to: 0))
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-03
- **Problem:** In the no-local-queue branch of previous(), `if self.progress > 3 { if self.pendingPlayVideoId != nil { await self.seek(to: 0) } else { await self.seek(to: 0) } }` — both arms of the inner if/else are byte-identical, so 
- **Fix:** Collapse the meaningless inner if/else at PlayerService.swift:699-707 to a single statement, since seek(to:) already handles the pendingPlayVideoId distinction internally:  if self.progress > 3 {     await self.seek(to: 0) } else {     Sing

### P2F038 · ✅ stop() leaves pendingPlayVideoId set, so MenuBar transport stays enabled and play/pause drives a cleared player
- **File:** `Sources/Kaset/Services/Player/PlayerService.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** WEB-02
- **Problem:** stop() clears currentTrack, progress, duration and sets state .idle but does NOT clear pendingPlayVideoId. Consequences: (1) MainWindow keeps rendering PersistentPlayerView because `pendingPlayVideoId != nil` (MainWindow
- **Fix:** In PlayerService.stop() (PlayerService.swift:800-811) add `self.pendingPlayVideoId = nil` after clearing currentTrack. This disables canControlPlayback, hides the PersistentPlayerView, and makes a subsequent playPause() fall through to the 

### P2F039 · ✅ Observer reports duration/progress as integer seconds, so the seek bar and remaining-time are quantized and a sub-second final track can never trigger near-end detection
- **File:** `Sources/Kaset/Views/SingletonPlayerWebView+ObserverScript.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-11, LYR-20
- **Problem:** sendUpdate() emits progress and duration via parseInt of the progress-bar value/aria-valuemax, i.e. whole seconds, and updatePlaybackState consumes them as Double seconds. The seek slider position (PlayerBar seekValue = 
- **Fix:** In SingletonPlayerWebView+ObserverScript.swift sendUpdate() (which already holds `const video = document.querySelector('video')` at line 262), emit the real media clock as floats and fall back to the progress-bar attributes only when the vi

### P2F040 · ✅ Freshly loaded paused track can get stuck in .loading because applyObservedPlaybackState only transitions out of .playing
- **File:** `Sources/Kaset/Services/Player/PlayerService+PlaybackRestoration.swift` · **Confidence:** medium · **Risk:** low
- **Stories:** PLAY-23, WEB-18
- **Problem:** applyObservedPlaybackState sets `.playing` when isPlaying is true, and `.paused` only when the prior state was already `.playing`. If a load completes but the video does not autoplay (autoplay blocked, a paused page, or 
- **Fix:** In applyObservedPlaybackState (PlayerService+PlaybackRestoration.swift:125-129), broaden the non-playing branch to also resolve .loading (and .buffering) once a non-playing observation arrives: change `else if self.state == .playing { self.

### P2F042 · ✅ Liked-songs pagination still uses a single shared continuation token on the client (inconsistent with Pass-1 per-request fix)
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-14
- **Problem:** Pass 1 moved playlist pagination to a caller-held per-request token (getPlaylistContinuation(token:)) precisely to avoid shared mutable continuation state on the @MainActor client (common-bug-patterns.md "Shared Continua
- **Fix:** Mirror the playlist fix. LikedSongsResponse already carries continuationToken, so make the cursor caller-owned: (1) Add `func getLikedSongsContinuation(token: String) async throws -> LikedSongsResponse?` on YTMusicClient that calls requestC

### P2F046 · ✅ Search section identity uses raw shelf title, colliding when YouTube returns two shelves with the same title
- **File:** `Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift` · **Confidence:** medium · **Risk:** low
- **Stories:** SRCH-10
- **Problem:** In parse(_:), SearchSection ids are stamped as the shelf title verbatim ("top" for the card, else draft.title, else shelf-<index>). YouTube "All" responses can surface two shelves with identical titles (e.g. duplicate "S
- **Fix:** Guarantee unique ids while preserving the stability goal of not perturbing ids when no collision exists. Track seen titles and only suffix true duplicates, keeping the first occurrence's id stable: in parse(...), before the map, use a count

### P2F047 · ✅ Continuation pagination stops early when a page contains only already-seen videoIds (legitimate intra-playlist duplicates)
- **File:** `Sources/Kaset/ViewModels/PlaylistDetailViewModel.swift` · **Confidence:** medium · **Risk:** medium
- **Stories:** DET-16
- **Problem:** loadMore() dedups continuation tracks by videoId against all previously-loaded tracks; if newTracks.isEmpty it sets continuationToken=nil and hasMore=false and returns, even when the server still returned a continuation 
- **Fix:** Decouple "page had no new unique tracks" from "stop paginating". In PlaylistDetailViewModel.loadMore (lines 177-183), when newTracks.isEmpty but response.continuationToken != nil and response.hasMore, do not append but advance the token and

### P2F048 · ✅ ImageCache in-flight de-duplication ignores targetSize, serving wrong-resolution images
- **File:** `Sources/Kaset/Utilities/ImageCache.swift` · **Confidence:** high · **Risk:** low
- **Stories:** XCUT-09, XCUT-08
- **Problem:** Pass 1 (F032) fixed the *memory cache* key to include targetSize (memoryCacheKey appends #WxH). But the in-flight de-duplication dictionary `inFlight` is still keyed by `url` only, and the awaited Task was created with o
- **Fix:** Key the in-flight map by the same composite memory key instead of by URL. (1) Change line 18 to `private var inFlight: [NSString: Task<NSImage?, Never>] = [:]`. (2) In image(for:targetSize:) reuse the already-computed `key`: replace `if let

### P2F049 · ✅ SyncedLyricsService and RomanizationService in-memory caches grow unbounded for app lifetime
- **File:** `Sources/Kaset/Services/Lyrics/SyncedLyricsService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** P2NEW-05
- **Problem:** `SyncedLyricsService.cache: [String: LyricResult]` (keyed by videoId) and `RomanizationService.cache: [String: String?]` (keyed by raw line text) are never evicted or capped. Both services are long-lived (constructed onc
- **Fix:** Only SyncedLyricsService.cache needs bounding (ignore the RomanizationService.cache part — it is dead in production). Add a simple FIFO/LRU cap: track insertion order and evict the oldest when exceeding a fixed limit (e.g. 100 tracks). Mini

### P2F050 · ✅ SearchViewModel search/suggestion Tasks capture self strongly, defeating its documented deinit cancellation
- **File:** `Sources/Kaset/ViewModels/SearchViewModel.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SRCH-26
- **Problem:** SearchViewModel's `searchTask` and `suggestionsTask` are created with `Task { ... await self.performSearch() ... }` capturing `self` STRONGLY (no `[weak self]`). This is inconsistent with every sibling view model — HomeV
- **Fix:** Mirror the sibling view models by adding `[weak self]` to the three task closures. For suggestionsTask (line 145): `self.suggestionsTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { 

### P2F051 · ✅ ar.lproj/tr.lproj regeneration (F029) is incomplete — actively-used keys still fall back to English
- **File:** `Sources/Kaset/Resources/ar.lproj/Localizable.strings` · **Confidence:** high · **Risk:** low
- **Stories:** _(infra/cross-cutting)_
- **Problem:** The pass-1 systems fix (commit e0b6ccb, F029) claims it regenerated 'complete ar.lproj/tr.lproj (263 keys each) ... matching fr/ko/id exports' to fix Arabic/Turkish falling back to English. The regeneration is incomplete
- **Fix:** Add the 3 user-facing keys with proper Arabic and Turkish translations to both Sources/Kaset/Resources/ar.lproj/Localizable.strings and Sources/Kaset/Resources/tr.lproj/Localizable.strings: "Search songs, albums, artists...", "Episodes", an

### P2F052 · ✅ AccentBackground (F034) reintroduced MainActor jank by calling the synchronous palette extractor on the main actor
- **File:** `Sources/Kaset/Views/AccentBackground.swift` · **Confidence:** high · **Risk:** low
- **Stories:** XCUT-04
- **Problem:** The pass-1 F034 fix (commit e0b6ccb) rewrote AccentBackground.loadPalette() to reuse ImageCache and cache palettes — both good — but in doing so it changed the extraction call from the off-MainActor async overload `Color
- **Fix:** In AccentBackground.swift line 97, run the synchronous extraction off the MainActor: replace `let extracted = ColorExtractor.extractPalette(from: image)` with `let extracted = await Task.detached(priority: .userInitiated) { ColorExtractor.e

### P2F053 · ✅ API key invalidated on ALL HTTP 400 responses — over-broad self-heal causes spurious re-bootstrap
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-03
- **Problem:** The pass-1 data fix (commit eb12d83) added `apiKeyProvider.invalidate()` in the `.httpError` branch of performRequest for any status 400 or 403, on the theory that a stale/rotated bootstrap key surfaces as 400/403. The 4
- **Fix:** In YTMusicClient.swift:1512-1518, drop the API-key invalidation from the `.httpError` branch entirely. The `.authError` branch (lines 1505-1511) already covers 401/403 (the statuses performNetworkRequest at 1571-1573 routes there), and that

### P2F054 · ✅ addToLibrary fast-path uses song.feedbackTokens?.add without checking isInLibrary (latent accidental-remove)
- **File:** `Sources/Kaset/Views/SharedViews/SongActionsHelper.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-20, DET-08
- **Problem:** The pass-1 F023 fix (commit 7848ab7) replaced the play-then-toggle hack with a proper API call, and the slow path correctly checks `metadata.isInLibrary == true` before adding. But the fast path takes `song.feedbackToken
- **Fix:** In SongActionsHelper.addToLibrary, gate the fast path on the song not being known-in-library so a future parser attaching toggle-style feedbackTokens to list Songs cannot cause an accidental remove. Replace `if let addToken = song.feedbackT
