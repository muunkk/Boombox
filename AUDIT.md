# Trust Boundary Audit

Fork base: see `FORK_BASE.txt` (upstream `sozercan/kaset@700b72d`).

This file tracks the current public trust boundary for Boombox after the strip and rebrand. Historical strip notes live in `STRIPPED.md` and `PROGRESS.md`.

## Network Endpoints

`rg -n "https://" Sources/` currently shows:

| Host | Where | Purpose | Verdict |
|------|-------|---------|---------|
| `music.youtube.com` | `YTMusicClient.swift`, `MiniPlayerWebView.swift`, `ShareService.swift`, `WebKitManager.swift` | InnerTube API, playback, auth origin, share-link construction | Expected |
| `i.ytimg.com` | `Song.swift` | Track thumbnails | Expected |
| `lrclib.net` | `LRCLibProvider.swift` | Synced-lyrics fallback | Expected |
| `example.com` | `AccountRowView.swift` | `#Preview` placeholder avatar | Harmless (dev-only) |

**No telemetry, no analytics SDKs, no crash reporters, no A/B hosts.**

Removed upstream endpoints: Sparkle/GitHub release checks and the Last.fm scrobble proxy are gone. Remaining network trust is Google/YouTube/YTImg for the music service and LRCLib for optional synced lyrics.

## Cookies And Keychain

All cookie & Keychain logic lives in `Sources/Kaset/Services/WebKit/WebKitManager+Cookies.swift`. Read end-to-end. Behavior:

- Serializes auth cookies (SAPISID, `__Secure-3PAPISID`, SID, HSID, SSID, APISID, LOGIN_INFO, etc.) via `NSKeyedArchiver`.
- Allows only YouTube/Google auth cookie names and YouTube/Google cookie domains.
- Stores archive in Keychain with:
  - `kSecClass = kSecClassGenericPassword`
  - `kSecAttrService = "com.melboonchan.boombox.auth-cookies"`
  - `kSecAttrAccount = "youtube-music-cookies"`
  - `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Restores cookies into `WKWebsiteDataStore.default()` on launch via `WebKitManager`.

The cookie lives in `WKWebsiteDataStore` scoped to the `music.youtube.com` / `.youtube.com` / `.google.com` domains. WebKit handles per-host scoping. The `SAPISIDHASH` header computation in `YTMusicClient.swift` is only added to InnerTube requests targeting `music.youtube.com/youtubei/v1`, so the hash is not sent to non-Google hosts.

## JavaScript Bridges

`WKScriptMessageHandler` attach points:

| Handler name | File | Purpose |
|--------------|------|---------|
| `singletonPlayer` | `MiniPlayerWebView.swift:273` | Core player-state events (play/pause/progress/track-change) from the hidden YTM WebView |
| `miniPlayer` | `MiniPlayerWebView.swift:49` | UI overlay / media-control relay in the visible mini-player |

The login WebView uses `createLoginWebViewConfiguration()`, which installs a fresh `WKUserContentController` and no native script message handlers for the sign-in surface.

## Logging

`DiagnosticsLogger` is an `os.Logger` wrapper defined under `Sources/Kaset/Utilities/`. Messages are visible in Console.app. Grep for SAPISID / Cookie / Authorization mentions in logger calls:

```
grep -rn -iE '(SAPISID|Cookie|authorization)' Sources/ | grep -iE '(log\(|logger\.|print\()'
```

Current result: log messages mention "cookies" by count (e.g. `"Saved \(cookieCount) auth cookies to Keychain"`), never by value. No plaintext cookie logging in upstream. ✅

Redaction posture will be preserved after strip. If future code paths add cookie-adjacent logging, the CLAUDE.md rule ("NEVER leak secrets...") already covers it.

## Telemetry, Analytics, Crash Reporters, Update Check-Ins

Grep: `Analytics`, `Telemetry`, `Mixpanel`, `Segment`, `Sentry`, `Crashlytics`, `PostHog`, `Amplitude`, `Firebase`. **Zero hits** in `Sources/`. ✅

Sparkle and release-check code were removed. Boombox has no auto-updater and no update check-in.

## Package.swift dependencies

`Package.swift` currently has an empty `dependencies` array. All remaining imports are Apple frameworks (`SwiftUI`, `WebKit`, `AppKit`, `MediaPlayer`, `Foundation`, `os`, `Security`, and related system frameworks).

## Entitlements (`Kaset.entitlements`)

```
app-sandbox              = true   ✅ sandboxed
cs.jit                   = true   needed for WebKit JS JIT
network.client           = true   needed for API + WebView
files.user-selected.*    = true   scoped file picker access (share-sheet attachments, etc.)
files.bookmarks.app-scope = true  security-scoped bookmarks (persistent user-selected file refs)
```

Nothing broad. No `network.server`, no `device.audio-input`, no `automation.apple-events`, no `inherit`. Reasonable. No changes needed.

## Summary

Remaining external trust: Google/YouTube Music, Apple's system frameworks, and optional LRCLib lyrics lookup. Removed surfaces include Sparkle auto-update, Last.fm scrobbling, WebExtensions, AppleScript, custom URL schemes, the API explorer, AI features, and binary distribution tooling.
