---
name: compile-knok-app-testing
description: Build and launch Knok.app locally for testing. Handles kill, rebuild, bundle assembly, Sparkle framework, asset catalog, rpath fix, ad-hoc signing, and launch. Use when you need to test Knok changes locally.
---

# Compile & Launch Knok.app for Local Testing

## Steps

Run this single script from the repo root (`/Users/tomasward/Desktop/Dev/knok`):

```bash
# 1. Kill existing instance
kill $(pgrep -f ".build/Knok.app/Contents/MacOS/Knok") 2>/dev/null
sleep 1

# 2. Full build (need all targets linked, not just --target KnokApp)
swift build

# 3. Assemble .app bundle
APP=".build/Knok.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

# Binary
cp .build/arm64-apple-macosx/debug/KnokApp "$APP/Contents/MacOS/Knok"

# Sparkle framework
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
cp -R .build/arm64-apple-macosx/debug/Sparkle.framework "$APP/Contents/Frameworks/"

# Info.plist
cp Sources/KnokApp/Info.plist "$APP/Contents/"

# Resources: copy compiled assets from installed app (SPM debug doesn't compile .xcassets)
cp /Applications/Knok.app/Contents/Resources/Assets.car "$APP/Contents/Resources/" 2>/dev/null
cp /Applications/Knok.app/Contents/Resources/MenuBarIcon.png "$APP/Contents/Resources/" 2>/dev/null
cp /Applications/Knok.app/Contents/Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/" 2>/dev/null
cp /Applications/Knok.app/Contents/Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null

# Also copy SPM resource bundle (for any non-asset resources)
cp -R .build/arm64-apple-macosx/debug/Knok_KnokApp.bundle "$APP/Contents/Resources/" 2>/dev/null

# 4. Fix rpath (Sparkle is in Frameworks/, binary looks at @loader_path by default)
install_name_tool -add_rpath @loader_path/../Frameworks "$APP/Contents/MacOS/Knok" 2>/dev/null

# 5. Ad-hoc sign (required after install_name_tool)
codesign --force --deep -s - "$APP"

# 6. Clear cached window frames (prevents stale UI from previous runs)
defaults delete app.getknok.Knok 2>/dev/null

# 7. Launch
open "$APP"
```

## Gotchas

- **Must use `swift build` (full)**, not `swift build --target KnokApp`. The target-only build compiles but doesn't always link the executable.
- **SPM debug builds don't compile .xcassets** into .car files. The menu bar icon won't show without copying the compiled assets from `/Applications/Knok.app`.
- **Sparkle framework rpath**: Debug binary has `@loader_path` rpath but Sparkle lives in `Contents/Frameworks/`. The `install_name_tool` call adds `@loader_path/../Frameworks`.
- **Window frame cache**: macOS caches window sizes by app bundle ID. `defaults delete` clears it so size changes take effect.
- **Code signature**: `install_name_tool` invalidates signatures. Ad-hoc re-signing (`-s -`) is sufficient for local testing.
