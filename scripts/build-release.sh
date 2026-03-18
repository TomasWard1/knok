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
swift build -c release --product KnokApp --product knok --product knok-mcp

BINARY_SRC=".build/release/KnokApp"
CLI_SRC=".build/release/knok"
MCP_SRC=".build/release/knok-mcp"
SPARKLE_FRAMEWORK_SRC=$(find .build -path "*/Sparkle.framework" -maxdepth 6 | head -1)

if [ -z "$SPARKLE_FRAMEWORK_SRC" ]; then
    echo "ERROR: Sparkle.framework not found in .build/" >&2
    exit 1
fi

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
echo "==> Assembling .app bundle"

cp "$BINARY_SRC" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$CLI_SRC" "$APP_BUNDLE/Contents/MacOS/knok"
cp "$MCP_SRC" "$APP_BUNDLE/Contents/MacOS/knok-mcp"
cp "Sources/KnokApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Patch version into bundle's Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# ── 2b. Compile asset catalog (app icon + menu bar icon) ─────────────────────
echo "==> Compiling asset catalog"
xcrun actool \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ARTIFACTS_DIR/assets-info.plist" \
    "Sources/KnokApp/Assets.xcassets"

# Copy menu bar icon PNGs directly to Resources (NSImage(named:) fallback)
cp "Sources/KnokApp/Assets.xcassets/MenuBarIcon.imageset/menu-bar-icon.png" \
    "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
cp "Sources/KnokApp/Assets.xcassets/MenuBarIcon.imageset/menu-bar-icon@2x.png" \
    "$APP_BUNDLE/Contents/Resources/MenuBarIcon@2x.png"

# ── 3. Embed Sparkle.framework ────────────────────────────────────────────────
echo "==> Embedding Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/"

# Fix rpath so the binary can find the framework at runtime
install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# ── 4. Code sign (inner → outer, no --deep to preserve identifiers) ──────────
echo "==> Code signing"

SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"

# Sign XPC services individually (preserving their bundle identifiers)
for xpc in "$SPARKLE_FW/XPCServices/"*.xpc; do
    echo "  Signing $(basename "$xpc")"
    codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$xpc"
done

# Sign Autoupdate helper
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$SPARKLE_FW/Autoupdate"

# Sign Updater.app
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$SPARKLE_FW/Updater.app"

# Sign Sparkle.framework (outer, no --deep since inner components are signed)
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Sign CLI helpers
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$APP_BUNDLE/Contents/MacOS/knok"
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$APP_BUNDLE/Contents/MacOS/knok-mcp"

# Sign the main binary
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Sign the app bundle (no --deep, no --identifier override)
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp \
    "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --verbose=4 "$APP_BUNDLE" || echo "Note: spctl may fail without notarization"

# ── 5. Create DMG with drag-to-Applications layout ───────────────────────────
echo "==> Creating DMG: $DMG_NAME"

# Install create-dmg if not present
if ! command -v create-dmg &>/dev/null; then
    echo "==> Installing create-dmg..."
    brew install create-dmg
fi

# create-dmg fails if the output file exists
rm -f "$DMG_PATH"

create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 80 \
    --icon "$APP_NAME.app" 175 190 \
    --app-drop-link 425 190 \
    --background "scripts/dmg-background.png" \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_BUNDLE"

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
