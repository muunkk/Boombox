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

# --- 1. Build (or RESUME). If the DMG already exists, skip the rebuild so a run
#        interrupted at notarization (e.g. Apple's queue stalled) can be finished
#        by simply re-running this script. Remove the DMG to force a clean rebuild. ---
if [[ -f "$DMG" ]]; then
  echo "↻ $DMG already exists — resuming without rebuilding (rm it to force a clean rebuild)."
else
  # Bump version.env (marketing version + monotonic build number).
  NEW_BUILD=$(( BUILD_NUMBER + 1 ))
  /usr/bin/sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" "$ROOT/version.env"
  /usr/bin/sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$NEW_BUILD/" "$ROOT/version.env"
  echo "📌 Releasing $VERSION (build $NEW_BUILD)"
  echo "   (If a later step fails, revert version.env: git checkout -- version.env)"

  # Build universal, Developer ID signed (embeds + inside-out signs Sparkle).
  ARCHES="arm64 x86_64" BOOMBOX_SIGNING=release "$ROOT/Scripts/build-app.sh" release

  # Verify the code signature is valid + complete (all nested code signed).
  # Do NOT run `spctl -a -t exec` here: a Developer ID app that is not notarized
  # YET is correctly rejected by Gatekeeper ("Unnotarized Developer ID"), so the
  # Gatekeeper assessment belongs AFTER notarization + stapling.
  echo "🔎 Verifying code signature…"
  if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
    echo "ERROR: code signature verification failed — check the Developer ID identity." >&2
    exit 1
  fi

  # Stage + build a compressed DMG.
  mkdir -p "$RELEASES_DIR"
  STAGE="$ROOT/.build/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Boombox" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  echo "💿 Built $DMG"
fi

# --- 2. Notarize + staple (skip if the DMG is already notarized + stapled). ---
if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
  echo "✅ $DMG is already notarized + stapled — skipping notarization."
else
  # Submit WITHOUT --wait and poll with a bounded timeout. `--wait` can hang ~30 min
  # then exit 124 when Apple's notary queue stalls; polling lets us fail fast with
  # actionable guidance. (A stuck submission can block the whole queue and notarytool
  # cannot cancel it — re-running this script later resumes once Apple recovers.)
  echo "🔏 Notarizing (submitting + polling Apple)…"
  SUB_OUT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" 2>&1) || true
  echo "$SUB_OUT"
  SUB_ID=$(grep -m1 -oE '\bid: [0-9a-f-]+' <<<"$SUB_OUT" | awk '{print $2}')
  if [[ -z "$SUB_ID" ]]; then
    echo "ERROR: notarytool submit failed (no submission id returned)." >&2
    exit 1
  fi
  NOTARY_STATUS=""
  for _ in $(seq 1 60); do   # ~30 min cap (60 × 30s)
    NOTARY_STATUS=$(xcrun notarytool info "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" 2>/dev/null | sed -n 's/.*status: //p' | tr -d '[:space:]')
    [[ "$NOTARY_STATUS" == Accepted || "$NOTARY_STATUS" == Invalid || "$NOTARY_STATUS" == Rejected ]] && break
    sleep 30
  done
  if [[ "$NOTARY_STATUS" != Accepted ]]; then
    echo "ERROR: notarization not Accepted (status: ${NOTARY_STATUS:-timeout})." >&2
    if [[ "$NOTARY_STATUS" == Invalid || "$NOTARY_STATUS" == Rejected ]]; then
      echo "  --- notary log ---" >&2
      xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 | head -40 >&2
    else
      echo "  Apple's notary queue appears slow/stuck (a known, recurring Apple issue — a stuck" >&2
      echo "  submission can block later ones, and notarytool has no cancel). The signed DMG is" >&2
      echo "  ready, so just re-run this script later to RESUME (it skips the rebuild and re-" >&2
      echo "  notarizes): Scripts/release.sh $VERSION" >&2
      echo "  Watch the queue with: xcrun notarytool history --keychain-profile $NOTARY_PROFILE" >&2
    fi
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  # Verify Gatekeeper accepts the notarized app *inside* the DMG — the real
  # end-user guarantee. This pipeline notarizes the DMG without code-signing the
  # disk image itself, so `spctl -t open` on the DMG reports "no usable signature"
  # even when it is correctly notarized + stapled; assess the app, not the DMG.
  VERIFY_MP="$ROOT/.build/dmg-verify"
  hdiutil detach "$VERIFY_MP" >/dev/null 2>&1 || true
  rm -rf "$VERIFY_MP"
  hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$VERIFY_MP"
  GK_OK=0
  if spctl -a -t exec -vv "$VERIFY_MP/Boombox.app" 2>&1 | grep -q 'source=Notarized Developer ID'; then
    GK_OK=1
  fi
  hdiutil detach "$VERIFY_MP" >/dev/null 2>&1 || true
  if [[ "$GK_OK" -ne 1 ]]; then
    echo "ERROR: notarized app failed Gatekeeper assessment (source != Notarized Developer ID)." >&2
    exit 1
  fi
  echo "✅ Notarized + stapled; app inside passes Gatekeeper (Notarized Developer ID)."
fi

# --- 3. Sign this release + merge it into the persistent appcast ---
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

# --- 4. Verify EVERY enclosure URL matches its own version (not just the current one) ---
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
