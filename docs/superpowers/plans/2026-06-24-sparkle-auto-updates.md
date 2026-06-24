# Sparkle Auto-Updates + One-Command Releases — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an installable Boombox.app that updates itself via an in-app "Check for Updates…" menu item, plus a single `Scripts/release.sh <version>` command that builds, signs, notarizes, packages a DMG, and publishes to GitHub Releases.

**Architecture:** Two cooperating halves. (1) *App side* — embed Sparkle 2 (SPM), hold an `SPUStandardUpdaterController` in the SwiftUI `App`, expose a Check-for-Updates command, and drop the App Sandbox so Sparkle is a clean drop-in. (2) *Release pipeline* — extend `build-app.sh` to embed + inside-out-sign `Sparkle.framework`, and add `release.sh` to notarize, build a DMG, run `generate_appcast`, and publish. The two halves meet at the appcast feed URL and the EdDSA public key.

**Tech Stack:** Swift 6 / SwiftUI / macOS 26+, Sparkle 2.9.3 (SPM binary XCFramework), `codesign` (Developer ID + Hardened Runtime), `notarytool`, `hdiutil`, `gh`, GitHub Releases.

## Global Constraints

- **Swift 6.0+**, **macOS 26.0+** target; existing `.swiftLanguageMode(.v6)` + `enableExperimentalFeature("StrictConcurrency")`.
- Mark `@Observable`/observable classes `@MainActor`.
- **No `print()`** — use `DiagnosticsLogger`. **No `DispatchQueue`** — Swift concurrency only. **No force unwraps** — `guard`/optional handling.
- SwiftFormat uses `--self insert`: in instance methods use `self.property`; in static methods call `Self.method()`. Run `swiftformat .` before completing each task.
- Lint/format gate per task: `swiftlint --strict && swiftformat .`. Build gate: `swift build`. Unit-test gate: `swift test --skip KasetUITests`.
- **No new third-party frameworks beyond Sparkle** (approved).
- **Sparkle version: 2.9.3** (`from: "2.9.3"`). Re-check `https://api.github.com/repos/sparkle-project/Sparkle/releases/latest` at implementation start; bump the floor if a newer 2.x patch shipped.
- **Bundle ID:** `com.melboonchan.boombox`. **Module name:** `Kaset`. **App name:** `Boombox`.
- **GitHub remote:** `https://github.com/muunkk/Boombox`. **Appcast feed URL (`SUFeedURL`):** `https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml`. **Release asset URL pattern:** `https://github.com/muunkk/Boombox/releases/download/<version>/<file>`.
- **NEVER leak secrets:** the EdDSA *private* key lives only in the login Keychain; notarization creds live only in a `notarytool` keychain profile. Only the EdDSA *public* key (non-secret) is embedded in Info.plist / committed. No cookies/tokens/keys in code, scripts, fixtures, logs, or docs — use placeholders.
- **Git boundary (maintainer policy):** the implementer/assistant writes scripts and code but does **NOT** run `git`/`gh`/publishing commands. Every "Commit" / `gh release` step is run by the maintainer (or only after explicit per-action approval). Treat commit steps as checkpoints for the maintainer.

---

## File Structure

**Create:**
- `Sources/Kaset/Updates/UpdaterController.swift` — owns `SPUStandardUpdaterController`; exposes `updater`, a `canCheckPublisher`, and `checkForUpdates()`. The only Sparkle-aware type besides the menu view.
- `Sources/Kaset/Updates/CheckForUpdatesViewModel.swift` — `@MainActor ObservableObject` publishing `canCheckForUpdates` from an injected `AnyPublisher<Bool, Never>` (testable seam — no live updater needed).
- `Sources/Kaset/Updates/CheckForUpdatesView.swift` — the "Check for Updates…" `Button`, disabled until `canCheckForUpdates`.
- `Tests/KasetTests/CheckForUpdatesViewModelTests.swift` — unit test for the view model's publisher wiring.
- `Scripts/release.sh` — one-command release pipeline.
- `docs/adr/0001-sparkle-auto-updates-drop-sandbox.md` — ADR (number per existing `docs/adr/` convention).
- `docs/release-runbook.md` — prerequisites + how to cut a release.
- `appcast.xml` — generated; committed at repo root (matches `SUFeedURL`).

**Modify:**
- `Package.swift` — add Sparkle dependency + product.
- `Kaset.entitlements` — remove sandbox + now-inert file/bookmark keys.
- `version.env` — add `SU_FEED_URL`, `SU_PUBLIC_ED_KEY`; `release.sh` bumps `MARKETING_VERSION`/`BUILD_NUMBER`.
- `Scripts/build-app.sh` — inject Sparkle Info.plist keys; embed + inside-out-sign `Sparkle.framework`.
- `Sources/Kaset/KasetApp.swift` — hold the updater controller + view model; add `CommandGroup(after: .appInfo)`.
- `.gitignore` — ignore the local `releases/` staging folder (and `*.p8`, `*.pem`).
- `README.md` — reverse "no auto-updater"; add install/update instructions.
- `docs/progress.md`, `docs/user-stories.csv` — log the effort.

---

## Task 1: Add Sparkle dependency

**Files:**
- Modify: `Package.swift`

**Interfaces:**
- Produces: the `Sparkle` module (import target) and the resolved Sparkle CLI tools under `.build/artifacts/.../Sparkle/bin/` (used by Tasks 5–8).

- [ ] **Step 1: Re-check the current Sparkle version**

Run: `curl -s https://api.github.com/repos/sparkle-project/Sparkle/releases/latest | grep '"tag_name"'`
Expected: a tag like `"tag_name": "2.9.3"` (or newer 2.x). Use that version below if it changed.

- [ ] **Step 2: Add the package dependency**

In `Package.swift`, change `dependencies: []` (the package-level array) to:

```swift
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
```

- [ ] **Step 3: Add the product to the Kaset target**

In the `.executableTarget(name: "Kaset", …)`, change `dependencies: []` to:

```swift
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
```

- [ ] **Step 4: Resolve and build**

Run: `swift package resolve && swift build`
Expected: resolves `sparkle-project/Sparkle 2.9.3`, build succeeds.

- [ ] **Step 5: Confirm the CLI tools resolved**

Run: `find "$(pwd)/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' -print -exec ls -1 {} \;`
Expected: a path ending in `artifacts/sparkle/Sparkle/bin` listing `generate_keys`, `sign_update`, `generate_appcast`.

- [ ] **Step 6: Lint/format**

Run: `swiftlint --strict && swiftformat .`
Expected: no errors.

- [ ] **Step 7: Commit** (maintainer)

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle 2.9.3 dependency"
```

---

## Task 2: Drop the App Sandbox (with a dependency-safety gate)

**Files:**
- Modify: `Kaset.entitlements`

**Interfaces:**
- Produces: an unsandboxed entitlements file — precondition for Sparkle's drop-in (no XPC services) integration.

- [ ] **Step 1: Verify nothing depends on sandbox-only behavior**

Run: `grep -rni "startAccessingSecurityScopedResource\|bookmarkData\|securityScope\|/Library/Containers\|NSHomeDirectory" Sources/ Tests/`
Expected: review every hit. Security-scoped bookmarks and container-path assumptions are the only blockers. If a hit relies on the sandbox container path or security-scoped bookmarks for correctness, STOP and resolve it (most likely none exist; user-selected file access works unsandboxed). Record findings in the commit message.

- [ ] **Step 2: Remove the sandbox + now-inert keys**

Edit `Kaset.entitlements` to remove these three keys (and their values): `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`. The file becomes:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.jit</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Build still green**

Run: `swift build`
Expected: success (entitlements don't affect `swift build`; this is a sanity check).

- [ ] **Step 4: Commit** (maintainer)

```bash
git add Kaset.entitlements
git commit -m "build: drop App Sandbox for self-distributed Sparkle updates"
```

---

## Task 3: CheckForUpdatesViewModel (TDD)

**Files:**
- Create: `Sources/Kaset/Updates/CheckForUpdatesViewModel.swift`
- Test: `Tests/KasetTests/CheckForUpdatesViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CheckForUpdatesViewModel: ObservableObject` with `@Published private(set) var canCheckForUpdates: Bool` and `init(initialValue: Bool = false, canCheckPublisher: AnyPublisher<Bool, Never>)`. Consumed by Task 4's view and `UpdaterController`.

- [ ] **Step 1: Write the failing test**

Create `Tests/KasetTests/CheckForUpdatesViewModelTests.swift`:

```swift
import Combine
import Testing
@testable import Kaset

@MainActor
struct CheckForUpdatesViewModelTests {
    @Test
    func tracksPublisherValues() {
        let subject = CurrentValueSubject<Bool, Never>(false)
        let viewModel = CheckForUpdatesViewModel(canCheckPublisher: subject.eraseToAnyPublisher())

        #expect(viewModel.canCheckForUpdates == false)

        subject.send(true)
        #expect(viewModel.canCheckForUpdates == true)

        subject.send(false)
        #expect(viewModel.canCheckForUpdates == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --skip KasetUITests --filter CheckForUpdatesViewModelTests`
Expected: FAIL — `CheckForUpdatesViewModel` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Kaset/Updates/CheckForUpdatesViewModel.swift`:

```swift
import Combine
import SwiftUI

/// Publishes whether the user may currently trigger an update check.
/// Decoupled from Sparkle via an injected publisher so it is unit-testable
/// without a live updater.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool

    private var cancellable: AnyCancellable?

    init(initialValue: Bool = false, canCheckPublisher: AnyPublisher<Bool, Never>) {
        self.canCheckForUpdates = initialValue
        self.cancellable = canCheckPublisher.sink { [weak self] value in
            self?.canCheckForUpdates = value
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --skip KasetUITests --filter CheckForUpdatesViewModelTests`
Expected: PASS.

- [ ] **Step 5: Lint/format**

Run: `swiftlint --strict && swiftformat .`
Expected: no errors (note `self.` usage already explicit).

- [ ] **Step 6: Commit** (maintainer)

```bash
git add Sources/Kaset/Updates/CheckForUpdatesViewModel.swift Tests/KasetTests/CheckForUpdatesViewModelTests.swift
git commit -m "feat(updates): add testable CheckForUpdatesViewModel"
```

---

## Task 4: UpdaterController + view + menu wiring

**Files:**
- Create: `Sources/Kaset/Updates/UpdaterController.swift`
- Create: `Sources/Kaset/Updates/CheckForUpdatesView.swift`
- Modify: `Sources/Kaset/KasetApp.swift`

**Interfaces:**
- Consumes: `CheckForUpdatesViewModel` (Task 3).
- Produces: `@MainActor final class UpdaterController` with `var updater: SPUUpdater`, `var canCheckPublisher: AnyPublisher<Bool, Never>`, `func checkForUpdates()`; and `struct CheckForUpdatesView: View` with `init(viewModel:onCheck:)`.

- [ ] **Step 1: Create the updater controller**

Create `Sources/Kaset/Updates/UpdaterController.swift`:

```swift
import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the lifetime of the app.
/// This is the only type that talks to Sparkle directly (besides the menu view).
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → Sparkle checks on its own schedule using the
        // SUFeedURL / SUPublicEDKey baked into the app's Info.plist.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { self.controller.updater }

    /// Emits whether a manual check is currently allowed.
    var canCheckPublisher: AnyPublisher<Bool, Never> {
        self.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    func checkForUpdates() {
        self.updater.checkForUpdates()
    }
}
```

- [ ] **Step 2: Create the menu view**

Create `Sources/Kaset/Updates/CheckForUpdatesView.swift`:

```swift
import SwiftUI

/// "Check for Updates…" menu item, enabled only when a check is allowed.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let onCheck: () -> Void

    init(viewModel: CheckForUpdatesViewModel, onCheck: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCheck = onCheck
    }

    var body: some View {
        Button("Check for Updates…", action: self.onCheck)
            .disabled(!self.viewModel.canCheckForUpdates)
    }
}
```

- [ ] **Step 3: Hold the controller + view model in `KasetApp`**

In `Sources/Kaset/KasetApp.swift`, add two stored properties to the `KasetApp` struct (near the other `@State` lines, but these are plain `let`s):

```swift
    private let updaterController: UpdaterController
    private let checkForUpdatesViewModel: CheckForUpdatesViewModel
```

Then at the **top of `init()`** (before the existing `Bundle.enableAppLocalizationOverride()` line), construct them:

```swift
        let updaterController = UpdaterController()
        self.updaterController = updaterController
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(
            canCheckPublisher: updaterController.canCheckPublisher
        )
```

- [ ] **Step 4: Add the menu command**

In `KasetApp.swift`, inside the `.commands { … }` block, add as the first entry (before the `CommandMenu("Playback")`):

```swift
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(
                    viewModel: self.checkForUpdatesViewModel,
                    onCheck: { self.updaterController.checkForUpdates() }
                )
            }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: success. (Note: running via bare `swift run` will log a Sparkle warning about a missing feed because there's no app-bundle Info.plist — expected; the real feed lives in the `build-app.sh` bundle. Do not "fix" this.)

- [ ] **Step 6: Unit tests still pass**

Run: `swift test --skip KasetUITests`
Expected: PASS (including Task 3's test).

- [ ] **Step 7: Lint/format**

Run: `swiftlint --strict && swiftformat .`
Expected: no errors.

- [ ] **Step 8: Commit** (maintainer)

```bash
git add Sources/Kaset/Updates/UpdaterController.swift Sources/Kaset/Updates/CheckForUpdatesView.swift Sources/Kaset/KasetApp.swift
git commit -m "feat(updates): wire Sparkle updater into Check for Updates menu"
```

---

## Task 5: EdDSA keys + Sparkle Info.plist keys

**Files:**
- Modify: `version.env`
- Modify: `Scripts/build-app.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the Sparkle `bin/` path from Task 1.
- Produces: `SU_FEED_URL` + `SU_PUBLIC_ED_KEY` in `version.env`; an Info.plist (in the built bundle) containing `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`.

- [ ] **Step 1: Generate the EdDSA key pair** (maintainer; writes to login Keychain)

```bash
SPARKLE_BIN="$(find "$(pwd)/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
"$SPARKLE_BIN/generate_keys"
```
Expected: prints "A key has been generated and saved in your keychain" and a `<string>…=</string>` base64 **public** key. Copy that base64 value for the next step. (Re-running prints the same public key; the private key never leaves the Keychain.)

- [ ] **Step 2: Add feed URL + public key to `version.env`**

Append to `version.env` (replace the placeholder with YOUR public key from Step 1 — it is NOT secret):

```bash
# Sparkle auto-update config
SU_FEED_URL=https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml
SU_PUBLIC_ED_KEY=REPLACE_WITH_BASE64_PUBLIC_KEY_FROM_generate_keys
```

- [ ] **Step 3: Inject the keys into the generated Info.plist**

In `Scripts/build-app.sh`, inside the `cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST` heredoc, add these keys right before the `<!-- Build Metadata -->` comment:

```xml
    <!-- Sparkle Auto-Update -->
    <key>SUFeedURL</key>
    <string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
```

(`version.env` is already `source`d at the top of `build-app.sh`, so `${SU_FEED_URL}` and `${SU_PUBLIC_ED_KEY}` are available.)

- [ ] **Step 4: Guard against an unset key**

In `Scripts/build-app.sh`, immediately after the `source "$ROOT/version.env"` line, add:

```bash
if [[ -z "${SU_PUBLIC_ED_KEY:-}" || "${SU_PUBLIC_ED_KEY}" == REPLACE_* ]]; then
  echo "ERROR: SU_PUBLIC_ED_KEY is not set in version.env (run generate_keys)." >&2
  exit 1
fi
: "${SU_FEED_URL:?SU_FEED_URL must be set in version.env}"
```

- [ ] **Step 5: Ignore secrets/staging in git**

Append to `.gitignore`:

```
# Sparkle / release artifacts
/releases/
*.p8
*.pem
```

- [ ] **Step 6: Verify the keys land in the bundle**

Run: `Scripts/build-app.sh release && /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' .build/app/Boombox.app/Contents/Info.plist`
Expected: prints your base64 public key (not the placeholder). Also confirm: `/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' .build/app/Boombox.app/Contents/Info.plist` prints the appcast URL.

- [ ] **Step 7: Commit** (maintainer — note `version.env` contains only the PUBLIC key)

```bash
git add version.env Scripts/build-app.sh .gitignore
git commit -m "build(updates): embed Sparkle feed URL + public key in Info.plist"
```

---

## Task 6: Embed + inside-out-sign Sparkle.framework

**Files:**
- Modify: `Scripts/build-app.sh`

**Interfaces:**
- Consumes: the resolved `Sparkle.xcframework` (Task 1), the app bundle + `CODESIGN_ARGS` already built in `build-app.sh`.
- Produces: a bundle whose `Contents/Frameworks/Sparkle.framework` is Developer-ID-signed inside-out, passing `codesign --verify` and `spctl`.

> Context: Sparkle's XCFramework ships ad-hoc signed (no Team ID). A `swift build` bundle is NOT auto-signed by Xcode, so we must re-sign every nested Mach-O with our identity, **inside-out**, and **never use `--deep`** for signing.

- [ ] **Step 1: Add the embed-and-sign function**

In `Scripts/build-app.sh`, add this function near the other helper functions (e.g. after `install_binary`):

```bash
# Embed Sparkle.framework and code-sign it inside-out with the SAME identity
# used for the app. Pass the codesign args array (no --entitlements).
embed_and_sign_sparkle() {
  local app_bundle="$1"; shift
  local codesign_args=("$@")

  local xc
  xc=$(find "$ROOT/.build" -type d -name 'Sparkle.xcframework' 2>/dev/null | head -n1)
  if [[ -z "$xc" ]]; then
    echo "ERROR: Sparkle.xcframework not found under .build (run 'swift build' first)" >&2
    exit 1
  fi

  # Pick the macOS slice (prefer a universal one).
  local slice
  slice=$(find "$xc" -maxdepth 1 -type d -name 'macos-*' | head -n1)
  local src_fw="$slice/Sparkle.framework"
  if [[ ! -d "$src_fw" ]]; then
    echo "ERROR: Sparkle.framework not found in slice: $slice" >&2
    exit 1
  fi
  echo "  → Embedding Sparkle from: $src_fw"
  lipo -archs "$src_fw/Versions/Current/Sparkle" 2>/dev/null || true

  local fw_dest="$app_bundle/Contents/Frameworks/Sparkle.framework"
  mkdir -p "$app_bundle/Contents/Frameworks"
  rm -rf "$fw_dest"
  cp -R "$src_fw" "$app_bundle/Contents/Frameworks/"

  # Discover the versioned dir (Sparkle 2.x uses "B"; confirm via the symlink).
  local v
  v=$(readlink "$fw_dest/Versions/Current" 2>/dev/null || echo "B")
  local vroot="$fw_dest/Versions/$v"
  echo "  → Sparkle versioned dir: $vroot"

  # Sign inside-out: deepest nested code first, framework bundle last.
  local nested=(
    "$vroot/XPCServices/Downloader.xpc"
    "$vroot/XPCServices/Installer.xpc"
    "$vroot/Autoupdate"
    "$vroot/Updater.app"
  )
  local item
  for item in "${nested[@]}"; do
    if [[ -e "$item" ]]; then
      echo "    ↳ signing $(basename "$item")"
      codesign "${codesign_args[@]}" "$item"
    fi
  done

  echo "    ↳ signing Sparkle.framework"
  codesign "${codesign_args[@]}" "$fw_dest"
}
```

- [ ] **Step 2: Call it before the final app signing**

In `Scripts/build-app.sh`, the signing section builds `CODESIGN_ARGS` then signs the app. Insert the embed call **after** `CODESIGN_ARGS` is determined but **before** the final `codesign … "$APP_BUNDLE"`:

```bash
# Embed + sign Sparkle BEFORE signing the app (inside-out signing order).
embed_and_sign_sparkle "$APP_BUNDLE" "${CODESIGN_ARGS[@]}"
```

(The existing final `codesign "${CODESIGN_ARGS[@]}" --entitlements … "$APP_BUNDLE"` then seals the whole bundle last. Nested Sparkle code is signed WITHOUT the app entitlements — correct.)

- [ ] **Step 3: Build with Developer ID and inspect the framework layout**

Run: `BOOMBOX_SIGNING=release Scripts/build-app.sh release`
Expected: logs "Embedding Sparkle from…", a `lipo` arch line, "Sparkle versioned dir: …/Versions/B", and "signing" lines for the nested helpers + framework. If the versioned dir prints `A` instead of `B`, that's fine — the script reads it dynamically.

- [ ] **Step 4: Verify code signature integrity**

Run:
```bash
APP=.build/app/Boombox.app
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$APP/Contents/Frameworks/Sparkle.framework" 2>&1 | grep -E 'TeamIdentifier|Authority'
```
Expected: `--verify` prints "valid on disk" / "satisfies its Designated Requirement"; the framework now shows YOUR `TeamIdentifier` and a `Developer ID Application` Authority (NOT ad-hoc). `--deep` is OK for *verifying*; we never used it for *signing*.

- [ ] **Step 5: Commit** (maintainer)

```bash
git add Scripts/build-app.sh
git commit -m "build(updates): embed + inside-out sign Sparkle.framework"
```

---

## Task 7: `release.sh` — version bump, DMG, notarize, staple

**Files:**
- Create: `Scripts/release.sh`
- Modify: `docs/release-runbook.md` (created in Task 10; the notarytool one-time setup is referenced here)

**Interfaces:**
- Consumes: `build-app.sh` (Tasks 5–6), a `notarytool` keychain profile named `boombox-notary`.
- Produces: a notarized, stapled `releases/Boombox-<version>.dmg`.

- [ ] **Step 1: One-time — store notarization credentials** (maintainer)

```bash
# Using an App Store Connect API key (recommended). Stored in the keychain; never committed.
xcrun notarytool store-credentials "boombox-notary" \
  --key /path/to/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```
Expected: "Validating your credentials… Success." (Alternatively `--apple-id … --team-id … --password <app-specific-password>`.)

- [ ] **Step 2: Create `Scripts/release.sh` (version bump + build + DMG + notarize)**

Create `Scripts/release.sh`:

```bash
#!/usr/bin/env bash
# One-command release: bump → build (universal, Developer ID) → DMG → notarize → staple → appcast.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION="${1:?Usage: release.sh <marketing-version>  e.g. release.sh 1.1.0}"
NOTARY_PROFILE="${BOOMBOX_NOTARY_PROFILE:-boombox-notary}"
RELEASES_DIR="$ROOT/releases"
APP="$ROOT/.build/app/Boombox.app"
DMG="$RELEASES_DIR/Boombox-$VERSION.dmg"

source "$ROOT/version.env"

# --- 1. Bump version.env (marketing version + monotonic build number) ---
NEW_BUILD=$(( BUILD_NUMBER + 1 ))
/usr/bin/sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" "$ROOT/version.env"
/usr/bin/sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$NEW_BUILD/" "$ROOT/version.env"
echo "📌 Version $VERSION (build $NEW_BUILD)"

# --- 2. Build universal, Developer ID signed (embeds + signs Sparkle) ---
ARCHES="arm64 x86_64" BOOMBOX_SIGNING=release "$ROOT/Scripts/build-app.sh" release

# --- 3. Stage + build a compressed DMG ---
mkdir -p "$RELEASES_DIR"
STAGE="$ROOT/.build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Boombox" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "💿 Built $DMG"

# --- 4. Notarize + staple the DMG ---
echo "🔏 Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "✅ Notarized + stapled."

echo ""
echo "Next: run Scripts/release.sh's appcast step is automatic below."
```

(The appcast + publish steps are appended in Task 8 — keep this file open.)

- [ ] **Step 3: Make it executable**

Run: `chmod +x Scripts/release.sh`
Expected: no output.

- [ ] **Step 4: Dry-run the build+DMG+notarize path**

Run: `Scripts/release.sh 1.0.1`
Expected: bumps to `1.0.1`/build 2, builds universal, creates `releases/Boombox-1.0.1.dmg`, notarytool returns `status: Accepted`, stapler validates. If notarytool returns `Invalid`, fetch the log: `xcrun notarytool log <id> --keychain-profile boombox-notary`.

- [ ] **Step 5: Commit** (maintainer — `version.env` bump + script)

```bash
git add Scripts/release.sh version.env
git commit -m "build(release): add release.sh (build + DMG + notarize)"
```

---

## Task 8: `release.sh` — appcast generation + publish

**Files:**
- Modify: `Scripts/release.sh`
- Create (generated): `appcast.xml`

**Interfaces:**
- Consumes: the notarized DMG (Task 7), the Sparkle `bin/` tools (Task 1), the EdDSA private key in the Keychain (Task 5).
- Produces: `appcast.xml` at repo root with the new `<item>` (EdDSA signature + length auto-filled); a GitHub Release with the DMG attached.

> `generate_appcast` auto-computes the EdDSA signature and length for every archive in a folder, reading the private key from the Keychain. We keep all release DMGs in `releases/` (gitignored) so the appcast lists every version; we set the new item's download URL via `--download-url-prefix`.

- [ ] **Step 1: Append the appcast step to `Scripts/release.sh`**

Replace the final two `echo` lines of `release.sh` with:

```bash
# --- 5. Generate/refresh the appcast (auto-signs via Keychain private key) ---
SPARKLE_BIN="$(find "$ROOT/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "ERROR: Sparkle bin not found; run 'swift build' first." >&2
  exit 1
fi
DL_PREFIX="https://github.com/muunkk/Boombox/releases/download/$VERSION/"
"$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR" --download-url-prefix "$DL_PREFIX"

# generate_appcast writes appcast.xml into RELEASES_DIR; publish a copy at repo root
# (this is the SUFeedURL path on the main branch).
cp "$RELEASES_DIR/appcast.xml" "$ROOT/appcast.xml"
echo "📰 appcast.xml updated. New enclosure URL prefix: $DL_PREFIX"

# --- 6. Verify the new item points at the right URL ---
if ! grep -q "Boombox-$VERSION.dmg" "$ROOT/appcast.xml"; then
  echo "ERROR: appcast.xml is missing the $VERSION enclosure — check download-url-prefix." >&2
  exit 1
fi

cat <<EOF

✅ Release $VERSION prepared.

The assistant does NOT publish. To finish, YOU run:

  gh release create "$VERSION" "$DMG" \\
    --repo muunkk/Boombox \\
    --title "Boombox $VERSION" \\
    --notes "See appcast for details."

  git add appcast.xml version.env
  git commit -m "release: Boombox $VERSION"
  git push

After the push, the installed app's "Check for Updates…" will find $VERSION.
EOF
```

- [ ] **Step 2: Run the full pipeline through appcast generation**

Run: `Scripts/release.sh 1.0.2`
Expected: builds/notarizes as before, then prints "appcast.xml updated", the grep guard passes, and the final manual-publish instructions appear. Confirm `appcast.xml` now exists at repo root.

- [ ] **Step 3: Inspect the generated appcast**

Run: `grep -E 'sparkle:edSignature|enclosure url|sparkle:version' appcast.xml`
Expected: an `<enclosure>` whose `url` is `https://github.com/muunkk/Boombox/releases/download/1.0.2/Boombox-1.0.2.dmg`, a non-empty `sparkle:edSignature`, and `sparkle:version` equal to the build number. Verify older versions (if any) retained their own URLs.

- [ ] **Step 4: Commit** (maintainer)

```bash
git add Scripts/release.sh appcast.xml version.env
git commit -m "build(release): generate + publish appcast in release.sh"
```

---

## Task 9: End-to-end staging test of the update flow

**Files:**
- None (verification task; uses a temporary local feed).

**Interfaces:**
- Consumes: everything above.
- Produces: confidence that an installed app detects, downloads, verifies, and installs an update.

> This validates the loop with a LOCAL appcast before trusting the live GitHub feed.

- [ ] **Step 1: Build + install a baseline**

Run:
```bash
Scripts/release.sh 9.0.0
cp -R .build/app/Boombox.app /Applications/
```
Expected: `/Applications/Boombox.app` is version 9.0.0.

- [ ] **Step 2: Stand up a local feed**

Run:
```bash
( cd releases && python3 -m http.server 8000 >/dev/null 2>&1 & echo $! > /tmp/boombox_feed.pid )
```
Expected: a local server serving `releases/` (DMGs + appcast.xml) at `http://localhost:8000`.

- [ ] **Step 3: Point a test build at the local feed + cut a newer version**

Temporarily set `SU_FEED_URL=http://localhost:8000/appcast.xml` in `version.env`, rebuild + reinstall 9.0.0 (so the installed app polls localhost), then restore the real `SU_FEED_URL` and run `Scripts/release.sh 9.0.1`. Re-run `generate_appcast` with `--download-url-prefix http://localhost:8000/` so the local appcast's new enclosure points at the local DMG:

```bash
SPARKLE_BIN="$(find "$(pwd)/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
"$SPARKLE_BIN/generate_appcast" releases --download-url-prefix "http://localhost:8000/"
```

Expected: `releases/appcast.xml` lists 9.0.1 with a `localhost:8000` enclosure URL.

- [ ] **Step 4: Trigger the update**

Launch `/Applications/Boombox.app`, then use **Boombox → Check for Updates…**.
Expected: Sparkle shows "A new version of Boombox is available" (9.0.1), downloads from localhost, verifies the EdDSA signature, installs, and offers to relaunch. After relaunch, the app reports 9.0.1 (About box / `CFBundleShortVersionString`).

- [ ] **Step 5: Tear down**

Run: `kill "$(cat /tmp/boombox_feed.pid)" && rm -f /tmp/boombox_feed.pid` and confirm `version.env` `SU_FEED_URL` is back to the real GitHub URL. Remove the test 9.0.x DMGs from `releases/` and regenerate the real appcast if needed.
Expected: local server stopped; `version.env` restored.

- [ ] **Step 6: Record the result**

No commit (verification only). Note the outcome in `docs/progress.md` (Task 10).

---

## Task 10: Documentation

**Files:**
- Create: `docs/adr/0001-sparkle-auto-updates-drop-sandbox.md` (use the next free ADR number in `docs/adr/`)
- Create: `docs/release-runbook.md`
- Modify: `README.md`, `docs/progress.md`, `docs/user-stories.csv`

- [ ] **Step 1: Write the ADR**

Create `docs/adr/0001-sparkle-auto-updates-drop-sandbox.md` capturing: context (need a self-updating stable build), decision (adopt Sparkle 2 via SPM; drop the App Sandbox for self-distribution; Developer ID + notarization; GitHub Releases + raw appcast), consequences (seamless updates; one dependency restored; at-rest cookie isolation moves to `~/Library/Application Support`), and the **follow-up**: Keychain-encrypt stored auth cookies rather than relying on container isolation. Reference the spec at `docs/superpowers/specs/2026-06-23-sparkle-auto-updates-design.md`.

- [ ] **Step 2: Write the release runbook**

Create `docs/release-runbook.md`: prerequisites (Developer ID Application cert in Keychain; `notarytool store-credentials boombox-notary`; EdDSA key via `generate_keys`; `SU_PUBLIC_ED_KEY` in `version.env`; `gh` authenticated), then the one-command flow (`Scripts/release.sh <version>` → manual `gh release create` + `git push`), and the staging-test procedure from Task 9.

- [ ] **Step 3: Update the README**

In `README.md`: remove/replace the "no auto-updater" sentence in the Pre-release notice and the "Removed: … Sparkle auto-updater" bullet; add an **Install** section (download the DMG from Releases, drag to /Applications) and an **Updates** section (auto-checks daily; Boombox → Check for Updates…).

- [ ] **Step 4: Update progress log + user stories**

Append a dated entry to `docs/progress.md` summarizing the effort and the Task 9 staging result; add/adjust the relevant row(s) in `docs/user-stories.csv` for the auto-update + release-pipeline feature.

- [ ] **Step 5: Final full verification**

Run: `swift build && swift test --skip KasetUITests && swiftlint --strict && swiftformat .`
Expected: all green.

- [ ] **Step 6: Commit** (maintainer)

```bash
git add docs/adr/ docs/release-runbook.md README.md docs/progress.md docs/user-stories.csv
git commit -m "docs(updates): ADR, release runbook, README + progress for Sparkle auto-updates"
```

---

## Self-Review Notes (resolved during authoring)

- **Spec coverage:** updater + menu (Tasks 3–4); auto-check (Task 5 Info.plist); drop sandbox + safety gate (Task 2); Developer ID + notarization (Tasks 6–7); DMG (Task 7); appcast on GitHub raw (Task 8); EdDSA keys (Task 5); versioning (Task 7); staging test (Task 9); ADR/README/runbook/progress (Task 10). All spec sections map to a task.
- **Top risk (Sparkle SPM signing):** handled as discover-then-sign — the script reads the framework's versioned dir and slice dynamically and verifies with `codesign --verify` + `spctl` (Task 6 Steps 3–4), rather than hardcoding `Versions/B`/slice names.
- **`generate_appcast` URL nuance:** mitigated with `--download-url-prefix` per release + a grep guard (Task 8 Steps 1, 3) and the end-to-end staging test (Task 9).
- **Secrets:** only the EdDSA *public* key and notarization profile *name* are committed; private key (Keychain) and API key (`.p8`, gitignored) never are.
- **Git boundary:** every commit/publish step is explicitly marked "(maintainer)".
