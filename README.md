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
