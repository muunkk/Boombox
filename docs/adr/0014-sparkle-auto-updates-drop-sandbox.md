# ADR-0014: Adopt Sparkle for Auto-Updates and Drop the App Sandbox

## Status

Accepted

## Context

Boombox is a personal, source-built macOS app distributed outside the Mac App Store. Prior to this decision the app had no installable "stable build that can update itself" — the upstream Sparkle integration (from [sozercan/kaset](https://github.com/sozercan/kaset)) was removed during the initial fork slim-down, and the README explicitly stated "no auto-updater."

The maintainer (a solo developer who is also the only user) wanted:

1. A **stable installed copy** running as a daily driver, while
2. **Continuing development** in the repo without disturbing that copy, then
3. **Cutting a release with one command**, and
4. **Pulling the update from inside the stable app** via a "Check for Updates" affordance.

The building blocks for half of this already existed: `Scripts/build-app.sh` produces a signed `Boombox.app` bundle. The missing half was the update mechanism and a release-publishing pipeline.

See the approved design at [`docs/superpowers/specs/2026-06-23-sparkle-auto-updates-design.md`](../superpowers/specs/2026-06-23-sparkle-auto-updates-design.md).

## Decision

### Update framework: Sparkle 2 via Swift Package Manager

Adopt **Sparkle 2** (binary XCFramework via SPM) as the auto-update framework. Sparkle is the de-facto standard for non–App Store macOS apps (IINA, Transmission, Rectangle, etc.) and was used in the upstream Kaset codebase. SPM integration keeps the dependency management in `Package.swift` without requiring an Xcode project.

### Drop the App Sandbox

Remove `com.apple.security.app-sandbox` (and the now-inert `files.user-selected.read-write` and `files.bookmarks.app-scope` entitlements) from `Kaset.entitlements`.

Only two entitlements are retained: `com.apple.security.cs.jit` (required for WebView/DRM) and `com.apple.security.network.client`.

**Rationale:** Self-distributed Sparkle apps are normally unsandboxed — verified against comparable apps (IINA confirmed unsandboxed at the entitlements level). The Mac App Store *requires* the sandbox; self-distribution does not. Dropping the sandbox makes Sparkle a clean drop-in with no XPC launcher services or mach-lookup exceptions needed. The codebase was audited for sandbox-only dependencies (`startAccessingSecurityScopedResource`, `bookmarkData`, container-path assumptions) before removing the entitlement — no blockers were found.

### Code signing: Developer ID + notarization

Sign the release build with a **Developer ID Application** certificate and notarize with Apple's notarization service (`xcrun notarytool`). This ensures Gatekeeper accepts the app without warnings and allows Sparkle to install updates silently.

Notarization requires Hardened Runtime (retained). Dropping the sandbox does not affect notarization or Gatekeeper.

### Distribution: GitHub Releases + appcast on `raw.githubusercontent.com`

- Release artifacts (universal arm64 + x86_64 DMGs) are attached to **GitHub Releases** on `muunkk/Boombox`.
- `appcast.xml` is committed at the **repo root** on the `main` branch and served at:
  `https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml`
  (the `SUFeedURL` baked into `Info.plist`).

This is free, versioned, and requires no additional infrastructure.

### Update cadence: automatic daily checks + manual menu item

- Sparkle performs automatic background checks every **86 400 seconds (daily)**, controlled by `SUEnableAutomaticChecks` and `SUScheduledCheckInterval` in `Info.plist`.
- A **"Check for Updates…"** menu item under the Boombox menu (placed after "About Boombox" via `CommandGroup(after: .appInfo)`) allows manual triggering.
- Sparkle prompts the user for permission to auto-check on first launch.

### Release pipeline: `Scripts/release.sh <version>`

A single command handles: version bump in `version.env`, universal build via `build-app.sh` (which embeds and inside-out signs `Sparkle.framework`), DMG creation, notarization + stapling, and `generate_appcast` to produce the signed `appcast.xml`. The maintainer then runs the printed manual publish steps (`gh release create` + `git push`).

### EdDSA key management

- The EdDSA key pair is generated once via Sparkle's `generate_keys` tool.
- The **private key** lives only in the macOS login Keychain; it is never committed.
- The **public key** (non-secret, base64) is stored in `version.env` as `SU_PUBLIC_ED_KEY` and embedded in `Info.plist` as `SUPublicEDKey`.

## Consequences

### Positive

- **Seamless self-updating:** users (the maintainer) can receive updates via a standard macOS "Check for Updates" dialog with no Gatekeeper friction.
- **One-command release:** `Scripts/release.sh <version>` handles the entire build-sign-notarize-package-appcast pipeline.
- **No extra infrastructure:** the feed is served free from GitHub's raw CDN.
- **Clean Sparkle integration:** the unsandboxed path requires no XPC helper services or mach-lookup entitlements, keeping the entitlements file minimal.
- **Restored upstream feature:** Sparkle was originally present in the upstream Kaset fork; this restores it in a maintained, tested form.

### Negative / Trade-offs

- **One new dependency:** Sparkle 2 is a substantial binary XCFramework (~10 MB); it must be embedded and inside-out signed in every release build. The `build-app.sh` script handles this.
- **Developer ID build required for releases:** ad-hoc or Apple Development signing cannot be used with notarization; a paid Apple Developer account is required. Local dev/CI builds continue to use ad-hoc signing and are unaffected.
- **No Mac App Store distribution:** the App Store requires the sandbox; by dropping it this distribution channel is explicitly closed (non-goal per the design).
- **Local data reset on first switch (one-time):** dropping the sandbox moves app data from the sandboxed container (`~/Library/Containers/com.melboonchan.boombox/Data/Library/Application Support/`) to the standard unsandboxed location (`~/Library/Application Support/`). On the first launch of an unsandboxed build, data stored by classes such as `FavoritesManager` (favorites, settings, login state) will not be found at the new path, causing a one-time reset. A migration step that copies data from the container path to the new location could be added later if desired; it is not implemented in this initial release.

## Follow-ups (not blocking)

1. **Keychain-encrypt stored WebView auth cookies.** Dropping the sandbox means the WebView's auth cookies move from `~/Library/Containers/com.melboonchan.boombox` (readable only by the app when sandboxed) to `~/Library/Application Support` (readable by any process running as the same user). Notarization and Gatekeeper are unaffected, but at-rest cookie isolation is weaker. Mitigation: encrypt sensitive stored auth state with a key held in the macOS Keychain — the approach browsers use — rather than relying on container isolation as the confidentiality boundary. This is tracked separately and is not blocking the initial Sparkle release.

2. **Local-data migration.** If the maintainer's existing installed copy has favorites, queue, or login state in the sandboxed container path, those will be invisible to the first unsandboxed release. A one-time migration helper that copies `~/Library/Containers/com.melboonchan.boombox/Data/Library/Application Support/` → `~/Library/Application Support/` could be shipped in a future release. Tracked for later consideration.
