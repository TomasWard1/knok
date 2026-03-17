---
name: knok
description: Use when working on the Knok codebase — architecture reference, release pipeline, Sparkle integration, signing, CI workflow, and socket IPC protocol.
---

# Knok — Agent Reference

## Architecture

```
AI agent → knok CLI / knok-mcp → KnokCore SocketServer → KnokApp (menu bar)
```

**4 SPM targets:**

| Target | Binary | Role |
|--------|--------|------|
| `KnokCore` | lib | Models, AlertPayload, SocketServer, constants |
| `KnokApp` | `Knok.app` | Menu bar app, AlertEngine, Sparkle updater |
| `KnokCLI` | `knok` | CLI for scripts/agents |
| `KnokMCP` | `knok-mcp` | MCP stdio server |

**Socket:** `~/.knok/knok.sock` (Unix domain)
**Bundle ID:** `app.getknok.Knok` | **Team ID:** `2JSZ8CME85`
**Min OS:** macOS 13 | **Swift:** 6.0 (strict concurrency)

## Git Workflow

```
feat/* or fix/*  →  PR to staging  →  (CI)  →  auto-PR to main  →  auto-merge  →  deploy
```

- All PRs target `staging`, never `main` directly
- Tags (`v*`) trigger the release pipeline
- **Never push directly to main**

```bash
# Before any push — check PR state
gh pr list --head $(git branch --show-current) --json state,number --jq '.[0]'
```

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

**Sparkle auto-update:** running Knok polls `appcast.xml` on main via `SUFeedURL`. CI updates it on every release.

### Local release build

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

### Sparkle keys

**Public key** (in `Sources/KnokApp/Info.plist` as `SUPublicEDKey`):
```
1oO20R6iw8ZX8FUNfiRWPcFqmgjRNsMsSrUbOv4sW9o=
```

**Get private key** for `SPARKLE_PRIVATE_KEY` secret:
```bash
security find-generic-password -a ed25519 -s "https://sparkle-project.org" -w
```

**sign_update in CI** (no keychain available):
```bash
echo "$SPARKLE_PRIVATE_KEY" | sign_update --ed-key-file - -p Knok-0.1.0.dmg
```

## Signing Quick Reference

```bash
codesign --verify --deep --strict Knok.app
spctl --assess --verbose=4 Knok.app        # "accepted" after notarization
xcrun stapler validate Knok-0.1.0.dmg
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## Common Gotchas

| Symptom | Fix |
|---------|-----|
| `main actor-isolated default value` | AppDelegate needs `@MainActor` — already applied |
| `SPUStandardUpdaterController` in stored property | Swift 6: class needs `@MainActor` |
| `.cer` export fails in CI | Export as `.p12` (includes private key) |
| "Developer ID Certification Authority" in Keychain | That's Apple's CA, not your identity — create "Developer ID Application" via Xcode |
| Sparkle shows no update | `SUFeedURL` must point to `main` branch raw URL |
| Notarization rejected | All `codesign` calls need `--options runtime` |

## Key Files

| File | Purpose |
|------|---------|
| `Sources/KnokApp/Info.plist` | Bundle ID, version, SUFeedURL, SUPublicEDKey |
| `appcast.xml` | Sparkle RSS feed (committed to main, CI updates on release) |
| `scripts/build-release.sh` | Full local/CI release pipeline |
| `scripts/update-appcast.py` | Inserts `<item>` into appcast.xml |
| `.github/workflows/release.yml` | CI release workflow (triggered on `v*` tags) |
| `.github/workflows/build.yml` | PR CI: build + test |
| `.github/workflows/promote-to-main.yml` | staging → main auto-promotion |
