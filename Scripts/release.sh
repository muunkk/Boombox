#!/usr/bin/env bash
# One-command release for Boombox:
#   bump → build (universal, Developer ID) → DMG → notarize → staple → appcast.
#
# Prereqs (see docs/release-runbook.md):
#   • Developer ID Application certificate in the login Keychain
#   • A notarytool keychain profile (default name: boombox-notary)
#       xcrun notarytool store-credentials boombox-notary --key … --key-id … --issuer …
#   • An EdDSA key from Sparkle's generate_keys, with SU_PUBLIC_ED_KEY set in version.env
#   • gh authenticated (for the final publish step, which YOU run)
#
# Usage: Scripts/release.sh <marketing-version>     e.g.  Scripts/release.sh 1.1.0
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION="${1:?Usage: release.sh <marketing-version>  e.g. release.sh 1.1.0}"
NOTARY_PROFILE="${BOOMBOX_NOTARY_PROFILE:-boombox-notary}"
RELEASES_DIR="$ROOT/releases"
APP="$ROOT/.build/app/Boombox.app"
DMG="$RELEASES_DIR/Boombox-$VERSION.dmg"
REPO="muunkk/Boombox"

source "$ROOT/version.env"

# --- 0. Guard: a real EdDSA public key must be configured (relocated here so it
#         never blocks local dev/adhoc builds via build-app.sh). ---
if [[ -z "${SU_PUBLIC_ED_KEY:-}" || "${SU_PUBLIC_ED_KEY}" == REPLACE_* ]]; then
  echo "ERROR: SU_PUBLIC_ED_KEY is not set in version.env." >&2
  echo "       Run Sparkle's generate_keys and paste the public key into version.env." >&2
  exit 1
fi
: "${SU_FEED_URL:?SU_FEED_URL must be set in version.env}"

# Refuse to release a version that already has a DMG (avoids clobbering a shipped build).
if [[ -f "$DMG" ]]; then
  echo "ERROR: $DMG already exists — bump to a new version or remove it first." >&2
  exit 1
fi

# --- 1. Bump version.env (marketing version + monotonic build number) ---
NEW_BUILD=$(( BUILD_NUMBER + 1 ))
/usr/bin/sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" "$ROOT/version.env"
/usr/bin/sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$NEW_BUILD/" "$ROOT/version.env"
echo "📌 Releasing $VERSION (build $NEW_BUILD)"
echo "   (If a later step fails, revert version.env: git checkout -- version.env)"

# --- 2. Build universal, Developer ID signed (embeds + inside-out signs Sparkle) ---
ARCHES="arm64 x86_64" BOOMBOX_SIGNING=release "$ROOT/Scripts/build-app.sh" release

# Fail fast if Gatekeeper would reject the freshly signed app.
echo "🔎 Verifying Developer ID signature…"
spctl -a -t exec -vvv "$APP" 2>&1 | grep -E 'accepted|source=' || {
  echo "ERROR: app failed Gatekeeper assessment — check the Developer ID identity." >&2
  exit 1
}

# --- 3. Stage + build a compressed DMG ---
mkdir -p "$RELEASES_DIR"
STAGE="$ROOT/.build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Boombox" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "💿 Built $DMG"

# --- 4. Notarize + staple the DMG ---
echo "🔏 Notarizing (can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "✅ Notarized + stapled."

# --- 5. Generate/refresh the appcast (auto-signs each archive via the Keychain key) ---
SPARKLE_BIN="$(find "$ROOT/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "ERROR: Sparkle bin not found; run 'swift build' first." >&2
  exit 1
fi
DL_PREFIX="https://github.com/$REPO/releases/download/$VERSION/"
"$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR" --download-url-prefix "$DL_PREFIX"

# generate_appcast writes appcast.xml into RELEASES_DIR; publish a copy at repo root
# (this is the SUFeedURL path served from the main branch).
cp "$RELEASES_DIR/appcast.xml" "$ROOT/appcast.xml"
echo "📰 appcast.xml updated (download prefix: $DL_PREFIX)"

# --- 6. Verify the new item points at the right URL ---
if ! grep -q "Boombox-$VERSION.dmg" "$ROOT/appcast.xml"; then
  echo "ERROR: appcast.xml is missing the $VERSION enclosure — check download-url-prefix." >&2
  exit 1
fi

cat <<EOF

✅ Release $VERSION prepared locally.

Publishing is outward-facing, so YOU run these final steps:

  gh release create "$VERSION" "$DMG" \\
    --repo $REPO \\
    --title "Boombox $VERSION" \\
    --notes "See the in-app release notes."

  git add appcast.xml version.env
  git commit -m "release: Boombox $VERSION"
  git push

After the push + release, installed copies will find $VERSION via Check for Updates.
EOF
