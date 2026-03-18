# Knok

## Git Workflow

### Branch Strategy
- `main` = production (releases tagged from here)
- `staging` = integration branch (all PRs target here)
- `feat/*`, `fix/*`, `chore/*` = development branches (from staging)

### CI/CD
1. Create PR to `staging`: `gh pr create --base staging`
2. CI runs: build + test + release build
3. Push to staging → auto-creates PR to main
4. Merge to main → tag for release

### Rules
- **NEVER** push directly to main
- All PRs target `staging`
- Tags (`v*`) trigger release workflow with binary packaging

## Architecture

- **Language:** Swift 6.0, macOS 13+
- **Build:** Swift Package Manager
- **IPC:** Unix Domain Socket at `~/.knok/knok.sock`
- **MCP:** modelcontextprotocol/swift-sdk 0.9.0
- **Bundle ID:** `app.getknok.Knok` | **Team ID:** `2JSZ8CME85`

### Targets

| Target | Binary | Role |
|--------|--------|------|
| `KnokCore` | lib | Models, AlertPayload, SocketServer, constants |
| `KnokApp` | `Knok.app` | Menu bar app, AlertEngine, Sparkle updater |
| `KnokCLI` | `knok` | CLI for scripts/agents |
| `KnokMCP` | `knok-mcp` | MCP stdio server |

### Key Files

| File | Purpose |
|------|---------|
| `Sources/KnokApp/Info.plist` | Bundle ID, version, SUFeedURL, SUPublicEDKey |
| `appcast.xml` | Sparkle RSS feed (committed to main, CI updates on release) |
| `scripts/build-release.sh` | Full local/CI release pipeline |
| `scripts/update-appcast.py` | Inserts `<item>` into appcast.xml |
| `.github/workflows/release.yml` | CI release workflow (triggered on `v*` tags) |
| `.github/workflows/build.yml` | PR CI: build + test |
| `.github/workflows/promote-to-main.yml` | staging → main auto-promotion |

## Build

```bash
swift build                        # all targets
swift build --target KnokApp      # app only
swift build -c release             # release build
swift test                         # run tests
```

## Release Pipeline

Trigger: `git tag vX.Y.Z && git push origin vX.Y.Z`

CI does: swift build → assemble .app → codesign (Developer ID, hardened runtime) → notarytool → staple → DMG → EdDSA sign → commit appcast.xml to main → `gh release create`

Sparkle auto-update: running Knok polls `appcast.xml` on main via `SUFeedURL`. CI updates it on every release.

### Triggering a Release

```bash
# 1. Bump version in Info.plist (CFBundleShortVersionString + CFBundleVersion)
# 2. Commit + merge to main via staging
# 3. Tag from main
git tag vX.Y.Z
git push origin vX.Y.Z   # triggers release.yml
```

### Local Release Build

```bash
export DEVELOPER_ID="Developer ID Application: Tomas Ward (2JSZ8CME85)"
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="2JSZ8CME85"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export SIGN_UPDATE_PATH="/path/to/sparkle/bin/sign_update"

./scripts/build-release.sh 0.1.0 1
# Output: .artifacts/Knok.app + .artifacts/Knok-0.1.0.dmg
```

### Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `DEVELOPER_ID_CERTIFICATE` | `base64 -i cert.p12` (.p12 export from Keychain) |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Export password |
| `DEVELOPER_ID_NAME` | `Developer ID Application: Tomas Ward (2JSZ8CME85)` |
| `APPLE_ID` | Apple Developer email |
| `APPLE_TEAM_ID` | `2JSZ8CME85` |
| `APPLE_APP_PASSWORD` | App-specific password (appleid.apple.com) |
| `SPARKLE_PRIVATE_KEY` | `security find-generic-password -a ed25519 -s "https://sparkle-project.org" -w` |

### Sparkle Keys

**Public key** (in `Sources/KnokApp/Info.plist` as `SUPublicEDKey`):
```
1oO20R6iw8ZX8FUNfiRWPcFqmgjRNsMsSrUbOv4sW9o=
```

**Get private key** for `SPARKLE_PRIVATE_KEY` secret:
```bash
security find-generic-password -a ed25519 -s "https://sparkle-project.org" -w
```

### Signing Quick Reference

```bash
codesign --verify --deep --strict Knok.app
spctl --assess --verbose=4 Knok.app        # "accepted" after notarization
xcrun stapler validate Knok-0.1.0.dmg
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### Manual appcast Update (if CI fails mid-run)

```bash
python3 scripts/update-appcast.py \
  --version 0.1.0 --build 1 \
  --url https://github.com/TomasWard1/knok/releases/download/v0.1.0/Knok-0.1.0.dmg \
  --signature <EdDSA-base64> \
  --size <bytes>
git add appcast.xml && git commit -m "chore: update appcast for v0.1.0" && git push origin main
```

## Common Gotchas

| Symptom | Fix |
|---------|-----|
| `main actor-isolated default value` | AppDelegate needs `@MainActor` — already applied |
| `SPUStandardUpdaterController` in stored property | Swift 6: class needs `@MainActor` |
| `.cer` export fails in CI | Export as `.p12` (includes private key) |
| CI: `Developer ID not found` | Check `DEVELOPER_ID_NAME` secret matches exactly (spaces included) |
| Sparkle shows no update | `SUFeedURL` must point to `main` branch raw URL |
| Notarization rejected | All `codesign` calls need `--options runtime` |
| `sign_update` fails in CI | `SPARKLE_PRIVATE_KEY` secret missing or malformed |
