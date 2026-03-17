#!/usr/bin/env bash
# build-release.sh — Full Knok release pipeline
# Usage: ./scripts/build-release.sh <VERSION> <BUILD_NUMBER>
# Example: ./scripts/build-release.sh 0.1.0 1
#
# Required env vars:
#   DEVELOPER_ID      — e.g. "Developer ID Application: Tomas Ward (TEAMID)"
#   APPLE_ID          — Apple developer email
#   APPLE_TEAM_ID     — 10-char Team ID
#   APPLE_APP_PASSWORD — App-specific password for notarytool
#   SIGN_UPDATE_PATH  — path to Sparkle's sign_update binary

set -euo pipefail

VERSION="${1:?VERSION required}"
BUILD_NUMBER="${2:?BUILD_NUMBER required}"
DEVELOPER_ID="${DEVELOPER_ID:?DEVELOPER_ID env var required}"
APPLE_ID="${APPLE_ID:?APPLE_ID env var required}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID env var required}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD env var required}"
SIGN_UPDATE_PATH="${SIGN_UPDATE_PATH:?SIGN_UPDATE_PATH env var required}"
# Optional: private key passed via env (CI). If absent, sign_update uses keychain.
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"

APP_NAME="Knok"
BUNDLE_ID="app.getknok.Knok"
ARTIFACTS_DIR="$(pwd)/.artifacts"
APP_BUNDLE="$ARTIFACTS_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$ARTIFACTS_DIR/$DMG_NAME"

echo "==> Building $APP_NAME $VERSION (build $BUILD_NUMBER)"

# Clean artifacts
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ── 1. Swift build ────────────────────────────────────────────────────────────
echo "==> swift build -c release"
swift build -c release --product KnokApp

BINARY_SRC=".build/release/KnokApp"
SPARKLE_FRAMEWORK_SRC=$(find .build -path "*/Sparkle.framework" -maxdepth 6 | head -1)

if [ -z "$SPARKLE_FRAMEWORK_SRC" ]; then
    echo "ERROR: Sparkle.framework not found in .build/" >&2
    exit 1
fi

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
echo "==> Assembling .app bundle"

cp "$BINARY_SRC" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Sources/KnokApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Patch version into bundle's Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# ── 3. Embed Sparkle.framework ────────────────────────────────────────────────
echo "==> Embedding Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/"

# Fix rpath so the binary can find the framework at runtime
install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# ── 4. Code sign ─────────────────────────────────────────────────────────────
echo "==> Code signing"

# Sign framework first (inner → outer)
codesign \
    --force \
    --options runtime \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater" \
    2>/dev/null || true

codesign \
    --force \
    --deep \
    --options runtime \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Sign the binary
codesign \
    --force \
    --options runtime \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Sign the bundle
codesign \
    --force \
    --deep \
    --options runtime \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    --identifier "$BUNDLE_ID" \
    "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --verbose=4 "$APP_BUNDLE" || echo "Note: spctl may fail without notarization"

# ── 5. Create DMG ─────────────────────────────────────────────────────────────
echo "==> Creating DMG: $DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# ── 6. Notarize ──────────────────────────────────────────────────────────────
echo "==> Notarizing (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

# ── 7. Staple ─────────────────────────────────────────────────────────────────
echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Validating staple"
xcrun stapler validate "$DMG_PATH"

# ── 8. Sign update (Sparkle EdDSA) ───────────────────────────────────────────
echo "==> Generating EdDSA signature"
DMG_SIZE=$(stat -f%z "$DMG_PATH")
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
    EDDSA_SIG=$(echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE_PATH" --ed-key-file - -p "$DMG_PATH")
else
    EDDSA_SIG=$("$SIGN_UPDATE_PATH" -p "$DMG_PATH")
fi

echo "EdDSA signature: $EDDSA_SIG"
echo "DMG size: $DMG_SIZE bytes"

# ── 9. Update appcast.xml ─────────────────────────────────────────────────────
echo "==> Updating appcast.xml"
DOWNLOAD_URL="https://github.com/TomasWard1/knok/releases/download/v${VERSION}/${DMG_NAME}"
python3 scripts/update-appcast.py \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --url "$DOWNLOAD_URL" \
    --signature "$EDDSA_SIG" \
    --size "$DMG_SIZE"

echo ""
echo "✓ Release artifacts ready:"
echo "  App bundle:  $APP_BUNDLE"
echo "  DMG:         $DMG_PATH"
echo "  appcast.xml: updated"
echo ""
echo "Next: commit appcast.xml, then gh release create v$VERSION $DMG_PATH"
