# Testing

Use CLI verification for this private fork:

```bash
swift build
swift test
```

The unit suite covers parsers, player queue behavior, auth state, cookie allowlisting, WebKit configuration, lyrics parsing, library models, retry policy, and service view models.

For app packaging smoke tests:

```bash
Scripts/build-app.sh release
open .build/app/YTMPrivate.app
```

Manual smoke coverage should include login, Safari fallback import, Premium playback, media keys, Control Center Now Playing, Dock menu actions, Library, Search, Lyrics, Queue reorder/shuffle/clear, Share, `Cmd+L` command palette, and `Cmd+Y` lyrics.
