# Stripped Fork Notes

Boombox keeps the native YouTube Music macOS client surface from upstream [Kaset](https://github.com/sozercan/kaset) and removes subsystems that are unnecessary for a personal source-build distribution model.

## Deleted Subsystems

- Apple Intelligence / FoundationModels features, tests, model types, tools, and settings.
- Last.fm scrobbling, Cloudflare worker code, scrobble settings, and diagnostics categories.
- Sparkle auto-updater, What's New UI, appcast, release workflow, Homebrew cask, and update signing scripts.
- AppleScript scripting support and scripting test fixtures.
- Floating video window mode and video metadata plumbing.
- WKWebExtension loading, extension settings, and extension option UI.
- Custom `kaset://` URL scheme and URL handler.
- API explorer CLI and legacy debug cookie export path.

## Kept Feature Boundary

- Native SwiftUI macOS interface, player bar, sidebar navigation, command palette, queue, share sheet, lyrics, search, library, podcasts, and system media integration.
- YouTube Music playback remains in the main `WKWebView` so Premium DRM playback is handled by Google's web player.
- Auth cookies are persisted only through the app's `WKWebsiteDataStore` and macOS Keychain service `com.melboonchan.boombox.auth-cookies`.
- The login WebView uses a login-only configuration with no native script message handlers.
- Passkeys are supported through Safari sign-in plus local allowlisted cookie import, not through embedded-WebView passkey promises.

## Remaining External Trust

- **Google / YouTube Music**: account sign-in, playback, DRM, library data, search, podcasts, and YouTube Music API responses.
- **Apple frameworks**: WebKit, SwiftUI, AppKit, MediaPlayer, Security/Keychain, UserNotifications, and system media controls.
- **LRCLib**: optional synced lyrics lookup when synced lyrics are enabled.

No updater, binary distribution channel, extension runtime, scrobbling service, AI service, AppleScript bridge, or custom URL scheme remains in Boombox.
