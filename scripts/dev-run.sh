#!/bin/bash
set -euo pipefail

# Build
echo "==> Building KnokApp..."
swift build

# Paths
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_BUNDLE=".build/Knok.app"

# Kill previous instance
pkill -9 -x Knok 2>/dev/null || true
rm -f ~/.knok/knok.sock
sleep 1

# Assemble .app bundle
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Binary (CFBundleExecutable = "Knok")
cp "$BUILD_DIR/KnokApp" "$APP_BUNDLE/Contents/MacOS/Knok"

# Info.plist
cp Sources/KnokApp/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Sparkle framework
cp -R "$BUILD_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/"

# SPM resource bundle
cp -R "$BUILD_DIR/Knok_KnokApp.bundle" "$APP_BUNDLE/Contents/Resources/"

# Compile asset catalog (swift build doesn't do this)
echo "==> Compiling asset catalog..."
xcrun actool \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --output-partial-info-plist /dev/null \
    Sources/KnokApp/Assets.xcassets 2>/dev/null || true

# PNG fallbacks for menu bar icon
cp Sources/KnokApp/Assets.xcassets/MenuBarIcon.imageset/menu-bar-icon.png \
    "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png" 2>/dev/null || true
cp Sources/KnokApp/Assets.xcassets/MenuBarIcon.imageset/menu-bar-icon@2x.png \
    "$APP_BUNDLE/Contents/Resources/MenuBarIcon@2x.png" 2>/dev/null || true

# Fix rpath for Sparkle (debug build only has @loader_path)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/Knok" 2>/dev/null || true

# Ad-hoc sign (Launch Services needs valid signature)
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Launching Knok.app..."
open "$APP_BUNDLE"
