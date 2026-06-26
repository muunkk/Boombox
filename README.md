# Boombox

> A native macOS client for YouTube Music. Built in SwiftUI, runs on your Premium subscription, ships zero telemetry.

![Pre-release](https://img.shields.io/badge/status-pre--release-orange)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

Based on [Kaset](https://github.com/sozercan/kaset) by [@sozercan](https://github.com/sozercan), stripped down for a personal source-build use case. See [Attribution](#attribution).

![Boombox screenshot](docs/screenshot.png)

## Pre-release notice

Boombox is a personal project in pre-release. There is no App Store distribution. Signed DMG releases are available on the [Releases page](https://github.com/muunkk/Boombox/releases); you can also clone the repo and build from source. Expect rough edges — report them in Issues.

## Features

### Playback & sound
- **YouTube Music Premium playback.** DRM-protected playback stays inside a hidden `WKWebView` using your existing subscription.
- **System integration.** Now Playing in Control Center, media keys, Dock right-click menu, haptics, optional track notifications.
- **Audio-only playback** and a CoreAudio output picker with AirPods detection.
- **Lyrics.** Plain YouTube Music lyrics and synced [LRCLib](https://lrclib.net) lyrics with line-by-line highlighting.
- **Queue management.** View, reorder, shuffle, undo/redo, and clear the playback queue.

### Native macOS UI
- **SwiftUI + Liquid Glass.** Glass player bar, sidebar navigation, Focus and Small Player presentation modes.
- **Resizable side panel.** Drag the leading edge of the lyrics/queue panel; width persists across launches. Two-finger swipe inside the panel switches between lyrics and queue.
- **Trackpad navigation.** Two-finger swipe back/forward in any tab, with a Safari-style chevron indicator that tracks the gesture. Works with both the "swipe with two fingers" and the default "swipe with two or three fingers" trackpad settings.
- **Esc** closes the lyrics or queue panel.
- **Hidden scrollbars** across the app for a cleaner look.
- **Album / song badges** on cards and rows so you can tell content types apart at a glance.

### Menu bar player
- **Optional menu bar item** with a compact Now Playing-style popover: artwork, scrubber, shuffle / prev / play / next / repeat, like, queue list, audio-output picker, volume slider (scroll anywhere in the popover to adjust volume), open-app shortcut.
- **Recordable global hotkey** to toggle the popover from anywhere (`Settings → General → Menu Bar Shortcut`).

### Sidebar
- **Search → Home → Library → Liked Music → Explore → New Releases → History.** `⌘1`–`⌘7` jump between them. Hold `⌘` to see Ghostty-style `⌘N` keycap badges next to each row.
- **Recordable hotkey** to show/hide the sidebar.
- **Now-playing card** with hover play/pause on the artwork, click title/artist to navigate to the album/artist page, and persists as a floating card when the sidebar is collapsed (the card slides in from behind the player bar).

### Browsing
- **Library and Home** support **grid / list** view modes plus **default / compact** density (toolbar pickers).
- **Search history.** Recent searches appear when the search box is empty; click to re-run, remove individual entries, or clear all.
- **Refresh button** in the toolbar (and `⌘R`).
- **Quick Picks** is pinned to the top of Home regardless of API order.

### Share & command
- **Share sheet** — songs, playlists, albums, artists.
- **Command palette** (`⌘L`).

## Requirements

- macOS 26.0 or newer (Liquid Glass APIs)
- Swift 6.2+ toolchain — Xcode 26+ or a swift.org toolchain
- A YouTube Music Premium subscription (required for DRM playback)
- Optional: a local Apple Development certificate for signing — the build falls back to ad-hoc signing if none is present

## Install

1. Download the latest `Boombox-<version>.dmg` from the [Releases page](https://github.com/muunkk/Boombox/releases).
2. Open the DMG and drag **Boombox** into your **Applications** folder.
3. Launch it from Applications. Releases are signed with a Developer ID and notarized, so they open without Gatekeeper warnings.

## Updates

Boombox keeps itself up to date with [Sparkle](https://sparkle-project.org):

- It checks for updates automatically once a day in the background.
- You can check any time via **Boombox → Check for Updates…**.
- When an update is found it downloads, verifies, installs, and offers to relaunch — no manual reinstall.

## Changelog

### 1.0.0 — Quality & hardening release

The first stable release. Following a three-pass code audit (134 issues found, 132 fixed), this release is overwhelmingly about making the existing experience correct, responsive, accessible, and trustworthy. Full per-issue detail lives in [`docs/audit-findings.md`](docs/audit-findings.md), [`docs/audit-findings-pass2.md`](docs/audit-findings-pass2.md), and [`docs/audit-findings-pass3.md`](docs/audit-findings-pass3.md); the canonical feature catalog is [`docs/user-stories.csv`](docs/user-stories.csv).

#### New in this release
- **Automatic updates** via [Sparkle](https://sparkle-project.org) — Boombox checks once a day in the background and can download, verify, install, and relaunch itself; also on demand via **Boombox → Check for Updates…**. See [Updates](#updates).
- **Signed & notarized DMG releases** on the [Releases page](https://github.com/muunkk/Boombox/releases), produced by a one-command release pipeline (build → notarize → DMG → appcast).
- The README screenshot is redacted of any signed-in account details.

#### Playback & queue
- **Shuffle actually shuffles.** Pressing **Next** with shuffle on no longer restarts the current song or starves part of the queue — it now excludes the current track the way Apple Music / YT Music do.
- **Single song + shuffle + repeat-off** no longer loops that one song forever at the end.
- **"Add to Library" no longer hijacks playback.** Saving a song used to interrupt your current track and start playing the saved one; it now saves silently in the background. The same content actions also no longer risk removing a song you meant to add.
- **Starting a Mix is clean.** The first Mix track keeps its real title, artist, and **artwork** instead of flashing a "Loading…" placeholder, and it keeps its **Go to Album / Go to Artist** links. Mixes also correct YouTube autoplay drift so the right track plays.
- **Per-track state is correct.** Right after a Mix or repeat-one starts, the **like** indicator and the **Library** toggle now reflect the *current* song, not the previous one (previously you could like/save the wrong track).
- **Duplicate songs in a queue render correctly.** Playlists/albums that legitimately repeat a track no longer show missing rows, mark the wrong row as now-playing, or remove/play the wrong copy.
- **Smoother track transitions.** Fixed WebView/queue desync that could jump to the next song and snap back, double-load the page, briefly play the wrong track, or drop the AirPlay connection near track boundaries; and recovery from a WebView content-process crash no longer leaves a stuck timeline.
- **Seek bar precision & polish.** The scrubber and remaining-time are now sub-second (no more 1-second snapping), no longer flicker to `-0:00` on every track change, and a freshly loaded paused track no longer gets stuck showing a loading state.
- **Stop / Clear** now properly disables the menu-bar transport controls instead of leaving live play/pause on a cleared player.

#### Browsing, detail pages & navigation
- **Your place is preserved per tab.** Drilling into an artist/album/playlist/search detail and then switching sidebar tabs no longer throws away where you were — each tab keeps its own navigation stack when you come back.
- **"Show all albums" on artists works again** (an internal enrichment step had been dropping the album-pagination data that powers it).
- **Pagination is reliable.** "Load more" on a playlist/album/search no longer appends tracks from a *different* list you viewed earlier, and no longer stops early when a page legitimately repeats a track.
- **Real error & empty states** where there were blank screens before: podcast shows now show an error-with-retry and a proper "no episodes" state; Home / Explore / New Releases / History show a clear empty state instead of a blank page; an artist's "See all top songs" now shows an error+retry like "See all albums" already did.
- **Failures are visible.** Tapping **Mix** or **Subscribe/Unsubscribe** on an artist while offline or on an API error now tells you it failed instead of silently doing nothing; library/like/queue/album actions now surface a toast on failure.
- **Detail pages handle offline** with the same immediate "No Connection" card the tabs show, and auto-recover when the network returns.
- **Cleaner metadata.** Home carousels no longer show junk "artists" (years, "Album", view counts), and radio/mix tracks now list all credited artists instead of just the first.

#### Search
- **Filter chips no longer disappear** when a filter returns zero results — you can switch back to a populated filter without retyping your query.
- **Podcasts now appear in the unified "All" results**, not only under the dedicated podcasts filter.
- **"Load more" in filtered search works** with YouTube's current (2025) results format.
- Keyboard-highlighted autocomplete suggestions are now exposed to VoiceOver and don't rely on color alone.

#### Library, Favorites & history
- **Your Favorites are safe.** A single corrupt or older-format entry no longer wipes your entire Favorites collection — unreadable entries are skipped (and backed up) while the rest load.
- **History fixes.** Removed a duplicate Refresh button, added an empty state, fixed row identity so refreshes don't show stale/mis-highlighted rows, and stopped caching history continuation pages so newer plays show up promptly.
- **Likes are consistent.** Rapid like/unlike is now serialized so the saved rating can't desync from what's shown, and a failed rating surfaces a toast.

#### Lyrics
- **Fixed a crash** romanizing Hindi/Bengali (and some Chinese/emoji) synced lyrics, and **moved romanization off the main thread** so loading lyrics or toggling romanization no longer hangs the UI on long CJK songs.
- **Lyric lines are accessible** — VoiceOver can tap a line to seek and can tell which line is currently active.
- Hardened LRC parsing against malformed/adversarial lyrics (overflow and deep-nesting guards) and made parsing a bit faster.

#### Player bar, Now Playing & visual polish
- **No more periodic stutter.** The player bar stopped doing a synchronous CoreAudio device query every 5 seconds, and stopped re-notifying every view ~twice a second during playback — both caused recurring micro-stutters/beachballs, especially with the queue panel open.
- **The queue side panel is smooth** — it no longer rebuilds the entire table (with flicker and re-loaded artwork) on every play/pause and track change.
- **Sharper artwork.** The image cache now keys by display size, so album art/thumbnails no longer appear blurry (a small thumbnail reused at full size) or waste memory.
- **Accent background** behind Now Playing now reuses cached artwork and caches its extracted palette, so it keeps up with the artwork and stops doing redundant downloads/CPU work.
- The menu-bar queue no longer shows stale artwork/titles when the queue changes.

#### Accounts & sign-in
- **No cross-account leakage.** Signing out now clears cached library/liked/history data, and Favorites / recent searches / saved queue are cleared and scoped per account, so a different person signing in on a shared Mac doesn't see the previous user's data. *(Note: tearing down the live in-memory queue on sign-out is tracked as a follow-up — see [Known limitations](#known-limitations).)*
- **No UI stalls during sign-in** — Keychain cookie writes (including the Safari sign-in fallback) now run off the main thread.
- Fixed an infinite loading shimmer in the sidebar profile when the account list comes back empty.

#### Settings & keyboard shortcuts
- **Search typing is protected.** Global player shortcuts (Space, ⌘←/→/↑/↓) no longer intercept text editing while the Search field is focused.
- **Reserved-shortcut warning.** The in-app shortcut recorder now warns if you try to bind a standard macOS shortcut (⌘Q / ⌘W / ⌘M / ⌘,).
- The **Toggle Sidebar (⌃⌘S)** shortcut is now documented, and your **last-used launch page** is now remembered across relaunches.

#### Localization
- **French and Indonesian are fixed.** Their translations were almost entirely scrambled (every label mapped to an unrelated word); both are now correct, including strings that carry values (e.g. "Connected as …", "Error: …").
- **Arabic and Turkish now actually localize** — stale 2-key stub files were replaced with the full translations.
- **~59 previously English-only strings now translate** across Arabic, French, Indonesian, Korean and Turkish — the menu-bar player, command bar, all hotkey/menu-bar settings, the Safari sign-in flow, and toolbar controls. Sign-in help text and a few interpolated status messages that could *never* localize were fixed too.
- The Now Playing panel chevron now points the correct way in right-to-left (Arabic) layouts.

#### Accessibility (VoiceOver)
- The **editable queue** (both the AppKit side panel and the glass queue) is now usable with VoiceOver: rows announce as buttons you can activate to play, expose the now-playing row, and no longer leave "Unknown Artist" hardcoded in English.
- Added labels/traits for **lyric lines, error/info toasts** (now announced), **account rows, the sidebar profile, the hotkey recorder, favorites cards, the display-mode/density toolbar pickers**, and arrow-key-selected suggestions.
- New Releases and History screens gained the structural identifiers other tabs already had.

#### Window, layout & empty states
- Logging out (or a session expiry) while in **Focus** or **Small Player** mode no longer strands the window with broken chrome — it resets to the standard layout.
- A collapsed sidebar **stays collapsed** when Settings, the login sheet, or the menu-bar popover becomes active (it used to force itself back open).
- The onboarding window size is now consistent with the signed-in window, so logging in no longer causes an abrupt resize/clip.
- Multiple error toasts that fire together now stack instead of overlapping into an unreadable pile.

#### Performance & responsiveness
- Moved heavy work off the main thread: CoreAudio device polling, queue encoding (now a single, synchronous-but-durable encode instead of a double encode), Keychain writes, Favorites saves, accent-palette extraction, and lyric romanization.
- Reduced steady-state overhead: gated needless playback-state re-notifications, optimized the queue panel, precompiled LRC/duration regexes, trimmed per-frame allocations in the now-playing equalizer and synced-lyrics cursor, and bounded the lyrics/romanization in-memory caches (they previously grew for the app's lifetime).
- The image cache now de-duplicates by size and propagates cancellation, so off-screen/cancelled image loads stop instead of completing in the background.

#### Stability & crash fixes
- Fixed **crashes** from: the lyrics romanizer (UTF-16 string indexing), reordering the queue while it changes mid-drag, and **integer overflows** in duration/timestamp parsing (`ParsingHelpers`, `Song`, `LRCParser`, `PodcastParser`) on malformed data.
- Added **recursion depth limits** to the lyrics and search-results parsers so a pathologically nested API response can't overflow the stack.
- Fixed an event-handler leak (and use-after-free risk) in the global hotkey service, and a slow leak of mouse-event monitors from the menu-bar popover.

#### Privacy & security
- Zero telemetry remains (no analytics, no crash reporters).
- Hardened the playback WebView trust boundary (defense-in-depth): it now restricts top-level navigations to the expected YouTube/Google origins, validates that JS-bridge messages come from the real main frame/origin, and rejects non-`http(s)` thumbnail URLs.
- Sign-out data clearing (above) closes the cross-account data-leak path.

#### Data accuracy & API resilience
- Pagination cursors are now per-request across playlists, albums, liked songs, search, and home/explore feeds (no cross-contamination), with support for YouTube's current (2025) continuation format.
- Network behavior hardened: offline requests fail fast instead of burning the full retry backoff, retries use jitter (no thundering herd) and no longer retry non-idempotent mutations, `429` responses honor `Retry-After`, the API key only re-bootstraps when appropriate, and connectivity updates can't strand a stale offline/online state.

#### Known limitations / follow-ups
A short list of low-severity items intentionally deferred (several pending live-app feedback) is tracked in [`docs/deferred-followups.md`](docs/deferred-followups.md).

## Build from source

```bash
git clone https://github.com/muunkk/Boombox
cd <repo>
swift build
swift test --skip KasetUITests
Scripts/build-app.sh release
open .build/app/Boombox.app
```

The resulting bundle is `.build/app/Boombox.app` with bundle id `com.melboonchan.boombox`. Signing uses a local Apple Development certificate when one is available and falls back to ad-hoc signing.

To install it in Applications:

```bash
cp -R .build/app/Boombox.app /Applications/
open /Applications/Boombox.app
```

## Signing in

Boombox plays through YouTube Music using your own Premium subscription. Google passkeys usually do not work inside an embedded login WebView, so the recommended first-run flow is Safari sign-in:

1. Open Boombox and choose **Sign in with Google**.
2. In the login sheet, choose **Use Safari sign-in**.
3. Click **Open YouTube Music in Safari**.
4. Sign in to `music.youtube.com` in Safari and complete any passkey, 2FA, or account prompts there.
5. Copy your own Safari YouTube/Google auth cookie rows, or a `Cookie:` header from your own Safari session, into the **Safari cookie rows or Cookie header** box in Boombox. Safari Web Inspector or a trusted local cookie-export tool can provide this; Boombox accepts Netscape-style cookie rows, `Cookie:` headers, or `name=value` pairs separated by semicolons.
6. Click **Import Cookies**.

Boombox imports only allowlisted YouTube/Google auth cookies, requires `SAPISID` or `__Secure-3PAPISID`, stores them locally in the app's WebKit data store and macOS Keychain, then clears the paste box. Cookie values are never logged, exported, or sent anywhere by Boombox. Treat cookie values like passwords: do not paste them into issues, logs, chat, or third-party tools you do not trust.

Embedded sign-in is still available from the same sheet and may work for password-based Google sign-in. Safari sign-in is there so passkey users can authenticate in Safari instead of typing their Google password into the app.

## Using Boombox

- **Home** shows personalized YouTube Music recommendations with Quick Picks pinned at the top. Toggle grid vs. list and default vs. compact from the toolbar.
- **Library** loads your playlists, liked songs, artists, albums, and podcasts. Same grid/list and density toggles available.
- **Liked Music**, **Explore**, **New Releases**, and **History** round out the sidebar.
- **Search** finds songs, albums, artists, playlists, and podcasts. Recent queries are saved; click to re-run.
- **Command Bar** (`⌘L`) is the fast path: type a query, run a search, or use quick actions.
- **Player bar** controls playback, shuffle, repeat, likes/dislikes, queue, lyrics, AirPlay, and output volume.
- **Queue / Lyrics side panel** is resizable (drag the leading edge) and you can swipe horizontally inside the panel to switch between queue and lyrics. `Esc` dismisses it.
- **Focus Player** and **Small Player** switch the window into now-playing layouts while music continues.
- **Trackpad gestures** — two-finger swipe goes back/forward through navigation; a Safari-style chevron tracks the gesture.
- **Sidebar now-playing card** shows artwork (hover to play/pause), title (click to open the album), artist (click to open the artist), and stays visible as a floating card when you collapse the sidebar.
- **Menu bar item** (opt in from `Settings → General → Show in Menu Bar`) puts a compact Now Playing popover in the system menu bar with optional global hotkey. Scroll anywhere inside the popover to change volume.
- **Sidebar hotkey** — assign a global shortcut to show/hide the sidebar in `Settings → General`.
- **Media keys**, Control Center Now Playing, and the Dock right-click menu work with playback.

## Keyboard shortcuts

| Shortcut | Action |
| -------- | ------ |
| `Space` | Play / Pause |
| `⌘→` | Next track |
| `⌘←` | Previous track |
| `⌘↑` | Volume up |
| `⌘↓` | Volume down |
| `⌘S` | Toggle shuffle |
| `⌥⌘R` | Cycle repeat mode: Off, All, One |
| `⌘Y` | Toggle lyrics |
| `⇧⌘F` | Toggle Focus Player |
| `⇧⌘M` | Toggle Small Player |
| `⌘1` | Go to Search |
| `⌘2` | Go to Home |
| `⌘3` | Go to Library |
| `⌘4` | Go to Liked Music |
| `⌘5` | Go to Explore |
| `⌘6` | Go to New Releases |
| `⌘7` | Go to History |
| `⌘F` | Focus search field |
| `⌘L` | Open Command Bar |
| `⌘R` | Refresh page |
| `⌘0` | Show the main Boombox window |
| `Esc` | Dismiss the queue or lyrics panel |

Hold `⌘` over the sidebar to see the number for each section as a small `⌘N` badge. Two extra global hotkeys can be assigned in `Settings → General`: one to toggle the menu bar player, one to show/hide the sidebar.

Mute is available from the Playback menu. It intentionally has no default shortcut so macOS can keep `⌘M` for Minimize. Full reference: [docs/keyboard-shortcuts.md](docs/keyboard-shortcuts.md).

## What's different from upstream Kaset

Boombox removes distribution, AI, and extension infrastructure that isn't needed for a personal source build. Full list in [STRIPPED.md](STRIPPED.md). Highlights:

- **Removed:** Apple FoundationModels integration, Last.fm scrobbling, AppleScript support, `kaset://` URL scheme, WKWebExtension runtime, API explorer CLI.
- **Added:** Sparkle 2 auto-updater (in-app "Check for Updates…" + daily background checks) with a one-command release pipeline (`Scripts/release.sh`).
- **Kept:** native player UI, YouTube Music Premium playback, system media integration, LRCLib synced lyrics, library/search/queue/share.

Security and trust boundary notes live in [AUDIT.md](AUDIT.md).

## Architecture and docs

- [docs/architecture.md](docs/architecture.md) — component overview
- [docs/playback.md](docs/playback.md) — playback subsystem
- [docs/keyboard-shortcuts.md](docs/keyboard-shortcuts.md) — keybindings
- [docs/testing.md](docs/testing.md) — test strategy
- [docs/adr/](docs/adr/) — architecture decision records

## Contributing

Issues are open — bug reports and feature requests are welcome. PRs are reviewed case-by-case: because this is a personal fork, not every contribution will be merged, but thoughtful patches get read. For anything larger than a small fix, open an issue to discuss first.

## Known limitations

- No binary distribution — source build only
- Google passkeys unsupported inside the embedded login WebView (use Safari cookie import)
- macOS 26+ only (uses Liquid Glass APIs)
- Swift module is still named `Kaset` internally — preserved as natural upstream attribution

## Attribution

Boombox is a fork of [Kaset](https://github.com/sozercan/kaset) by [@sozercan](https://github.com/sozercan), forked at commit [`700b72d`](https://github.com/sozercan/kaset/commit/700b72d49e47d55d6f1b2fde6c5a73f70228843c). Without the original implementation this project would not exist — huge thanks.

## License

MIT — see [LICENSE](LICENSE). Original copyright © 2025 sozercan is preserved as required by the MIT terms. Fork-specific additions are also MIT.

## Disclaimer

Boombox is an unofficial personal application and is not affiliated with YouTube, YouTube Music, or Google. YouTube, YouTube Music, and related marks belong to Google LLC.
