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
- **4 targets:** KnokCore (lib), KnokApp (menu bar), KnokCLI, KnokMCP
