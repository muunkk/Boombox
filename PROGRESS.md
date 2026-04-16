# Private Fork — Build Progress

Tracks where we are in executing `/Users/melboonchan/.claude/plans/rosy-crafting-moore.md`.
Update on every commit so we can resume after an interruption.

## Current state

**Branch:** `personal/main`
**Upstream fork base:** see `FORK_BASE.txt` (`700b72d` on `sozercan/kaset`)
**Build:** ✅ `swift build` passes

## Checklist

- [x] §2  Clone, set up `upstream` remote, `personal/main` branch, `FORK_BASE.txt`
- [x] §3  Audit — `AUDIT.md` committed (`c9715c9`)
- [x] §4a/c/d AI strip — committed (`d54f7cc`)
- [ ] §4a/c/d Last.fm scrobbling strip — **IN PROGRESS** (files deleted + `KasetApp.swift` edited, uncommitted)
- [ ] §4a/b Sparkle / WhatsNew strip + `Package.swift` dep removal
- [ ] §4a AppleScript strip
- [ ] §4a Floating video window strip
- [ ] §4a WebExtensions strip (added during audit — `ExtensionsSettingsView`, `ExtensionOptionsView`, `ExtensionsManager`, WKWebExtension bits in `WebKitManager`)
- [ ] §4a Distribution strip (`Casks/`, release scripts)
- [ ] §4e Test target cleanup (orphan imports)
- [ ] §5    Rebrand — USER must do in Xcode GUI (bundle ID, team, scheme, Info.plist)
- [ ] §6    Keybinding remap: ⌘K → ⌘L (command bar), ⌘L → ⌘Y (lyrics)
- [ ] §6b F1 Modernize UA + load `https://music.youtube.com/` in login WebView
- [ ] §6b F2 "Sign in via Safari" fallback view for passkey users
- [ ] §6b F3 Tighten cookie Keychain accessibility, host allowlist, Sign Out action
- [ ] §6b F4 Strip native script bridges from login WebView config
- [ ] §9b   `STRIPPED.md` listing every deletion
- [ ] §7    USER: build/sign in Xcode with Personal Team
- [ ] §8    USER: smoke-test checklist

## Notes / findings (from audit)

- Keychain cookie uses `kSecAttrAccessibleWhenUnlocked` (line 143 of `WebKitManager+Cookies.swift`) — fix to `ThisDeviceOnly` in §6b F3.
- WebExtensions subsystem (`WKWebExtensionController`) present in `WebKitManager.swift` lines 37, 50, 82, 173–214, 237–261, 521–527. Added to strip list.
- `GeneralSettingsView.swift:143` has a `github.com/sozercan/kaset` link — update or remove during rebrand.
- Only outbound network hosts (after strips): music.youtube.com, i.ytimg.com, accounts.google.com, lrclib.net.
- `DiagnosticsLogger.scrobbling` still present at `DiagnosticsLogger.swift:43`; remove with the scrobbling commit.
- `DiagnosticsLogger.extensions` at `DiagnosticsLogger.swift:49`; remove with the extensions commit.

## How to resume after interruption

1. `cd /Users/melboonchan/Master/Projects/YTM/kaset`
2. `git status` + `git log --oneline -5` to see last commit
3. `swift build 2>&1 | tail -3` to see current compile state
4. Consult this checklist; continue from the first unchecked box.
5. After completing each step, commit and update this file.
