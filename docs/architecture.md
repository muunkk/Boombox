# Architecture

YTM Private is a SwiftPM-first macOS 26 app. The public app/product identity is `YTM Private` / `YTMPrivate` / `com.melboonchan.ytmprivate`, while the Swift target and module remain `Kaset` to avoid unnecessary source churn.

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

Auth cookies are allowlisted by name and Google/YouTube domain before persistence. The Keychain item uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` under `com.melboonchan.ytmprivate.auth-cookies`.

Google passkeys are handled through Safari. The fallback view opens YouTube Music in Safari and imports pasted allowlisted auth cookies locally into WebKit plus Keychain.

## Removed Attack Surface

The private fork removes subsystems outside the kept feature set. See `STRIPPED.md` for the complete list.

## Persistence

- Favorites: `~/Library/Application Support/YTMPrivate/favorites.json`
- Queue state: `UserDefaults` keys under `ytmprivate.saved.*`
- Queue display mode: `ytmprivate.queue.displayMode`
- Auth cookies: macOS Keychain plus WebKit's persistent website data store
- Image cache: `com.melboonchan.ytmprivate.imagecache`

## Verification

Use the local loop:

```bash
swift build
swift test
Scripts/build-app.sh release
```
