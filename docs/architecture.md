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
- `Sources/Kaset/Services/MenuBarController.swift` owns the optional `NSStatusItem`, its `NSPopover`-hosted compact player, and the popover-scoped scroll-wheel monitor that drives volume.
- `Sources/Kaset/Services/GlobalHotkeyService.swift` registers Carbon `RegisterEventHotKey` shortcuts (one instance per hotkey, ID-filtered) for the menu bar popover and the sidebar toggle.
- `Sources/Kaset/Services/GlobalNavigationCoordinator.swift` brokers cross-tab navigation requests (e.g. clicking the sidebar now-playing card) by funnelling them onto the Library tab's `NavigationPath`.
- `Sources/Kaset/Services/RecentSearchesStore.swift` persists the recent search queries shown when the search field is empty.
- `Sources/Kaset/Views/SharedViews/NavigationSwipeGestures.swift` implements two-finger trackpad back/forward (both `.swipe` events and `NSEvent.trackSwipeEvent`) with a Safari-style chevron indicator.
- `Sources/Kaset/Views/SharedViews/SidePanelSwipeSwitchModifier.swift` recognises horizontal swipes inside the lyrics/queue panel and toggles between the two views.

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
- App settings (`SettingsManager`): `UserDefaults` under `settings.*` — menu bar toggle, menu bar / sidebar global hotkeys (JSON-encoded `HotkeyShortcut`), side panel width, display mode (grid/list), display density (default/compact), recent searches.
- Auth cookies: macOS Keychain plus WebKit's persistent website data store
- Image cache: `com.melboonchan.boombox.imagecache`

## Verification

Use the local loop:

```bash
swift build
swift test
Scripts/build-app.sh release
```
