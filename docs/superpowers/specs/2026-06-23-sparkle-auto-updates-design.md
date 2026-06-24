# Design: Sparkle Auto-Updates + One-Command Releases

- **Date:** 2026-06-23
- **Status:** Approved (design); pending implementation plan
- **Author:** Mel Boonchan (with AI assistant)
- **Related:** ADR to be created in `docs/adr/`; `docs/progress.md` entry

## Problem

Boombox is a personal, source-built macOS app. Today there is **no installable "stable" build that can update itself** — the README explicitly states "no auto-updater," and the upstream Sparkle integration was removed during the fork's slim-down. The maintainer (a solo dev who is also the only user) wants to:

1. Keep a **stable installed copy** running as a daily driver, while
2. **Continuing development** in the repo without disturbing that copy, then
3. **Cut a release with one command**, and
4. **Pull the update from inside the stable app** via a "Check for Updates" affordance.

The building blocks for half of this already exist: `Scripts/build-app.sh` produces a signed `Boombox.app` bundle. The missing half is the entire update mechanism and a release-publishing pipeline.

## Goals

- In-app **Check for Updates…** menu item plus **automatic background update checks**.
- A **single command** (`Scripts/release.sh <version>`) that builds, signs, notarizes, packages, publishes to GitHub Releases, and updates the update feed.
- **Seamless, warning-free updates** (Developer ID signing + notarization).
- Update feed hosted for free on the existing GitHub repo.

## Non-Goals

- Mac App Store distribution (would require keeping the sandbox; explicitly out of scope).
- Delta/partial updates (Sparkle supports them, but full-DMG updates are simpler and fine for a personal app).
- Multi-user / fleet update management.
- Cross-platform packaging.

## Decisions (settled during brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Update framework | **Sparkle 2** (SPM) | De-facto standard for non–App Store macOS apps (IINA, Transmission, Rectangle, etc.); was used upstream before the strip-down. |
| Distribution / feed host | **GitHub Releases** + `appcast.xml` served via `raw.githubusercontent.com` | Free, versioned, no extra infra; repo already at `github.com/muunkk/Boombox`. |
| App Sandbox | **Drop it** (remove `com.apple.security.app-sandbox`) | Verified that self-distributed Sparkle apps are normally unsandboxed (IINA confirmed unsandboxed at the entitlements level). Unsandboxed = Sparkle is drop-in (no XPC services / mach-lookup exceptions). Only the Mac App Store *requires* the sandbox. |
| Code signing | **Developer ID + notarization** (maintainer has a paid Apple Developer account) | Updates install silently with no Gatekeeper warnings. |
| Release artifact | **DMG** (universal arm64 + x86_64) | Nicer first-install UX than a zip; Sparkle updates from a DMG fine; universal runs on any Mac. |
| Update cadence | **Automatic daily checks + manual menu item** | Standard Sparkle behavior; Sparkle prompts for permission to auto-check on first launch. |

### Security note on dropping the sandbox

Dropping the sandbox does **not** affect notarization or Gatekeeper (those require Hardened Runtime + notarization, both retained). It does **not** remove Keychain isolation or TCC consent prompts. The one real change: at-rest app data (notably the WebView's auth cookies) moves from `~/Library/Containers/<bundle-id>` to `~/Library/Application Support`, readable by any process running as the same user. **Mitigation (tracked separately, not blocking this work):** encrypt sensitive stored auth state with a key held in the macOS Keychain, the way browsers do, rather than relying on container isolation as the confidentiality boundary. This is recorded in the ADR as a follow-up.

## Architecture

Two cooperating halves: the **app-side updater** (ships in the app) and the **release pipeline** (developer tooling). They meet at two contracts: the **appcast feed URL** and the **EdDSA public key**.

```
   ┌─────────────────────────────┐         ┌──────────────────────────────┐
   │  Installed Boombox.app       │         │  Developer machine            │
   │  (stable daily driver)       │         │  Scripts/release.sh <ver>     │
   │                              │         │                              │
   │  SPUStandardUpdaterController│         │  build → embed+sign Sparkle  │
   │     │ reads SUFeedURL        │         │  → notarize → DMG → notarize │
   │     │ verifies SUPublicEDKey │         │  → EdDSA sign → appcast.xml  │
   │     ▼                        │         │  → gh release create         │
   │  "Check for Updates…" menu   │         └───────────────┬──────────────┘
   └──────────────┬───────────────┘                         │
                  │  HTTPS GET                               │ publishes
                  ▼                                          ▼
        raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml
                  │  <enclosure url=…> points to ──►  GitHub Releases DMG
```

### Component 1 — Updater holder

- **What it does:** Owns a single `SPUStandardUpdaterController` and exposes whether a check can currently run, plus a `checkForUpdates()` action.
- **How it's used:** Instantiated once in `AppDelegate` (the app already uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`). The SwiftUI menu reads it.
- **Depends on:** Sparkle. `@MainActor` per project rules for observable state.
- **Boundary:** Nothing else in the app needs to know Sparkle exists; this is the only Sparkle-aware type besides the menu view.

### Component 2 — Check-for-Updates menu item

- **What it does:** A small SwiftUI view (`CheckForUpdatesView`) with a `Button("Check for Updates…")` that is disabled while `updater.canCheckForUpdates` is false and calls `updater.checkForUpdates()` otherwise.
- **How it's used:** Added in `KasetApp.swift` via `CommandGroup(after: .appInfo)`, placing it directly under "About Boombox" in the app menu — the conventional macOS location.
- **Depends on:** Component 1.

### Component 3 — Settings toggle (optional, low-risk)

- **What it does:** An "Automatically check for updates" toggle in the **General** settings tab, bound to Sparkle's `automaticallyChecksForUpdates`.
- **Boundary:** Purely a convenience mirror of Sparkle state; can be deferred if it complicates the first cut.

### Component 4 — Bundle/Info.plist configuration

`Scripts/build-app.sh` generates `Info.plist` inline. Add these keys:

| Key | Value |
|-----|-------|
| `SUFeedURL` | `https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key (base64) generated once via Sparkle's `generate_keys` |
| `SUEnableAutomaticChecks` | `true` |
| `SUScheduledCheckInterval` | `86400` (daily) |

No `SUEnableInstallerLauncherService` / mach-lookup exceptions — those are sandbox-only and we are unsandboxed.

### Component 5 — Entitlements change

Remove from `Kaset.entitlements`:
- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write` (inert without sandbox)
- `com.apple.security.files.bookmarks.app-scope` (inert without sandbox)

Retain: `com.apple.security.cs.jit` (WebView/DRM), `com.apple.security.network.client`.
**Verification gate:** confirm nothing in the app actually depends on sandbox-only behavior (security-scoped bookmarks, container paths) before removing — search the codebase for `startAccessingSecurityScopedResource`, `bookmarkData`, and container-path assumptions. Resolve any findings as part of implementation.

### Component 6 — Sparkle dependency & embedding

- Add to `Package.swift`: `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")`, and the `Sparkle` product to the `Kaset` target.
- Sparkle ships as a **binary XCFramework** via SPM. Because the app is built with `swift build` (not an Xcode project), the framework is **not auto-embedded**; the build/release script must:
  1. Locate the resolved `Sparkle.framework` in SPM's artifacts (e.g. `.build/artifacts/.../Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`).
  2. Copy it into `Boombox.app/Contents/Frameworks/`.
  3. Code-sign **inside-out** with Developer ID + Hardened Runtime: nested `Updater.app`, `Autoupdate`, and any `XPCServices/*.xpc` first, then `Sparkle.framework`, then the app bundle last.
- **This is the highest-risk implementation detail** (exact artifact path + signing order). The implementation plan must pin the exact commands and verify with `codesign --verify --deep --strict` and `spctl -a -vvv`.

### Component 7 — Release pipeline `Scripts/release.sh <version>`

Single command, end to end:

1. **Bump version** — set `MARKETING_VERSION=<version>` and monotonically increment `BUILD_NUMBER` in `version.env`. (Sparkle compares `CFBundleVersion` = build number for "is newer".)
2. **Build** universal `.app` via `build-app.sh` in Developer ID (`release`) signing mode (`ARCHES="arm64 x86_64"`).
3. **Embed + sign Sparkle** (Component 6).
4. **Notarize the app** — `xcrun notarytool submit --wait` (credentials via a notarytool keychain profile or App Store Connect API key), then `xcrun stapler staple`.
5. **Package DMG** — `Boombox-<version>.dmg` via `hdiutil`; notarize + staple the DMG too.
6. **EdDSA-sign** the DMG — Sparkle's `sign_update` (private key from login Keychain) → signature + length for the appcast.
7. **Update `appcast.xml`** — append a new `<item>` (version, short version, enclosure URL pointing at the GitHub release asset, `sparkle:edSignature`, `length`, and release notes).
8. **Publish** — `gh release create v<version>` with the DMG attached; commit updated `appcast.xml` + `version.env`.

> **Git/publish boundary:** Per maintainer policy, the assistant writes `release.sh` but does **not** run git/`gh`/release-publishing steps. The maintainer runs `release.sh`. The assistant only runs local build/test verification.

### Secrets handling

- **EdDSA private key:** generated once via Sparkle `generate_keys`; stored in the login Keychain; **never** committed. Only the public key is embedded (in Info.plist).
- **Notarization credentials:** a `notarytool` keychain profile (or App Store Connect API key) referenced by name in `release.sh`; **never** hard-coded.
- No real cookies/tokens/keys ever appear in code, scripts, fixtures, logs, or docs (project critical rule).

## Versioning

- `release.sh 1.1.0` → marketing version `1.1.0`, build number auto-incremented.
- Sparkle uses build number for newness comparison and shows marketing version to the user.

## Distribution & feed

- DMGs attached to GitHub Releases on `muunkk/Boombox`.
- `appcast.xml` committed at the **repo root** (matching the `SUFeedURL` path `/main/appcast.xml`), served at `https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml` (the `SUFeedURL`).

## Error handling & edge cases

- **No network / feed unreachable:** Sparkle surfaces its standard "couldn't check for updates" UI; no app crash. No custom handling needed.
- **Signature mismatch (EdDSA or code signature):** Sparkle refuses the update — the security property we want. Verified during staging test.
- **Notarization failure in `release.sh`:** script must abort with a clear message and a non-zero exit before publishing anything; never publish an unnotarized/unsigned artifact.
- **Partial release:** `release.sh` should be ordered so that irreversible/public steps (gh release, appcast commit) come **last**, after all signing/notarization succeeds, to avoid a half-published release.
- **Downgrade/equal version:** Sparkle won't offer an update whose build number isn't greater; `release.sh` enforces monotonic build numbers.

## Testing & verification

- **Build/lint/test stay green:** `swift build`; `swift test --skip KasetUITests`; `swiftlint --strict && swiftformat .`.
- **Unit tests:** cover the updater holder's observable wiring (`canCheckForUpdates`) where testable without launching the updater UI.
- **End-to-end staging test (the important one):** build & install `vX.Y.Z`, cut a fake `vX.Y.(Z+1)` against a **local/file appcast**, confirm the installed app detects it, downloads, verifies signatures, swaps in place, and relaunches updated. Validates the full loop before trusting it against the live feed.
- **Signing verification:** `codesign --verify --deep --strict --verbose=2` and `spctl -a -vvv -t install` on both the `.app` and the `.dmg`.

## Documentation deliverables

- **ADR** in `docs/adr/`: "Adopt Sparkle for auto-updates and drop the App Sandbox," including the Keychain-encryption follow-up for at-rest cookies.
- **README.md:** reverse the "no auto-updater" / "Sparkle removed" statements; add install + update instructions.
- **Release runbook:** prerequisites (Developer ID cert, notarytool profile, EdDSA key in Keychain) and the one-command flow.
- **`docs/progress.md`:** log the effort and phases per project convention.
- **`docs/keyboard-shortcuts.md`:** only if a shortcut is added (none planned for Check for Updates by default).

## Open implementation risks (to resolve in the plan)

1. **Exact Sparkle SPM artifact path + inside-out signing order** for a `swift build` (non-Xcode) bundle — the single biggest risk; must be verified empirically.
2. **notarytool credential mechanism** (keychain profile vs API key) — pick and document.
3. Confirm **no sandbox-only dependencies** exist before removing the entitlement.
```
