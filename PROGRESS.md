# Private Fork Progress

This file tracks the private YouTube Music macOS fork work so another session can resume safely.

## Current State

- Branch: `personal/main`
- Upstream fork base: `700b72d49e47d55d6f1b2fde6c5a73f70228843c` (`sozercan/kaset`)
- Latest completed commit: `796a598 strip: remove WKWebExtension subsystem`
- `swift build`: passes
- `swift test`: currently fails because AI/FoundationModels test files still reference stripped types
- Target app identity: `YTM Private` / `YTMPrivate` / `com.melboonchan.ytmprivate`

## Completed

- [x] Clone hygiene, upstream remote, `personal/main`, and `FORK_BASE.txt`
- [x] Pre-strip audit in `AUDIT.md`
- [x] FoundationModels / Apple Intelligence runtime strip
- [x] Last.fm scrobbling and Cloudflare worker strip
- [x] Sparkle auto-updater and What's New strip
- [x] AppleScript service strip
- [x] Floating video window strip
- [x] WKWebExtension subsystem strip

## Remaining Work

- [ ] Delete orphaned AI/FoundationModels tests so `swift test` can compile again
- [ ] Remove distribution leftovers: `Casks/`, `appcast.xml`, Sparkle release scripts, GitHub release workflow, stale Sparkle signing code
- [ ] Remove remaining floating-video metadata leftovers: `MusicVideoType`, `Song.hasVideo`, `Song.musicVideoType`, `currentTrackHasVideo`, `MOCK_HAS_VIDEO`, `VideoWindow` IDs
- [ ] Strip the custom `kaset://` URL scheme and URL handler because it is outside the kept feature set
- [ ] Remap shortcuts: command bar `Cmd+L`, lyrics `Cmd+Y`, no `Cmd+K` palette action
- [ ] Harden auth: modern Safari UA, direct `https://music.youtube.com/` login, login-only WebView config, device-only Keychain cookies, cookie allowlist, Safari passkey fallback
- [ ] Rebrand app bundle and user-facing docs to `YTM Private`
- [ ] Add `STRIPPED.md`
- [ ] Run final verification: `swift build`, `swift test`, focused greps, and `Scripts/build-app.sh release`

## Resume Commands

```bash
cd /Users/melboonchan/Master/Projects/YTM/kaset
git status --short --branch
git log --oneline -8
swift build
swift test
```

Continue from the first unchecked item above, then update this file before committing.
