# Boombox Release Runbook

This document describes how to cut a signed, notarized, auto-updating Boombox release using the one-command pipeline in `Scripts/release.sh`.

See also: [ADR-0014](adr/0014-sparkle-auto-updates-drop-sandbox.md) for the architectural rationale.

---

## Future releases — quick reference

Once the one-time setup below is done, **every** release is just two steps:

```bash
# 1. Build + sign + notarize + update the appcast (one command).
#    Approve the Keychain prompt that appears for the appcast-signing step.
Scripts/release.sh <version>        # e.g. 1.1.0

# 2. Publish (release.sh prints these exact commands at the end).
gh release create <version> releases/Boombox-<version>.dmg \
  --repo muunkk/Boombox --title "Boombox <version>" --notes "What changed…"
git add appcast.xml version.env && git commit -m "release: Boombox <version>" && git push
```

Pick the next `<version>` higher than the last (semantic versioning — `1.0.1` for a
fix, `1.1.0` for features, `2.0.0` for breaking changes). After you push, installed
copies update within a day automatically, or instantly via **Boombox → Check for
Updates…**. Detailed steps, prerequisites, and troubleshooting follow.

---

## Prerequisites (one-time setup)

Complete these steps once on the machine you will use to cut releases. They do not need to be repeated for each release.

### 1. Developer ID Application certificate

A **Developer ID Application** certificate must be present in your login Keychain. Obtain it from the Apple Developer portal and install it via Xcode or `security import`.

Verify it is present:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Expected: one line showing your certificate name and hash.

### 2. Notarytool keychain profile

Store your App Store Connect API key in the Keychain under the profile name `boombox-notary` so `notarytool` can authenticate without requiring credentials on every run. The API key file (`AuthKey_XXXXXXXXXX.p8`) is never committed to the repo.

```bash
xcrun notarytool store-credentials boombox-notary \
  --key /path/to/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

Replace the placeholders with your actual App Store Connect API key path, key ID, and issuer UUID. Confirm with:

```bash
xcrun notarytool history --keychain-profile boombox-notary
```

Expected: "Successfully received submission history" (the list may be empty on first run).

Alternatively, if you prefer Apple ID + app-specific password:

```bash
xcrun notarytool store-credentials boombox-notary \
  --apple-id your@email.com \
  --team-id XXXXXXXXXX \
  --password <app-specific-password>
```

### 3. EdDSA key pair for Sparkle

Sparkle uses an EdDSA key pair to sign and verify update packages. The private key lives only in the Keychain; the public key is embedded in the app.

**Generate the key pair (run once):**

```bash
SPARKLE_BIN="$(find "$(pwd)/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
"$SPARKLE_BIN/generate_keys"
```

This prints a base64-encoded **public key** and saves the **private key** to your login Keychain. The private key never leaves the Keychain and is never committed.

**Add the public key to `version.env`:**

Open `version.env` and replace the placeholder value:

```bash
SU_PUBLIC_ED_KEY=REPLACE_WITH_BASE64_PUBLIC_KEY_FROM_generate_keys
```

with the actual base64 string printed by `generate_keys`. This value is not secret and is committed with the repo.

Verify:

```bash
grep SU_PUBLIC_ED_KEY version.env
```

Expected: a non-placeholder base64 string (typically ~44 characters ending in `=`).

### 4. `gh` CLI authenticated

The final publish step uses the GitHub CLI. Authenticate it if you have not already:

```bash
gh auth login
gh auth status
```

Expected: "Logged in to github.com as muunkk".

---

## Cutting a release

### One command

```bash
Scripts/release.sh <marketing-version>
```

For example:

```bash
Scripts/release.sh 1.1.0
```

The script performs these steps automatically:

1. **Bumps `version.env`** — sets `MARKETING_VERSION=<version>` and increments `BUILD_NUMBER` monotonically. Sparkle uses the build number to determine whether a release is newer.
2. **Builds a universal binary** (`arm64 + x86_64`) in Developer ID signing mode by calling `Scripts/build-app.sh release`. This step also embeds `Sparkle.framework` into `Contents/Frameworks/` and signs all nested Mach-Os inside-out (XPC services and `Updater.app` before the framework, then the framework before the app bundle) using your Developer ID certificate.
3. **Verifies the code signature** (`codesign --verify --deep --strict`) and aborts if invalid. Gatekeeper acceptance is *not* checked here — a Developer ID app is correctly rejected by `spctl` until it has been notarized, so the Gatekeeper assessment runs after step 5.
4. **Builds a compressed DMG** (`releases/Boombox-<version>.dmg`) containing `Boombox.app` and an `/Applications` symlink for drag-to-install UX.
5. **Notarizes and staples the DMG** via `xcrun notarytool submit --wait` (using the `boombox-notary` profile), then `xcrun stapler staple`, then confirms Gatekeeper accepts the stapled DMG (`spctl -a -t open`). Aborts if notarization is not accepted.
6. **Generates the appcast.** Runs `generate_appcast` over a single-version staging dir (so this release's per-version download URL is correct and no delta items are produced), reading the EdDSA private key from the Keychain to sign it. **A Keychain prompt appears here the first time — enter your login password and click _Always Allow_.** The new `<item>` is merged into the persistent `appcast.xml` at the repo root via `Scripts/merge_appcast.py`, which preserves every prior version's own download URL. (Running `generate_appcast --download-url-prefix` over a multi-version folder instead would rewrite all older releases' URLs to the current tag and 404 them — the per-version merge exists to prevent exactly that.)
7. **Prints the manual publish steps** (see below).

### Manual publish steps (you run these)

The script intentionally does not run git or `gh` commands. After the script prints "Release prepared locally", run:

```bash
gh release create <version> releases/Boombox-<version>.dmg \
  --repo muunkk/Boombox \
  --title "Boombox <version>" \
  --notes "See the in-app release notes."

git add appcast.xml version.env
git commit -m "release: Boombox <version>"
git push
```

After the push, installed copies of Boombox will discover the new version on their next automatic check (or immediately via **Boombox → Check for Updates…**).

---

## Overriding defaults

| Environment variable | Default | Purpose |
|----------------------|---------|---------|
| `BOOMBOX_NOTARY_PROFILE` | `boombox-notary` | Name of the `notarytool` keychain profile to use |

Example:

```bash
BOOMBOX_NOTARY_PROFILE=my-other-profile Scripts/release.sh 1.2.0
```

---

## Signature verification (optional)

After `release.sh` completes (before publishing), verify the bundle and DMG:

```bash
# Verify the app bundle
codesign --verify --deep --strict --verbose=2 .build/app/Boombox.app

# Confirm Gatekeeper accepts it
spctl -a -t exec -vvv .build/app/Boombox.app

# Confirm Sparkle.framework is signed with your Team ID (not ad-hoc)
codesign -dvvv .build/app/Boombox.app/Contents/Frameworks/Sparkle.framework \
  2>&1 | grep -E 'TeamIdentifier|Authority'

# Confirm the DMG is stapled
xcrun stapler validate releases/Boombox-<version>.dmg
```

---

## End-to-end staging test (before first live release)

Run this procedure once before cutting a real release to validate the entire update loop locally, without touching the live GitHub feed.

### Step 1 — Build and install a baseline version

```bash
Scripts/release.sh 9.0.0
cp -R .build/app/Boombox.app /Applications/
```

### Step 2 — Serve a local feed

In a separate terminal, start a local HTTP server in the `releases/` directory:

```bash
cd releases
python3 -m http.server 8000
```

Leave it running.

### Step 3 — Point the baseline app at the local feed

Temporarily change `SU_FEED_URL` in `version.env` to `http://localhost:8000/appcast.xml`, then rebuild and reinstall:

```bash
# In version.env: SU_FEED_URL=http://localhost:8000/appcast.xml
Scripts/build-app.sh release
cp -R .build/app/Boombox.app /Applications/
```

The installed 9.0.0 app will now poll the local server.

### Step 4 — Cut a newer version against the local feed

Restore the real `SU_FEED_URL` in `version.env`, run the release script for the next version:

```bash
# In version.env: SU_FEED_URL=https://raw.githubusercontent.com/muunkk/Boombox/main/appcast.xml
Scripts/release.sh 9.0.1
```

Then build a **local** appcast for the new DMG, pointing the download URL at the local
server. Generate over a single-version dir — never the whole `releases/` folder, since
one `--download-url-prefix` over multiple versions would rewrite older releases' URLs:

```bash
SPARKLE_BIN="$(find "$(pwd)/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
FEED=/tmp/boombox-localfeed; rm -rf "$FEED"; mkdir -p "$FEED"
cp releases/Boombox-9.0.1.dmg "$FEED/"
"$SPARKLE_BIN/generate_appcast" "$FEED" --download-url-prefix "http://localhost:8000/"
# $FEED now holds Boombox-9.0.1.dmg + a signed appcast.xml. Serve THIS dir instead of
# releases/ :  stop the earlier server, then  cd "$FEED" && python3 -m http.server 8000
```

### Step 5 — Trigger the update

1. Launch `/Applications/Boombox.app` (version 9.0.0 with the local feed URL).
2. Choose **Boombox → Check for Updates…**.
3. Expected: Sparkle shows "A new version of Boombox is available (9.0.1)", downloads from `localhost:8000`, verifies the EdDSA signature, installs the update, and offers to relaunch.
4. After relaunching, confirm the About box shows 9.0.1.

### Step 6 — Tear down

```bash
kill "$(cat /tmp/boombox_feed.pid 2>/dev/null)" 2>/dev/null || true
```

Restore `SU_FEED_URL` to the real GitHub URL in `version.env` if it was temporarily changed. Remove the test DMGs from `releases/` if desired, and regenerate the real appcast.

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `ERROR: SU_PUBLIC_ED_KEY is not set` | `generate_keys` not yet run or placeholder not replaced | Run `generate_keys` (Step 3 of prerequisites) and paste the public key into `version.env` |
| `ERROR: $DMG already exists` | A DMG for this version is already in `releases/` | Bump to a new version, or remove the existing DMG and regenerate |
| notarytool returns `Invalid` | Signing or entitlements issue | Fetch the full log: `xcrun notarytool log <submission-id> --keychain-profile boombox-notary` |
| Sparkle shows "Update Error" | `SUPublicEDKey` mismatch or wrong appcast URL | Verify `SUPublicEDKey` in Info.plist matches `generate_keys` output; verify `SUFeedURL` is correct |
| `spctl` rejects the app | Developer ID identity not found or cert expired | Check `security find-identity -v -p codesigning`; renew cert if expired |
