# Pre-Strip Audit

Fork base: see `FORK_BASE.txt` (upstream `sozercan/kaset@700b72d`).

Read-through of the upstream source before any modifications. Purpose: confirm what the code actually does against what the README claims, so the private fork can trust its audited surface.

## Network endpoints — `grep -rn "https://"` on `Sources/`

All outbound HTTPS hosts present in upstream:

| Host | Where | Purpose | Verdict |
|------|-------|---------|---------|
| `music.youtube.com` | `YTMusicClient.swift`, `MiniPlayerWebView.swift`, `ShareService.swift`, `LoginWebView.swift` (redirect target), `APIExplorer/main.swift` | InnerTube API + playback + share-link construction | Expected |
| `i.ytimg.com` | `Song.swift` | Track thumbnails | Expected |
| `accounts.google.com` | `LoginWebView.swift` | Legacy sign-in URL (modernizing) | Expected — fixing in §6b Fix 1 |
| `lrclib.net` | `LRCLibProvider.swift` | Synced-lyrics fallback | Expected |
| `api.github.com` / `github.com/sozercan/kaset` | `WhatsNewProvider.swift`, `GeneralSettingsView.swift` link | Sparkle release check + "Source on GitHub" link | **Being stripped** (Sparkle); GH link will be updated or removed |
| `kaset-lastfm.sozercan.workers.dev` | `LastFMService.swift` | Last.fm scrobble proxy (third-party Cloudflare Worker) | **Being stripped** |
| `example.com` | `AccountRowView.swift` | `#Preview` placeholder avatar | Harmless (dev-only) |

**No telemetry, no analytics SDKs, no crash reporters, no A/B hosts.** Clean.

After strip: `api.github.com`, `github.com/sozercan/kaset`, and `kaset-lastfm.*.workers.dev` will be gone. Remaining hosts: Google/YouTube/YTImg + LRCLib. Nothing talks to this fork's author, Sparkle, or any third party.

## Cookies & Keychain

All cookie & Keychain logic lives in `Sources/Kaset/Services/WebKit/WebKitManager+Cookies.swift`. Read end-to-end. Behavior:

- Serializes auth cookies (SAPISID, `__Secure-3PAPISID`, SID, HSID, SSID, APISID, LOGIN_INFO, etc.) via `NSKeyedArchiver`.
- Stores archive in Keychain with:
  - `kSecClass = kSecClassGenericPassword`
  - `kSecAttrService = "com.kaset.cookies"`
  - `kSecAttrAccount = "youtube-auth"`
  - **`kSecAttrAccessible = kSecAttrAccessibleWhenUnlocked`** ⚠️
- Restores cookies into `WKWebsiteDataStore.default()` on launch via `WebKitManager`.

**Finding A — Keychain accessibility is iCloud-syncable.** `kSecAttrAccessibleWhenUnlocked` does not prevent iCloud Keychain sync. For an auth cookie, we want `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the cookie cannot leave this Mac even if iCloud Keychain is enabled. Fix planned in §6b Fix 3. Location: `WebKitManager+Cookies.swift:143`.

**Finding B — Per-host scope.** The cookie lives in `WKWebsiteDataStore` scoped to the `music.youtube.com` / `.youtube.com` / `.google.com` domains — WebKit handles per-host scoping correctly. The `SAPISIDHASH` header computation in `YTMusicClient.swift` is only ever added to InnerTube requests targeting `music.youtube.com/youtubei/v1`, so the hash never leaks to non-Google hosts. Verified by reading the request-construction paths.

## JavaScript bridges

`WKScriptMessageHandler` attach points:

| Handler name | File | Purpose |
|--------------|------|---------|
| `singletonPlayer` | `MiniPlayerWebView.swift:273` | Core player-state events (play/pause/progress/track-change) from the hidden YTM WebView |
| `miniPlayer` | `MiniPlayerWebView.swift:49` | UI overlay / media-control relay in the visible mini-player |
| `optionsDebug` | `ExtensionOptionsView.swift:41` | Pipes WebKit Extension options-page console to `DiagnosticsLogger` |

**Finding C — `optionsDebug` is being removed** with the WebExtensions strip. Leaves only `singletonPlayer` and `miniPlayer`, both scoped to our own WebView content (not to Google-served login pages).

**Finding D — Login WebView (`LoginWebView.swift`) currently reuses `WebKitManager.createWebViewConfiguration()`**, which attaches `webExtensionController`. During login the user is on a Google-controlled page; there should be no extension surface or native bridges active in that window. Fix planned in §6b Fix 4: split config into `createLoginWebViewConfiguration()` that returns a stripped-down setup with no bridges and no extension controller.

## Logging

`DiagnosticsLogger` is an `os.Logger` wrapper defined under `Sources/Kaset/Utilities/`. Messages are visible in Console.app. Grep for SAPISID / Cookie / Authorization mentions in logger calls:

```
grep -rn -iE '(SAPISID|Cookie|authorization)' Sources/ | grep -iE '(log\(|logger\.|print\()'
```

Current result: log messages mention "cookies" by count (e.g. `"Saved \(cookieCount) auth cookies to Keychain"`), never by value. No plaintext cookie logging in upstream. ✅

Redaction posture will be preserved after strip. If future code paths add cookie-adjacent logging, the CLAUDE.md rule ("NEVER leak secrets...") already covers it.

## Telemetry, analytics, crash reporters, update check-ins

Grep: `Analytics`, `Telemetry`, `Mixpanel`, `Segment`, `Sentry`, `Crashlytics`, `PostHog`, `Amplitude`, `Firebase`. **Zero hits** in `Sources/`. ✅

Sparkle does phone home to the GitHub releases API (`api.github.com/repos/sozercan/kaset/releases/*` via `WhatsNewProvider.swift`) for update checks. Removed as part of the strip.

## Package.swift dependencies

Only non-Apple dep: `https://github.com/sparkle-project/Sparkle@2.8.1`. Being removed.

Post-strip, the dependency graph contains zero external packages. All remaining imports are Apple frameworks (`SwiftUI`, `WebKit`, `AppKit`, `MediaPlayer`, `Foundation`, `os`).

## Entitlements (`Kaset.entitlements`)

```
app-sandbox              = true   ✅ sandboxed
cs.jit                   = true   needed for WebKit JS JIT
network.client           = true   needed for API + WebView
files.user-selected.*    = true   scoped file picker access (share-sheet attachments, etc.)
files.bookmarks.app-scope = true  security-scoped bookmarks (persistent user-selected file refs)
```

Nothing broad. No `network.server`, no `device.audio-input`, no `automation.apple-events`, no `inherit`. Reasonable. No changes needed.

## Summary of findings fed into the strip/hardening plan

1. **Keychain accessibility** — tighten to `ThisDeviceOnly` (Fix 3 in plan §6b).
2. **Legacy Google login URL + stale Safari 17 UA** — modernize (Fix 1).
3. **Login WebView reuses full config with WebExtensions enabled** — split out a stripped login config (Fix 4).
4. **WebExtensions subsystem is a latent attack surface** not listed among kept features — strip entirely.
5. **GitHub "Source on GitHub" link in GeneralSettingsView** — update to point at the private fork or remove, since upstream attribution now lives in `LICENSE` and `STRIPPED.md`.

All other surfaces reviewed clean.
