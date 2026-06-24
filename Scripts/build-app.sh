#!/usr/bin/env bash
# Build script to create Boombox.app bundle
# Based on Kuyruk/CodexBar packaging approach

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Load version info
source "$ROOT/version.env"

# Configuration
CONF=${1:-release}
SIGNING_MODE=${BOOMBOX_SIGNING:-dev}
APP_NAME="Boombox"
DISPLAY_NAME="Boombox"
APP_EXECUTABLE="Boombox"
SWIFT_EXECUTABLE="Boombox"
BUNDLE_ID="com.melboonchan.boombox"
DEVELOPMENT_LOCALIZATION="en"
BUILD_DIR="$ROOT/.build/app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Build for host architecture by default; allow overriding via ARCHES (e.g., "arm64 x86_64" for universal).
ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  case "$HOST_ARCH" in
    arm64) ARCH_LIST=(arm64) ;;
    x86_64) ARCH_LIST=(x86_64) ;;
    *) ARCH_LIST=("$HOST_ARCH") ;;
  esac
fi

echo "🔨 Building $DISPLAY_NAME ($CONF) for ${ARCH_LIST[*]}..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build for each architecture
for ARCH in "${ARCH_LIST[@]}"; do
  echo "  → Building for $ARCH..."
  swift build -c "$CONF" --arch "$ARCH"
done

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Build path helper
build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

# Verify binary architectures
verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

compile_asset_catalog() {
  local source_catalog="$1"
  local output_dir="$2"
  if [[ -d "$source_catalog" ]] && command -v actool &>/dev/null; then
    actool --compile "$output_dir" \
      --platform macosx \
      --minimum-deployment-target 26.0 \
      "$source_catalog" 2>/dev/null || true
  fi
}

emit_bundle_localizations_plist() {
  local resources_dir="$1"
  local development_localization="$2"
  local localization
  local localization_dir

  {
    if [[ -n "$development_localization" ]]; then
      printf '%s\n' "$development_localization"
    fi

    find "$resources_dir" -type d -name '*.lproj' -print | while IFS= read -r localization_dir; do
      localization=$(basename "$localization_dir" .lproj)
      [[ "$localization" == "Base" ]] && continue
      printf '%s\n' "$localization"
    done
  } | LC_ALL=C sort -u | while IFS= read -r localization; do
    [[ -z "$localization" ]] && continue
    printf '        <string>%s</string>\n' "$localization"
  done
}

# Install binary (handles universal builds)
install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

# Copy executable
install_binary "$SWIFT_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy app icon (.icon bundle for macOS 26+ Liquid Glass, .icns as fallback)
ICON_SOURCE="$ROOT/Sources/Kaset/Resources/boombox.icon"
if [[ -d "$ICON_SOURCE" ]]; then
  echo "🎨 Copying app icon..."
  cp -R "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/boombox.icon"
fi
ICNS_PATH="$ROOT/Sources/Kaset/Resources/boombox.icns"
if [[ -f "$ICNS_PATH" ]]; then
  cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/boombox.icns"
fi

# Compile asset catalog if actool is available
XCASSETS_PATH="$ROOT/Sources/Kaset/Resources/Assets.xcassets"
if [[ -d "$XCASSETS_PATH" ]] && command -v actool &>/dev/null; then
  echo "🎨 Compiling asset catalog..."
  compile_asset_catalog "$XCASSETS_PATH" "$APP_BUNDLE/Contents/Resources"
fi

# SwiftPM resource bundles are emitted next to the built binary
FIRST_ARCH="${ARCH_LIST[0]}"
BINARY_PATH=$(build_product_path "$SWIFT_EXECUTABLE" "$FIRST_ARCH")
PREFERRED_BUILD_DIR=$(dirname "$BINARY_PATH")
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    bundle_name=$(basename "$bundle")
    bundle_dest="$APP_BUNDLE/Contents/Resources/$bundle_name"
    echo "  → Copying resource bundle: $bundle_name"
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    if [[ -d "$bundle_dest/Assets.xcassets" ]] && command -v actool &>/dev/null; then
      echo "    ↳ Compiling bundle asset catalog"
      compile_asset_catalog "$bundle_dest/Assets.xcassets" "$bundle_dest"
    fi
  done

  # Compile catalogs into both the copied SwiftPM resource bundle and the
  # app's top-level Resources directory so Bundle.module and Bundle.main
  # lookups can both resolve packaged localizations.
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    bundle_name=$(basename "$bundle")
    bundle_dest="$APP_BUNDLE/Contents/Resources/$bundle_name"

    for xcstrings in "$bundle"/*.xcstrings; do
      if [[ -f "$xcstrings" ]]; then
        echo "  → Compiling localization catalog: $(basename "$xcstrings")"
        xcrun xcstringstool compile "$xcstrings" \
          --output-directory "$bundle_dest"
        xcrun xcstringstool compile "$xcstrings" \
          --output-directory "$APP_BUNDLE/Contents/Resources"
      fi
    done
  done
fi

APP_LOCALIZATIONS_PLIST=$(emit_bundle_localizations_plist "$APP_BUNDLE/Contents/Resources" "$DEVELOPMENT_LOCALIZATION")

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>${DEVELOPMENT_LOCALIZATION}</string>
    <key>CFBundleLocalizations</key>
    <array>
${APP_LOCALIZATIONS_PLIST}
    </array>
    <key>CFBundleExecutable</key>
    <string>${APP_EXECUTABLE}</string>
    <key>CFBundleIconFile</key>
    <string>boombox</string>
    <key>CFBundleIconName</key>
    <string>boombox</string>
    <key>NSAccentColorName</key>
    <string>AccentColor</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Boombox — fork of Kaset by sozercan, distributed under the MIT license.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
    <!-- Sparkle Auto-Update -->
    <key>SUFeedURL</key>
    <string>${SU_FEED_URL:-}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY:-}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <!-- Build Metadata -->
    <key>BoomboxBuildTimestamp</key>
    <string>${BUILD_TIMESTAMP}</string>
    <key>BoomboxGitCommit</key>
    <string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

# Strip extended attributes to prevent AppleDouble (._*) files that break code sealing
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
find "$APP_BUNDLE" -name '._*' -delete 2>/dev/null || true

# Embed Sparkle.framework and code-sign it inside-out with the SAME identity
# used for the app. Pass the codesign args array (WITHOUT --entitlements).
# Sparkle's XCFramework ships ad-hoc signed (no Team ID), and a SwiftPM build
# does not auto-sign embedded frameworks, so every nested Mach-O must be
# re-signed inside-out (deepest first). Never use --deep for signing.
embed_and_sign_sparkle() {
  local app_bundle="$1"; shift
  local codesign_args=("$@")

  # Prefer the canonical resolved artifact; fall back to a search that EXCLUDES the
  # index-build cache (which can hold a stale / differently-configured copy).
  local xc="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework"
  if [[ ! -d "$xc" ]]; then
    xc=$(find "$ROOT/.build" -type d -name 'Sparkle.xcframework' -not -path '*/index-build/*' 2>/dev/null | head -n1)
  fi
  if [[ -z "$xc" || ! -d "$xc" ]]; then
    echo "ERROR: Sparkle.xcframework not found under .build (run 'swift build' first)" >&2
    exit 1
  fi

  # Pick the macOS slice (the SPM artifact ships a universal macos-arm64_x86_64).
  local slice
  slice=$(find "$xc" -maxdepth 1 -type d -name 'macos-*' | head -n1)
  local src_fw="$slice/Sparkle.framework"
  if [[ ! -d "$src_fw" ]]; then
    echo "ERROR: Sparkle.framework not found in slice: $slice" >&2
    exit 1
  fi
  echo "  → Embedding Sparkle from: $src_fw"

  local fw_dest="$app_bundle/Contents/Frameworks/Sparkle.framework"
  mkdir -p "$app_bundle/Contents/Frameworks"
  rm -rf "$fw_dest"
  cp -R "$src_fw" "$app_bundle/Contents/Frameworks/"

  # The Boombox binary links @rpath/Sparkle.framework but SPM only gives it an
  # @loader_path rpath (works in .build, not in the bundle). Add the standard
  # bundle rpath so dyld resolves Contents/Frameworks at runtime.
  local main_bin="$app_bundle/Contents/MacOS/$APP_EXECUTABLE"
  if ! otool -l "$main_bin" 2>/dev/null | grep -qF '@loader_path/../Frameworks'; then
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$main_bin"
  fi

  # Discover the versioned dir (Sparkle 2.x uses "B"; read it rather than assume).
  local v
  v=$(readlink "$fw_dest/Versions/Current" 2>/dev/null || echo "B")
  local vroot="$fw_dest/Versions/$v"
  echo "  → Sparkle versioned dir: $vroot"

  # Sign inside-out: deepest nested code first, framework bundle last.
  # Each nested Mach-O is re-signed with our Developer ID and NO entitlements:
  # Sparkle ships them ad-hoc, and keeping Sparkle's original application-identifier
  # entitlement would mismatch our Team ID and fail notarization. Naked Mach-Os under
  # Hardened Runtime need no entitlements — do NOT add --entitlements here.
  local item
  for item in \
    "$vroot/XPCServices/Downloader.xpc" \
    "$vroot/XPCServices/Installer.xpc" \
    "$vroot/Autoupdate" \
    "$vroot/Updater.app"; do
    if [[ -e "$item" ]]; then
      echo "    ↳ signing $(basename "$item")"
      codesign "${codesign_args[@]}" "$item"
    fi
  done
  echo "    ↳ signing Sparkle.framework"
  codesign "${codesign_args[@]}" "$fw_dest"
}

# Sign the app
echo "🔏 Signing app..."
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  CODESIGN_ARGS=(--force --sign -)
elif [[ "$SIGNING_MODE" == "dev" ]]; then
  # Use Apple Development certificate
  CODESIGN_HASH=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
  if [[ -z "$CODESIGN_HASH" ]]; then
    echo "WARN: No Apple Development certificate found. Falling back to ad-hoc signing."
    CODESIGN_ARGS=(--force --sign -)
  else
    CODESIGN_ARGS=(--force --sign "$CODESIGN_HASH")
  fi
else
  CODESIGN_ID="${APP_IDENTITY:-Developer ID Application}"
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_ID")
fi

# Embed + inside-out sign Sparkle.framework BEFORE sealing the app bundle.
embed_and_sign_sparkle "$APP_BUNDLE" "${CODESIGN_ARGS[@]}"

# Sign the app bundle with entitlements
if [[ -f "$ROOT/Kaset.entitlements" ]]; then
  codesign "${CODESIGN_ARGS[@]}" --entitlements "$ROOT/Kaset.entitlements" "$APP_BUNDLE"
else
  codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
fi

echo ""
echo "✅ Build complete!"
echo "📍 App location: $APP_BUNDLE"
echo "   Version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
echo "   Commit:  ${GIT_COMMIT}"
echo "   Arches:  ${ARCH_LIST[*]}"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
