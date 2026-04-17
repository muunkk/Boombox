# YTM Private

A private, source-built macOS YouTube Music client for personal use.

![YTM Private screenshot](docs/screenshot.png)

## Kept Features

- **Native macOS experience** — Apple Music-style SwiftUI interface with Liquid Glass player bar and sidebar navigation.
- **YouTube Music Premium playback** — Playback stays inside the main YouTube Music `WKWebView`, so DRM-protected Premium content uses your existing subscription.
- **System integration** — Now Playing in Control Center, media keys, Dock menu controls, haptics, and optional track notifications.
- **Library access** — Browse playlists, liked songs, artists, albums, and subscribed podcasts from your YouTube Music account.
- **Search** — Find songs, albums, artists, playlists, and podcasts.
- **Lyrics** — Plain YouTube Music lyrics and synced LRCLib lyrics with line-by-line highlighting when timing data is available.
- **Queue management** — View, reorder, shuffle, and clear the playback queue.
- **Share** — Share songs, playlists, albums, and artists through the native macOS share sheet.
- **Command palette** — `Cmd+L` opens the command palette. Lyrics moved to `Cmd+Y`.

## Auth Notes

Google passkeys are not promised inside the embedded login WebView. This private app supports a Safari fallback instead: sign in to YouTube Music in Safari, then import allowlisted YouTube/Google auth cookies locally into the app's WebKit data store and macOS Keychain. Pasted cookie values are not logged, exported, or sent to any service by this app.

## Local Build

```bash
swift build
swift test
Scripts/build-app.sh release
open .build/app/YTMPrivate.app
```

The app bundle is named `YTMPrivate.app`, displays as `YTM Private`, and uses bundle id `com.melboonchan.ytmprivate`. Signing defaults to a local Apple Development certificate when available and falls back to ad-hoc signing.

## Trust Boundary

See [STRIPPED.md](STRIPPED.md) for the deleted upstream subsystems and the remaining network/service boundary.

## Disclaimer

YTM Private is an unofficial personal application and is not affiliated with YouTube or Google. YouTube, YouTube Music, and related marks belong to Google.
