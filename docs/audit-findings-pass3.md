# Boombox — Pass 3 Audit Findings (new axes) — RESOLVED

Third-pass audit on axes not covered by passes 1-2: **security, performance/main-thread, persistence & migration, network resilience, parser fuzzing, window/appearance/empty states**. 6-lens hunt (×2 runs unioned) -> 51 findings -> adversarial verify -> **48 confirmed** (2 refuted, 1 dup). **46 fixed**, 2 deferred (low-severity hygiene). Integrated branch: **1052 unit tests, 0 failures** (verified ×2); CI runs UI tests.

**Status: 46/48 fixed** — high 2, medium 10, low 36. Fix commit `612950d`.

**Deferred (low):** P3F004 (raw SAPISID retained on in-memory auth state but never consumed/logged — enum hygiene), P3F014 (sign-out clears *persisted* queue; live in-memory queue teardown needs cross-module wiring). Tracked for a follow-up.

**Note on PERF-002 (P3F007/P3F035):** the double JSON-encode of the queue was removed (single encode, ~50% less work); the write was kept **synchronous** rather than detached, because a fire-and-forget save races restore/clear and risks losing the queue if the app quits right after a track change. Further off-main work can be added later via debounced saves.


## HIGH severity

### P3F024 · ✅ Integer overflow trap in ParsingHelpers.parseDuration crashes on adversarial duration text
- **File:** `Sources/Kaset/Services/API/Parsers/ParsingHelpers.swift` · **Confidence:** high · **Risk:** low
- **Stories:** P2NEW-06
- **Problem:** parseDuration splits on ':' and does Int multiplication without overflow protection: for two components it computes components[0] * 60 + components[1], and for three components[0] * 3600 + components[1] * 60 + components
- **Fix:** Replace the trapping arithmetic with overflow-safe folding over the components. Treat each `:`-separated part as a place value and accumulate with bounds checking, returning nil on overflow or implausible values:  ```swift static func parse

### P3F039 · ✅ Sign-out and account switching never clear persisted favorites, saved queue, or recent searches — previous user's data leaks across accounts/sessions
- **File:** `Sources/Kaset/Services/Auth/AuthService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-09
- **Problem:** signOut() clears WebKit data plus APICache/URLCache (clearAccountScopedCaches), but does NOT clear the three persistent on-disk/UserDefaults stores that hold per-user content: favorites.json (FavoritesManager), the boomb
- **Fix:** Minimal fix: in AuthService.signOut(), after clearing WebKit/caches, also clear the user-scoped stores using existing APIs: await/await on MainActor call FavoritesManager.shared.clearAll(), RecentSearchesStore.shared.clearAll() (add a trivi


## MEDIUM severity

### P3F005 · ✅ STATE_UPDATE re-assigns state = .playing every tick, firing Observation to all observers ~2x/sec even when state is unchanged
- **File:** `Sources/Kaset/Services/Player/PlayerService+PlaybackRestoration.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-11
- **Problem:** applyObservedPlaybackState runs on every STATE_UPDATE message from the WebView observer (throttled to ~2/sec, see SingletonPlayerWebView+ObserverScript.swift UPDATE_THROTTLE_MS=500). When already playing, the branch `if 
- **Fix:** Guard both branches so @Observable scalars only mutate on actual change. Replace lines 128-134 with: `if isPlaying, self.state != .playing, self.state != .ended { self.state = .playing } else if !isPlaying, self.state == .loading || self.st

### P3F006 · ✅ Side-panel queue rebuilds the entire NSTableView (full reloadData) ~2x/sec during playback and never recycles cells
- **File:** `Sources/Kaset/Views/QueueSidePanelView.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** QUE-08, QUE-12, SET-19
- **Problem:** QueueSidePanelView.body reads `playerService.isPlaying`, so its body (and thus updateNSViewController) re-runs every time `state`/`isPlaying` notifies — which is ~2x/sec during playback (see PERF-001). updateNSViewContro
- **Fix:** Two-part: (1) Adopt cell reuse — give the cell a reuse identifier and use tableView.makeView(withIdentifier:owner:) in tableView(_:viewFor:row:), falling back to QueueTableCellView() only when nil; this makes prepareForReuse() effective and

### P3F007 · ✅ saveQueueForPersistence() runs two synchronous full-queue JSON encodes on the MainActor on every track change / queue mutation
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** PLAY-12, PLAY-11, PLAY-22
- **Problem:** saveQueueForPersistence() synchronously encodes the entire queue array TWICE on the @MainActor: once as `encoder.encode(self.queue)` (line 422, the legacy payload) and again inside `PersistedPlaybackSession(queue: self.q
- **Fix:** Minimal: eliminate the redundant second encode by dropping the legacy savedQueueKey/savedQueueIndexKey path and persisting only PersistedPlaybackSession (restore already prefers it at line 452). That halves the work with no behavior change.

### P3F025 · ✅ Integer overflow trap in LRCParser time math on untrusted LRCLib lyrics
- **File:** `Sources/Kaset/Services/API/Parsers/LRCParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-21
- **Problem:** LRCParser parses synced-lyric timestamps whose minute group is matched by \[(\d{2,}):... — an UNBOUNDED number of minute digits. Minute/second values are converted with Int(...) ?? 0 then combined as (mm * 60 * 1000) + (
- **Fix:** Bound the minute/second magnitude before multiplying, or use overflow-checked arithmetic. Minimal: clamp mm (e.g. `let mm = min(Int(...) ?? 0, 24 * 60)`) for both the word-level (line 54) and line-level (line 70) paths, or compute with `&*`

### P3F030 · ✅ Logout / session-expiry while in Focus or Small Player mode strands the window with broken chrome and mode never resets
- **File:** `Sources/Kaset/Views/MainWindow.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-16
- **Problem:** playerPresentationMode is app-level @State in KasetApp and is only ever reset to .standard by an explicit user/dock toggle. When the auth state flips to .loggedOut (manual sign-out via AuthService.signOut, or automatic A
- **Fix:** In MainWindow.handleAuthStateChange's `.loggedOut` case (MainWindow.swift:558), reset the presentation mode so the coordinator's onChange runs the .standard restore path: `if self.playerPresentationMode.wrappedValue != .standard { self.play

### P3F034 · ✅ PlayerBar polls CoreAudio HAL synchronously on the MainActor every 5 seconds (recurring main-thread stalls)
- **File:** `Sources/Kaset/Views/PlayerBar.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-18
- **Problem:** PlayerBar.refreshAudioOutputLoop() runs on the MainActor (it directly assigns the MainActor-isolated @State self.audioOutput with no executor hop) and loops forever with a 5s Task.sleep. Each iteration calls AudioOutputD
- **Fix:** Move the HAL queries off the MainActor: in refreshAudioOutputLoop, compute the values via `let output = await Task.detached { AudioOutputDeviceInfo.currentDefaultOutput() }.value` (and similarly availableOutputDevices() when the picker is o

### P3F035 · ✅ saveQueueForPersistence() JSON-encodes the entire (unbounded) queue twice, synchronously on the MainActor, on every track advance
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-02, QUE-05, QUE-18
- **Problem:** PlayerService.saveQueueForPersistence() runs on the @MainActor PlayerService and synchronously encodes the whole queue to JSON TWICE per call: once as `queueData = encoder.encode(self.queue)` (line 422) and again inside 
- **Fix:** Eliminate the redundant double-encode first (zero-risk, immediate win): drop the separate queueData = encode(self.queue) write, or derive the legacy queueData from the already-built PersistedPlaybackSession.queue so the queue is serialized 

### P3F037 · ✅ Queue side-panel table does a full reloadData() of the entire queue on every play/pause and currentIndex change
- **File:** `Sources/Kaset/Views/QueueSidePanelView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-04, QUE-08, QUE-12
- **Problem:** QueueListControllerRepresentable.updateNSViewController takes isPlaying and currentIndex as inputs (lines 88, 104-107). SwiftUI calls updateNSViewController whenever any input changes — including every isPlaying toggle. 
- **Fix:** In updateNSViewController, before overwriting context.coordinator.queue (line 105), diff the new queue against the coordinator's current queue by identity (e.g. compare the arrays of videoId). Only call viewController.tableView?.reloadData(

### P3F044 · ✅ NetworkMonitor never gates the request pipeline and defaults isConnected=true, so requests fire while offline and rely solely on slow URLSession timeouts
- **File:** `Sources/Kaset/Services/NetworkMonitor.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** SET-17
- **Problem:** NetworkMonitor.isConnected is consulted only by views to render an offline ErrorView; no service or ViewModel checks it before issuing a request (grep confirms zero references in Services/ or ViewModels/ except the monit
- **Fix:** Add a fast-fail at the top of the request pipeline: in YTMusicClient.request (and the key provider / LRCLib / image fetch paths), check `await NetworkMonitor.shared.isConnected` and throw `YTMusicError.networkError` immediately when false, 

### P3F046 · ✅ Integer-overflow trap in Song.parseDuration (Codable-style init(from:)) on malformed duration
- **File:** `Sources/Kaset/Models/Song.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-17
- **Problem:** Song.init?(from:) parses the `duration` string field via Song.parseDuration, which does `components[0] * 60 + components[1]` (line 118) and `components[0] * 3600 + components[1] * 60 + components[2]` (line 120) with the 
- **Fix:** In Song.parseDuration, replace the trapping arithmetic with overflow-checked operations and return nil on overflow, e.g.: for the 2-component case `guard let p = components[0].multipliedReportingOverflow(by: 60), !p.overflow, let s = p.part


## LOW severity

### P3F001 · ✅ Playback WebView has no navigation policy delegate — authenticated session can follow arbitrary navigations with script bridges attached
- **File:** `Sources/Kaset/Views/SingletonPlayerWebView.swift` · **Confidence:** medium · **Risk:** medium
- **Stories:** WEB-01
- **Problem:** The hidden DRM-playback WebView (`SingletonPlayerWebView`) is created with the shared persistent `WKWebsiteDataStore.default()` (which holds all YouTube/Google auth cookies), has the native `singletonPlayer` message brid
- **Fix:** Add `webView(_:decidePolicyFor:decisionHandler:)` to the playback Coordinator that allows the navigation only when scheme is https and host ends in `.youtube.com`/`.google.com`/`googleusercontent.com`/`ytimg.com` (the origins YTM playback a

### P3F002 · ✅ singletonPlayer JS message handler trusts any frame — no frameInfo / securityOrigin / isMainFrame validation
- **File:** `Sources/Kaset/Views/SingletonPlayerWebView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-13
- **Problem:** `userContentController(_:didReceive:)` (line 207) reads `message.body` and dispatches `TRACK_ENDED`, `REMOTE_NEXT`, `REMOTE_PREVIOUS`, `AIRPLAY_STATUS`, `LYRICS_TIME`, and `STATE_UPDATE` (driving track advancement, fake 
- **Fix:** At the top of `userContentController(_:didReceive:)` (after parameter, before the body guard), drop messages not from the trusted main frame: `guard message.frameInfo.isMainFrame, let origin = message.frameInfo.securityOrigin as WKSecurityO

### P3F003 · ✅ WebView-DOM thumbnail URL flows to URLSession with no http(s) scheme allowlist (local-file / data fetch)
- **File:** `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-11
- **Problem:** `updateTrackMetadata` builds `let thumbnailURL = URL(string: thumbnailUrl)` (line 474) directly from the `thumbnailUrl` string sent by the WebView observer (read from a DOM `img.src` and forwarded over the `singletonPlay
- **Fix:** Add a scheme guard at the trusted boundary in ImageCache.image(for:) (single chokepoint that protects all image fetches): at the top of the method, `guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { r

### P3F004 · ⏳ Raw SAPISID secret retained in-memory on the shared @Observable auth state's associated value but never consumed — _DEFERRED_
- **File:** `Sources/Kaset/Services/Auth/AuthService.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-16, WEB-19
- **Problem:** `AuthService.State` carries the raw SAPISID cookie value as an associated value in `case loggedIn(sapisid: String)` (line 14). `completeLogin(sapisid:)` (line 128) and `checkAuthStatus` (line 88) store the actual SAPISID
- **Fix:** Change `case loggedIn(sapisid: String)` to `case loggedIn` (boolean state only). Update `isLoggedIn` to `if case .loggedIn = self { return true }` (already pattern works). Replace the three `.loggedIn(sapisid: ...)` assignments (init line 4

### P3F008 · ✅ WebKitManager.forceBackupCookies / importAuthCookies run blocking Keychain writes on the MainActor despite 'off the main actor' intent
- **File:** `Sources/Kaset/Services/WebKit/WebKitManager.swift` · **Confidence:** high · **Risk:** low
- **Stories:** WEB-21
- **Problem:** WebKitManager is @MainActor (WebKitManager.swift:9). forceBackupCookies (line 294) and importAuthCookies (line 319) wrap the Keychain write in a plain `Task(priority: .utility) { ... }`. An unstructured `Task {}` created
- **Fix:** In forceBackupCookies (line 294) replace `Task(priority: .utility)` with `Task.detached(priority: .utility)` to match performCookieBackup. In importAuthCookies (line 319) replace `await Task(priority: .utility) {...}.value` with `await Task

### P3F009 · ✅ FavoritesManager.save() performs JSON encode + atomic disk write on the MainActor (Task{} inherits MainActor, not detached)
- **File:** `Sources/Kaset/Services/FavoritesManager.swift` · **Confidence:** high · **Risk:** low
- **Stories:** P2NEW-04
- **Problem:** FavoritesManager is @MainActor @Observable (line 21-23). save() schedules the write via `self.saveTask = Task(priority: .utility) { ... }` (line 137) — NOT Task.detached — so the closure inherits MainActor isolation. Con
- **Fix:** Change line 137 from `self.saveTask = Task(priority: .utility) {` to `self.saveTask = Task.detached(priority: .utility) {` so the encode + file I/O genuinely run off the main actor as the comment intends. All captured values are Sendable va

### P3F010 · ✅ SyncedLyrics.currentLineIndex allocates a full [LineStatus] array per call at ~10Hz during synced-lyric playback
- **File:** `Sources/Kaset/Models/SyncedLyrics.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-05
- **Problem:** While synced lyrics are active, the WebView observer pushes LYRICS_TIME at 10Hz (SingletonPlayerWebView+ObserverScript.swift:186-194, 100ms interval), each updating playerService.currentTimeMs. SyncedLyricsDisplayView.on
- **Fix:** Replace currentLineIndex with an allocation-free reverse linear scan (lines are time-sorted): func currentLineIndex(at timeMs: Int) -> Int? { var idx: Int? = nil; for i in lines.indices { let line = lines[i]; if line.timeInMs > timeMs { bre

### P3F011 · ✅ LRCParser compiles an NSRegularExpression inside the per-line parse loop
- **File:** `Sources/Kaset/Services/API/Parsers/LRCParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-23
- **Problem:** LRCParser.parse correctly hoists timeRegex/metadataRegex/wordRegex out of the loop (lines 13-15), but then inside the `for line in lines` loop it compiles a FOURTH regex from scratch on every metadata-matching line: `(tr
- **Fix:** Hoist the pure-metadata regex to a `static let` on the enum (e.g. `private static let pureMetadataRegex = try? NSRegularExpression(pattern: "^\\[([a-z]+):([^\\]]+)\\]\\s*$")`) and replace line 31 with `if let pure = Self.pureMetadataRegex, 

### P3F012 · ✅ ParsingHelpers.extractDurationFromAccessibilityLabel recompiles two regexes on every call, invoked per-track during list parsing
- **File:** `Sources/Kaset/Services/API/Parsers/ParsingHelpers.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-26, P2NEW-06
- **Problem:** extractDurationFromAccessibilityLabel compiles TWO NSRegularExpressions (minutePattern line 304, secondPattern line 311) freshly on every invocation. This is a per-item fallback in the duration-extraction path used while
- **Fix:** Hoist the three constant patterns to private static lazily-compiled NSRegularExpression instances and reuse them, e.g. `private static let minuteDurationRegex = try? NSRegularExpression(pattern: #"(\d+)\s*minutes?"#, options: .caseInsensiti

### P3F013 · ✅ WaveformView spawns a new Task{@MainActor} on every 30Hz timer fire to update the now-playing equalizer bars
- **File:** `Sources/Kaset/Views/QueueTableCellView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-24
- **Problem:** The current-track waveform animation runs a Timer at 30Hz (1.0/30.0, line 520) whose closure allocates a fresh `Task { @MainActor [weak self] in self?.updateBars() }` on every fire (lines 521-523). The Timer callback alr
- **Fix:** Replace the per-tick Task with MainActor.assumeIsolated since the timer closure already runs on RunLoop.main: `let timer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateBars() } }`. T

### P3F014 · ⏳ Saved playback queue/session is account-global and survives sign-out and account switch — _DEFERRED_
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** low
- **Stories:** PLAY-22
- **Problem:** The persisted queue is written to fixed, account-agnostic UserDefaults keys (`boombox.saved.queue`, `boombox.saved.queueIndex`, `boombox.saved.playbackSession`) with no per-account scoping. AuthService.signOut() (Sources
- **Fix:** Call playerService.clearSavedQueue() (which already exists at PlayerService+Queue.swift:486 and removes the persisted session) from AuthService.signOut() right after clearing WebKit/caches, and from AccountService.clearAccounts() and switch

### P3F015 · ✅ "Last Used" launch page never persists — always falls back to Home after relaunch
- **File:** `Sources/Kaset/Services/SettingsManager.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-04, XCUT-01
- **Problem:** SettingsManager exposes a `defaultLaunchPage` option of `.lastUsed`, whose resolved value is supposed to come from `lastUsedPage`. But `lastUsedPage` is declared as a plain in-memory property initialized to `.home` (`var
- **Fix:** Two parts. (1) Persist the property in SettingsManager: add a `lastUsedPage` key to `Keys`, give the property a `didSet { UserDefaults.standard.set(self.lastUsedPage.rawValue, forKey: Keys.lastUsedPage) }`, and initialize it in init from Us

### P3F016 · ✅ Favorites (favorites.json) are account-global and persist across sign-out / account switch
- **File:** `Sources/Kaset/Services/FavoritesManager.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** LIB-28, LIB-27
- **Problem:** FavoritesManager persists pinned items to a single shared file (`Application Support/Boombox/favorites.json`) with no account scoping, and nothing in the auth/account lifecycle clears or re-scopes it. AuthService.signOut
- **Fix:** Add FavoritesManager to the auth lifecycle the same way SongLikeStatusManager already is. Give FavoritesManager a setActiveAccountID(_:) that switches the backing file to a per-account name (e.g. favorites-<brandId>.json, with the legacy fa

### P3F017 · ✅ Recent searches persist across sign-out and are shared across all accounts
- **File:** `Sources/Kaset/Services/RecentSearchesStore.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SRCH-17
- **Problem:** RecentSearchesStore writes raw query strings to a single UserDefaults key (`settings.recentSearches`) with no account scoping, and there is no sign-out or account-switch hook that clears it. After a user signs out (or sw
- **Fix:** Add `RecentSearchesStore.shared.clearAll()` to AuthService.clearAccountScopedCaches() (called from signOut). Since clearAccountScopedCaches is a static method and RecentSearchesStore.shared is @MainActor, ensure the call site is on the Main

### P3F018 · ✅ Non-idempotent mutations (library feedback, subscribe/unsubscribe) are silently retried by RetryPolicy on network/5xx errors
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-06, API-20
- **Problem:** Every API call -- reads AND writes -- flows through the single private request() which unconditionally wraps the operation in RetryPolicy.default.execute (line 1435). RetryPolicy retries on any YTMusicError.networkError 
- **Fix:** Add a `retryable: Bool = true` parameter to private request() (line 1413) and, when false, call performRequest directly instead of RetryPolicy.default.execute. Pass retryable: false from the genuinely non-idempotent helper editSongLibrarySt

### P3F019 · ✅ RetryPolicy backoff has no jitter -- synchronized retries cause a thundering herd against YouTube Music
- **File:** `Sources/Kaset/Utilities/RetryPolicy.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-06
- **Problem:** RetryPolicy.delay computes min(baseDelay * pow(2.0, attempt), maxDelay) (line 13) -- pure deterministic exponential backoff with NO randomized jitter. The app fires many concurrent requests through the same RetryPolicy.d
- **Fix:** In delay(for:), add equal jitter while preserving the worst-case bound: let base = min(self.baseDelay * pow(2.0, Double(attempt)), self.maxDelay); return Double.random(in: (base * 0.5) ... base). This decorrelates concurrent retries without

### P3F020 · ✅ Request pipeline never consults NetworkMonitor -- offline requests fire and burn the full retry backoff (~3s+) before failing
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-06
- **Problem:** NetworkMonitor.shared already knows when the device is offline, but neither request() (line 1413), performRequest, nor RetryPolicy ever check NetworkMonitor.shared.isConnected -- confirmed by grep (no NetworkMonitor refe
- **Fix:** Two minimal options: (1) Treat connectivity-fatal URLErrors as non-retryable so the backoff budget isn't spent: in YTMusicError.isRetryable, for .networkError(underlying), return false when (underlying as? URLError)?.code is .notConnectedTo

### P3F021 · ✅ NetworkMonitor path updates hop to MainActor via unordered Tasks -- out-of-order delivery can strand isConnected on a stale value
- **File:** `Sources/Kaset/Services/NetworkMonitor.swift` · **Confidence:** medium · **Risk:** low
- **Stories:** SET-17
- **Problem:** NWPathMonitor delivers path updates serially on its DispatchQueue, but pathUpdateHandler forwards each one to the MainActor via an independent unstructured Task { @MainActor [weak self] in self?.updatePath(path) } (lines
- **Fix:** Replace the per-update Task spawn with an order-preserving channel. In startMonitoring(), create an AsyncStream<NWPath> whose continuation is yielded from pathUpdateHandler (continuation.yield(path) is safe to call from the monitor queue), 

### P3F022 · ✅ HTTP 429 rate-limit responses are mapped to a generic non-retryable 'Server Error' with no Retry-After handling
- **File:** `Sources/Kaset/Services/API/YTMusicClient.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-07
- **Problem:** performNetworkRequest special-cases only 401/403 (auth) -- every other non-2xx, including 429 Too Many Requests, falls into the generic .httpError(statusCode:) branch (lines 1563-1564) and is surfaced as YTMusicError.api
- **Fix:** Add a dedicated rate-limit case rather than overloading apiError. Minimal version: in performNetworkRequest, before the generic httpError fallthrough, special-case 429 and capture httpResponse.value(forHTTPHeaderField:"Retry-After"); plumb 

### P3F023 · ✅ ImageCache network fetch runs in an unstructured Task, so cancellation never reaches URLSession (download completes after view/prefetch is cancelled)
- **File:** `Sources/Kaset/Utilities/ImageCache.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** XCUT-08
- **Problem:** image(for:) performs the network download inside an unstructured Task<NSImage?, Never> { ... URLSession.shared.data(from: url) ... } (lines 93-104). Unstructured Task {} does NOT inherit cooperative cancellation from the
- **Fix:** Make cancellation propagate without breaking in-flight dedup. The dedup design stores a Task in inFlight keyed by URL+size, so simply awaiting URLSession directly (the finding's first option) would remove dedup; keep the Task but make cance

### P3F026 · ✅ Integer overflow trap in PodcastParser.parseDurationToSeconds
- **File:** `Sources/Kaset/Services/API/Parsers/PodcastParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-25, API-23
- **Problem:** parseDurationToSeconds converts episode duration strings ("36 min", "1:11:19") to seconds with unguarded Int multiplication. The "X min" branch does minutes * 60 and the colon branches do components[0] * 60 + components[
- **Fix:** Use overflow-checked arithmetic and return nil on overflow. In parseDurationToSeconds: replace `return minutes * 60` with `let (r, o) = minutes.multipliedReportingOverflow(by: 60); return o ? nil : r`; and for the colon branches build the s

### P3F027 · ✅ Unbounded recursion in LyricsParser.findTimedLyricsModel risks stack overflow on deeply nested response
- **File:** `Sources/Kaset/Services/API/Parsers/LyricsParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-22
- **Problem:** findTimedLyricsModel recursively walks every value of every dictionary and array in the entire next-endpoint response looking for a timedLyricsModel key, with NO depth limit. The sibling recursive search PlaylistParser.f
- **Fix:** Add a depth parameter mirroring the sibling: `private static func findTimedLyricsModel(in node: Any, depth: Int = 0) -> [String: Any]? { guard depth < 20 else { return nil }` and pass `depth + 1` on each recursive call. Trivial, consistent 

### P3F028 · ✅ PodcastParser silently drops playback progress when API encodes percentage as a non-Int number
- **File:** `Sources/Kaset/Services/API/Parsers/PodcastParser.swift` · **Confidence:** medium · **Risk:** low
- **Stories:** DET-25
- **Problem:** parseMultiRowListItem reads playback progress via playbackProgressPercentage as? Int. JSONSerialization bridges JSON numbers to NSNumber, and a fractional or float-encoded value (e.g. 33.0 deserialized as a Double-backed
- **Fix:** Replace `as? Int` with a number-tolerant read on line 258: `let percentage = (playbackProgressPercent["playbackProgressPercentage"] as? NSNumber)?.intValue`. This honors both integer- and float-encoded NSNumbers (and rounds toward zero), pr

### P3F029 · ✅ Latent integer overflow trap in Song.parseDuration (Song.init from data)
- **File:** `Sources/Kaset/Models/Song.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-17, XCUT-13
- **Problem:** Song's API convenience initializer Song.init?(from:) parses a duration string via the private Song.parseDuration, which performs the same unguarded components[0] * 60 + components[1] / components[0] * 3600 + ... multipli
- **Fix:** Either delete the unused Song.init?(from:)/Song.parseDuration (preferred, since they have no production callers — but tests depend on Song(from:), so deletion requires updating tests), or make parseDuration overflow-safe. Minimal safe versi

### P3F031 · ✅ didBecomeKey handler force-reopens an intentionally collapsed sidebar whenever ANY window (Settings, login sheet, menu-bar popover) becomes key
- **File:** `Sources/Kaset/Views/MainWindow.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-05
- **Problem:** MainWindow observes NSWindow.didBecomeKeyNotification without filtering on the notification object, and unconditionally forces columnVisibility back to .all. The app provides a deliberate Toggle Sidebar shortcut (⌃⌘S, Ma
- **Fix:** Switch the trigger from per-window key changes to a genuine app reactivation, and/or filter on the main window. Minimal: replace the `NSWindow.didBecomeKeyNotification` observer with `NSApplication.didBecomeActiveNotification`, so the sideb

### P3F033 · ✅ Onboarding window minimum size (500x500) is inconsistent with authenticated content (900x600), causing an abrupt resize/clip on login
- **File:** `Sources/Kaset/Views/OnboardingView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** AUTH-01
- **Problem:** OnboardingView sets .frame(minWidth: 500, minHeight: 500) while the authenticated mainContent and initializingView both set .frame(minWidth: 900, minHeight: 600). The Window scene declares no .windowResizability or .defa
- **Fix:** Align the minimum size across shell states: change OnboardingView.swift:82 from .frame(minWidth: 500, minHeight: 500) to .frame(minWidth: 900, minHeight: 600) to match initializingView and mainContent. Optionally also add .windowResizabilit

### P3F038 · ✅ QueueView (SwiftUI) rebuilds the entire queue-entry array (with per-row id string formatting) on every play/pause and track change
- **File:** `Sources/Kaset/Views/QueueView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** QUE-04, QUE-02, QUE-06
- **Problem:** QueueView.queueEntries is a computed property that calls QueueDisplayEntry.entries(for:), which enumerates the whole queue and allocates a new QueueDisplayEntry plus a freshly interpolated id string ('\(index)-\(song.vid
- **Fix:** Memoize entries keyed on a queue-identity token so they rebuild only when the queue changes, not on isPlaying/currentIndex passes. Simplest: have PlayerService expose the precomputed [QueueDisplayEntry] (rebuilt when queue mutates) and read

### P3F040 · ✅ FavoritesManager permanently discards skipped/unreadable favorite entries on the next save (no backup) when decode is only partially successful
- **File:** `Sources/Kaset/Services/FavoritesManager.swift` · **Confidence:** high · **Risk:** low
- **Stories:** P2NEW-04
- **Problem:** Pass-1 replaced the all-or-nothing favorites decode with a tolerant FailableDecodable that skips individual corrupt/outdated entries. But the partial-failure path is now a silent permanent-data-loss path. In load(), when
- **Fix:** In load(), inside the `if skipped > 0` block (after line 103), add `self.loadFailed = true` so the next save() backs up the original favorites.json to favorites.json.bak before overwriting it with the pruned subset. This reuses the existing

### P3F041 · ✅ Queue persistence writes three separate UserDefaults keys non-atomically, allowing index/queue/session desync on crash mid-write
- **File:** `Sources/Kaset/Services/Player/PlayerService+Queue.swift` · **Confidence:** high · **Risk:** medium
- **Stories:** PLAY-22
- **Problem:** saveQueueForPersistence() persists the playback state across three independent UserDefaults keys in sequence — savedQueueKey (the [Song] array), savedQueueIndexKey (the Int index), and savedPlaybackSessionKey (the full P
- **Fix:** Add a `let schemaVersion: Int` field to PersistedPlaybackSession and, on restore, validate the version before applying (treat mismatch/decode-failure as a migration path rather than a silent discard). The atomicity concern is low priority s

### P3F042 · ✅ RetryPolicy uses jitter-free deterministic exponential backoff → synchronized retry waves (thundering herd)
- **File:** `Sources/Kaset/Utilities/RetryPolicy.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-06
- **Problem:** delay(for:) computes min(baseDelay * 2^attempt, maxDelay) with no randomized jitter. Every request that flows through the shared RetryPolicy.default (which is the wrapper for ALL YTMusicClient.request() calls) retries at
- **Fix:** Add equal jitter to delay(for:): let capped = min(self.baseDelay * pow(2.0, Double(attempt)), self.maxDelay); return capped / 2 + Double.random(in: 0...(capped / 2)). This de-correlates concurrent retries with no behavioral risk (still boun

### P3F043 · ✅ Continuation (pagination) failure leaves token + hasMore intact with no backoff, so the scroll sentinel re-fires the failing request in a tight loop
- **File:** `Sources/Kaset/ViewModels/PlaylistDetailViewModel.swift` · **Confidence:** high · **Risk:** low
- **Stories:** DET-16
- **Problem:** When a continuation page fails, loadMore() in PlaylistDetailViewModel (and identically in LikedMusicViewModel) reverts loadingState to .loaded but does NOT clear continuationToken and does NOT set hasMore=false (lines 23
- **Fix:** In the generic catch block of both loadMore() implementations, stop the sentinel from re-firing the same request. Simplest: set `self.hasMore = false` (and optionally keep continuationToken so a future manual retry/refresh can resume) so th

### P3F045 · ✅ LRCLibProvider performs an unbounded-timeout lyrics fetch on URLSession.shared with no cancellation handling
- **File:** `Sources/Kaset/Services/Lyrics/Providers/LRCLibProvider.swift` · **Confidence:** high · **Risk:** low
- **Stories:** LYR-21
- **Problem:** LRCLibProvider.search() issues `URLSession.shared.data(for: request)` with no custom timeoutInterval, inheriting the default 60s request / 7-day resource timeout, and catches every error (including CancellationError) int
- **Fix:** In LRCLibProvider.search(), set a short timeout: `request.timeoutInterval = 10` after creating the request (line 35). And before the catch swallows everything, re-throw cancellation: change the catch to `catch is CancellationError { return 

### P3F047 · ✅ Integer-overflow trap in extractDurationFromAccessibilityLabel minute/second math
- **File:** `Sources/Kaset/Services/API/Parsers/ParsingHelpers.swift` · **Confidence:** high · **Risk:** low
- **Stories:** API-26
- **Problem:** extractDurationFromAccessibilityLabel extracts `(\d+)` minute and second values from an artist-page accessibility label and returns `TimeInterval(minutes * 60 + seconds)` (line 319) using the trapping `*`/`+` operators. 
- **Fix:** Replace line 319 with overflow-safe arithmetic, e.g. compute in Double or use reporting operators: `let (m, mOverflow) = minutes.multipliedReportingOverflow(by: 60); guard !mOverflow else { return nil }; let (total, addOverflow) = m.addingR

### P3F048 · ✅ Unbounded recursion in SearchResponseParser.parseSearchSections on nested itemSectionRenderer wrappers
- **File:** `Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift` · **Confidence:** high · **Risk:** low
- **Stories:** SRCH-10
- **Problem:** parseSearchSections recursively re-enters itself for each nested `itemSectionRenderer.contents` entry (line 154) with no recursion-depth guard. A normal search response nests these one or two levels, but an adversarial r
- **Fix:** Add an overload with a depth parameter and cap descent: private static func parseSearchSections(_ sectionData: [String: Any], depth: Int = 0) -> [DraftSection]. At the top, guard depth < 16 else { logger.debug(...); return [] }. In the recu

### P3F050 · ✅ Three error toasts render at the same Y position and overlap when multiple errors fire together
- **File:** `Sources/Kaset/Views/MainWindow.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-18, P2NEW-01
- **Problem:** MainWindow attaches three independent top-aligned overlays — AccountErrorToast, ContentActionErrorToast, and PlaybackErrorToast — each with the identical .overlay(alignment: .top) and .padding(.top, 60). Each toast manag
- **Fix:** Replace the three independent .overlay(alignment: .top) blocks in MainWindow.swift (176-190) with a single top overlay containing a VStack(spacing: 8) that holds AccountErrorToast(), ContentActionErrorToast(), and PlaybackErrorToast() with 

### P3F051 · ✅ Sidebar profile shows an infinite loading skeleton when logged in but the accounts list returns empty
- **File:** `Sources/Kaset/Views/SidebarProfileView.swift` · **Confidence:** high · **Risk:** low
- **Stories:** NAV-17
- **Problem:** SidebarProfileView.loggedInContent renders: currentAccount -> profile; else if lastError != nil && !isLoading -> error/retry; else -> loadingStateView (skeleton). AccountService.fetchAccounts() sets currentAccount = resp
- **Fix:** In SidebarProfileView.loggedInContent, add an explicit terminal branch before the loading fallback: after the currentAccount and error branches, add `else if !accountService.isLoading { errorStateView }` (or a dedicated minimal "no account 
