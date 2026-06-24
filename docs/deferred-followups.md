# Deferred Follow-ups (from the QA passes 1–3)

Outstanding items intentionally **not** fixed during the autonomous QA passes, captured here so they can be picked up later — several are best handled **after live-app / runtime feedback** (they involve real device behavior, multi-account use, or offline UX). All are **low / low-medium severity**; the high/medium findings were all fixed (see `audit-findings*.md`).

Status legend — **Trigger**: _anytime_ = safe to do now (pure code change); _needs feedback_ = validate against real app behavior first.

| ID | Area | Severity | Trigger | Summary |
|----|------|----------|---------|---------|
| P3F004 | Security/hygiene | low | anytime | SAPISID over-retention on in-memory auth state |
| P3F014 | Privacy | low | needs feedback | Live in-memory queue not torn down on sign-out |
| P3F039 | Privacy/multi-account | low-med | needs feedback | Recent searches + saved queue not account-scoped |
| P3F044 / P3F020 | Network/offline | low | needs feedback | Offline gating only on the main request path |
| P3F045 | Lyrics/concurrency | low | anytime | LRCLib cancellation not fully propagated |
| P3F003 | Security (defense-in-depth) | low | anytime | Add scheme guard at the ImageCache chokepoint too |
| STATE (Exit Focus) | UX consistency | low | anytime | "Exit Focus Player" menu item disabled when no track |

---

## P3F004 — SAPISID over-retention on in-memory auth state · _anytime_
- **Where:** `Sources/Kaset/Services/Auth/AuthService.swift` (`State.loggedIn(sapisid: String)`), `Tests/KasetTests/AuthServiceTests.swift`.
- **Problem:** The raw SAPISID cookie value is stored as the associated value of the `@Observable` `State.loggedIn(sapisid:)` case but is never consumed or logged anywhere (all readers use `state.isLoggedIn`). It's an unnecessary in-memory retention of a secret (no leak today).
- **Fix:** Change `case loggedIn(sapisid: String)` → `case loggedIn`. Keep `completeLogin(sapisid:)` (it's in `AuthServiceProtocol` and called from `LoginSheet`/tests) but ignore the value for `state`. Update `AuthServiceTests.swift` lines ~42, ~82, ~107–111 to drop the associated value.
- **Why deferred:** the enum change requires editing the test file, which was outside the fixing batch's allowlist. Pure mechanical change.

## P3F014 — Live in-memory queue not cleared on sign-out · _needs feedback_
- **Where:** sign-out call site (`GeneralSettingsView` / `AppServices` / `AppDelegate`), `PlayerService` (`clearSavedQueue()` exists).
- **Problem:** Sign-out now clears the **persisted** queue keys (so the previous account's queue won't auto-restore next launch — done in pass 3), but the **live** in-memory `PlayerService.queue` keeps playing/visible until relaunch.
- **Fix:** From the sign-out path, also call `playerService.clearSavedQueue()` + stop/clear the live queue. `AuthService` holds no `PlayerService` reference, so wire it via the sign-out call site (which has `AppServices`) or an `AppDelegate` observer of the `.loggedOut` transition.
- **Why deferred:** cross-module wiring outside the batch; validate the desired UX (does sign-out stop playback immediately?) against the running app.

## P3F039 — Recent searches & saved queue not account-scoped · _needs feedback_
- **Where:** `Sources/Kaset/Services/RecentSearchesStore.swift`, queue-persistence keys in `PlayerService+Queue.swift`, `AccountService.switchAccount(to:)`.
- **Problem:** Favorites got per-account scoping in pass 3, but recent searches and the saved queue are still global, so switching accounts can surface the other account's recent searches / queue.
- **Fix:** Namespace `settings.recentSearches` and the `boombox.saved.*` keys by `accountID` (mirror `SongLikeStatusManager`'s account scoping), and reset/reload them on account switch.
- **Why deferred:** broader refactor; best validated with real multi-account (primary + brand) testing.

## P3F044 / P3F020 — Offline gating only on the main request path · _needs feedback_
- **Where:** `YTMusicClient.request()` (gated ✅), but bypassed by `SearchViewModel` debounced search/suggestion dispatch, `ImageCache` prefetch, `LRCLibProvider` lyrics fetch, and `YTMusicAPIKeyProvider.fetchAPIKey` (15s timeout, no connectivity check).
- **Fix:** Add `NetworkMonitor` connectivity checks (fast-fail) at those entry points.
- **Why deferred:** validate against real offline/airplane-mode behavior to confirm the right UX (fail fast vs. queue).

## P3F045 — LRCLib cancellation not fully propagated · _anytime_
- **Where:** `Sources/Kaset/Services/Lyrics/Providers/LRCLibProvider.swift`, `LyricsProvider.swift` (protocol), `YTMusicSyncedProvider.swift`, lyrics-resolution call sites.
- **Problem:** Pass 3 added a 10s request timeout + a cooperative `Task.isCancelled` pre-flight, but a cancellation mid-request is still surfaced as `.unavailable` rather than re-thrown.
- **Fix:** Change the `LyricsProvider.search(info:)` protocol method to `async throws` and let `CancellationError` propagate; update conformers + call sites.
- **Why deferred:** protocol signature change spanning multiple files outside the batch.

## P3F003 — ImageCache scheme guard (defense-in-depth) · _anytime_
- **Where:** `Sources/Kaset/Utilities/ImageCache.swift` (`image(for:)`, before `URLSession.shared.data(from:)`).
- **Problem:** The WebView-thumbnail dataflow is already scheme-guarded at the boundary (pass 3), but adding a guard at the `ImageCache` chokepoint would protect **all** image callsites.
- **Fix:** `guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }`.

## STATE — "Exit Focus Player" menu item unreachable with no track · _anytime_
- **Where:** `Sources/Kaset/KasetApp.swift` (~line 275).
- **Problem:** "Exit Focus Player" is `.disabled(playerService.currentTrack == nil)`, so after logout-with-no-track it's unreachable while in focus mode — inconsistent with the "Small Player" item's condition. (The stranded-window bug itself was fixed in pass 3 by resetting the presentation mode on `.loggedOut`.)
- **Fix:** Align to `.disabled(currentTrack == nil && playerPresentationMode != .focus)`.
