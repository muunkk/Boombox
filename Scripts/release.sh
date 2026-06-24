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

# Verify the code signature is valid + complete (all nested code signed).
# Do NOT run `spctl -a -t exec` here: a Developer ID app that is not notarized
# YET is correctly rejected by Gatekeeper ("Unnotarized Developer ID"), so the
# Gatekeeper assessment belongs AFTER notarization + stapling (step 4).
echo "🔎 Verifying code signature…"
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  echo "ERROR: code signature verification failed — check the Developer ID identity." >&2
  exit 1
fi

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
# notarytool submit --wait exits 0 even when the result is Invalid/Rejected, so
# parse the status explicitly and fail loudly with the log command.
echo "🔏 Notarizing (can take a few minutes)…"
NOTARY_OUT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
echo "$NOTARY_OUT"
if ! grep -q 'status: Accepted' <<<"$NOTARY_OUT"; then
  SUBMISSION_ID=$(grep -m1 -oE '\bid: [0-9a-f-]+' <<<"$NOTARY_OUT" | awk '{print $2}')
  echo "ERROR: notarization was not Accepted. Inspect the log with:" >&2
  echo "  xcrun notarytool log ${SUBMISSION_ID:-<submission-id>} --keychain-profile $NOTARY_PROFILE" >&2
  exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
# Now that it's notarized + stapled, Gatekeeper must accept it.
if ! spctl -a -t open --context context:primary-signature -vvv "$DMG" 2>&1 | grep -q ': accepted'; then
  echo "ERROR: notarized DMG failed Gatekeeper assessment." >&2
  exit 1
fi
echo "✅ Notarized + stapled + Gatekeeper-accepted."

# --- 5. Sign this release + merge it into the persistent appcast ---
# Generate the appcast over a SINGLE-version dir so the one --download-url-prefix is
# correct for exactly this release. (A shared multi-version dir would rewrite EVERY
# release's enclosure to the current tag, 404-ing older versions.) Then merge the
# resulting item into the persistent, committed appcast, which keeps each version's
# own URL — see Scripts/merge_appcast.py.
SPARKLE_BIN="$(find "$ROOT/.build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -n1)"
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "ERROR: Sparkle bin not found; run 'swift build' first." >&2
  exit 1
fi
GENDIR="$ROOT/.build/appcast-gen"
rm -rf "$GENDIR"
mkdir -p "$GENDIR"
cp "$DMG" "$GENDIR/"
"$SPARKLE_BIN/generate_appcast" "$GENDIR" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$VERSION/"

python3 "$ROOT/Scripts/merge_appcast.py" "$GENDIR/appcast.xml" "$ROOT/appcast.xml"
echo "📰 appcast.xml updated with $VERSION"

# --- 6. Verify EVERY enclosure URL matches its own version (not just the current one) ---
python3 - "$ROOT/appcast.xml" "$VERSION" <<'PY'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
xml = open(path, encoding="utf-8").read()
urls = re.findall(r'url="([^"]+Boombox-[^"/]+\.dmg)"', xml)
bad = [u for u in urls if not re.search(r"/releases/download/([^/]+)/Boombox-\1\.dmg$", u)]
if bad:
    sys.exit("ERROR: appcast enclosure URL/version mismatch:\n  " + "\n  ".join(bad))
if not any(("Boombox-%s.dmg" % ver) in u for u in urls):
    sys.exit("ERROR: current version %s missing from appcast" % ver)
print("appcast URL check OK (%d version(s))" % len(urls))
PY

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
