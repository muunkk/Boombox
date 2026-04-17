# Private Fork Progress

This file tracks the private YouTube Music macOS fork work so another session can resume safely.

## Current State

- Branch: `feature/player-bar-polish`
- Upstream fork base: `700b72d49e47d55d6f1b2fde6c5a73f70228843c` (`sozercan/kaset`)
- Latest completed checkpoint: player bar polish toggle placement at `a797c1e` on `feature/player-bar-polish`; merge to `personal/main` is still pending
- `swift build`: passes
- `swift test`: passes (894 tests after player bar polish coverage)
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

- [x] Delete orphaned AI/FoundationModels tests so `swift test` can compile again
- [x] Remove distribution leftovers: `Casks/`, `appcast.xml`, Sparkle release scripts, GitHub release workflow, stale Sparkle signing code
- [x] Remove remaining floating-video metadata leftovers: `MusicVideoType`, `Song.hasVideo`, `Song.musicVideoType`, `currentTrackHasVideo`, `MOCK_HAS_VIDEO`, `VideoWindow` IDs
- [x] Strip the custom `kaset://` URL scheme and URL handler because it is outside the kept feature set
- [x] Remap shortcuts: command bar `Cmd+L`, lyrics `Cmd+Y`, and remove the old command-k palette action
- [x] Harden auth: modern Safari UA, direct `https://music.youtube.com/` login, login-only WebView config, device-only Keychain cookies, cookie allowlist, Safari passkey fallback
- [x] Rebrand app bundle and user-facing docs to `YTM Private`
- [x] Add `STRIPPED.md`
- [x] Run final verification: `swift build`, `swift test`, focused greps, and `Scripts/build-app.sh release`
- [x] Fix command palette search submission and add YouTube Music autocomplete suggestions
- [x] Add player UI feature suite: expanded now-playing popover, Focus Player, Small Player, hidden dislike button, dynamic audio output icon, and exponential volume curve
- [x] Add player bar polish branch: persistent sidebar now-playing panel, stable bottom scrubber, and removal of the player-bar popover

## Worktree Branch Log

Parallel feature work for the player UI suite used separate worktrees, then merged through `feature/player-ui-suite` before landing on `personal/main`.

- `feature/player-ui-suite`
  - Commit `b10a7d0`: added shared player-presentation state, environment wiring, `Focus Player` / `Small Player` menu commands, and placeholders for the alternate player surfaces.
  - Commit `d877293`: resolved integration overlap between compact/focus player surfaces, removed duplicate progress controls, and made compact player volume use the shared exponential curve.
  - Merged to `personal/main` as `a26e3b5`.
- `feature/player-expanded-focus`
  - Commit `df6d642`: made the player-bar artwork/title open a medium now-playing popover; added large artwork, progress seek, transport controls, hover actions, and the full-window Focus Player with Escape/return controls.
- `feature/player-controls`
  - Commit `ec3d275`: hid the player-bar dislike button, added `VolumeCurve`, added default audio-output detection/icons for AirPods/AirPlay/headphones/speakers, and updated volume shortcuts/sliders to use the non-linear curve.
- `feature/player-compact-mode`
  - Commit `eb84cb5`: added same-window Small Player mode, compact window resize/restore coordination, lock-screen-style controls, and compact-mode frame tests.

Final verification after merging to `personal/main`:

- `swift build`: passed
- `swift test`: passed, 892 tests in 73 suites
- `Scripts/build-app.sh release`: passed
- `codesign --verify --deep --strict .build/app/YTMPrivate.app`: passed
- Packaged app launched from `.build/app/YTMPrivate.app`

## Player Bar Polish Branch Log

- Branch: `feature/player-bar-polish`
- Base: `personal/main` at `3a8d6d1`
- Implementation commit: `99d569f`
- Visibility follow-up commit: `2aead9d`
- Toggle placement follow-up commit: `a797c1e`
- Summary:
  - Added a persisted `showSidebarNowPlayingPanel` setting.
  - Added a toggle button in the bottom player bar for the sidebar now-playing panel.
  - Added `NowPlayingSidebarPanel` above the sidebar profile area with artwork/title/artist and hover actions for `Focus Player` and `Hide Panel`.
  - Removed the player-bar now-playing popover so title/art no longer conflicts with the hover scrubber.
  - Made the bottom seek slider stay visible while dragging and always show when the sidebar now-playing panel is enabled.
  - Changed the toggle icon to the verified `sidebar.left` SF Symbol so the hidden/off state renders visibly on macOS 26.
  - Moved the toggle into the left transport cluster before Previous and changed it to an up/down chevron toggle.
- Verification:
  - `swift build`: passed
  - `swift test`: passed, 894 tests in 73 suites
  - `Scripts/build-app.sh release`: passed

## Resume Commands

```bash
cd /Users/melboonchan/Master/Projects/YTM/kaset
git status --short --branch
git log --oneline -8
swift build
swift test
```

Continue from the first unchecked item above, then update this file before committing.
