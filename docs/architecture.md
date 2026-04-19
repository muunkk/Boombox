# Architecture

Boombox is a SwiftPM-first macOS 26 app. The public app/product identity is `Boombox` / `com.melboonchan.boombox`, while the Swift target and module remain `Kaset` to avoid unnecessary source churn and to preserve an upstream-attribution breadcrumb.

## Core Shape

- `Sources/Kaset/KasetApp.swift` wires the app-scoped services into SwiftUI scenes.
- `Sources/Kaset/Views/MainWindow.swift` hosts the navigation shell, player bar, queue, lyrics, onboarding, and login sheet.
- `Sources/Kaset/Services/Player/` owns queue state, playback coordination, media key handling, Now Playing updates, and WebView synchronization.
- `Sources/Kaset/Views/MiniPlayerWebView.swift` and related `SingletonPlayerWebView` files keep YouTube Music playback in a single persistent `WKWebView`.
- `Sources/Kaset/Services/API/YTMusicClient.swift` talks to YouTube Music's web API for metadata, search, library, lyrics, and queue support.
- `Sources/Kaset/Services/WebKit/` owns the shared WebKit data store, Keychain cookie persistence, and Safari sign-in fallback import.
- `Sources/Kaset/Services/Lyrics/` combines YouTube Music plain lyrics with optional LRCLib synced lyrics.

## Auth Boundary

The main playback WebView and login WebView share the same `WKWebsiteDataStore`, but login uses `createLoginWebViewConfiguration()` so no native script message handlers are attached to the sign-in surface.

Auth cookies are allowlisted by name and Google/YouTube domain before persistence. The Keychain item uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` under `com.melboonchan.boombox.auth-cookies`.

Google passkeys are handled through Safari. The fallback view opens YouTube Music in Safari and imports pasted allowlisted auth cookies locally into WebKit plus Keychain.

## Removed Attack Surface

Boombox removes subsystems outside the kept feature set. See `STRIPPED.md` for the complete list.

## Persistence

- Favorites: `~/Library/Application Support/Boombox/favorites.json`
- Queue state: `UserDefaults` keys under `boombox.saved.*`
- Queue display mode: `boombox.queue.displayMode`
- Auth cookies: macOS Keychain plus WebKit's persistent website data store
- Image cache: `com.melboonchan.boombox.imagecache`

## Verification

Use the local loop:

```bash
swift build
swift test
Scripts/build-app.sh release
```
