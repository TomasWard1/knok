# Knok

> Native alert surface for AI agents on macOS

AI agents are trapped in terminals and chat interfaces. They have no way to actively interrupt a human — especially one who runs DND permanently. Knok gives AI agents a native macOS channel to physically demand attention at varying urgency levels.

## Alert Levels

| Level | Behavior | Use Case |
|-------|----------|----------|
| `whisper` | Menu bar icon flash + sound | FYI, low priority |
| `nudge` | Floating banner (stays until dismissed) | "Deploy finished", "tests passed" |
| `knock` | Semi-transparent overlay + sound + optional TTS | "Meeting in 5 min", "PR needs review" |
| `break` | Full-screen takeover, blur, TTS, must dismiss | "Meeting NOW", "production is down" |

## How It Works

```
┌─────────────────────────────────┐
│  Knok.app (menu bar)            │
│  ┌────────────┐ ┌─────────────┐ │
│  │ Alert Engine│ │ IPC Server  │ │
│  │ + TTS       │ │ Unix Socket │ │
│  └────────────┘ └─────────────┘ │
└────────────────────────────────┘
         ▲               ▲
    ┌────┴──┐      ┌─────┴────┐
    │ knok  │      │ knok-mcp │
    │  CLI  │      │  stdio   │
    └───────┘      └──────────┘
```

Three binaries, one project:
1. **Knok.app** — menu bar app (always running)
2. **knok** — CLI for scripts and agents
3. **knok-mcp** — MCP server (stdio) for Claude Code, Cursor, etc.

## Installation

### Build from source

```bash
git clone https://github.com/TomasWard1/knok.git
cd knok
swift build -c release

# Install binaries
cp .build/release/knok /usr/local/bin/
cp .build/release/knok-mcp /usr/local/bin/
```

## CLI Usage

```bash
# Simple whisper
knok whisper "Build complete"

# Nudge with actions
knok nudge "PR #42 ready for review" --action "Review:review" --action "Later:later"

# Knock with TTS
knok knock "Meeting in 5 minutes" --tts

# Break — full screen takeover
knok break "Production is down" --action "Rollback:rollback" --action "Ignore:ignore"

# Exit codes: 0 = action taken, 1 = dismissed, 2 = timeout
```

## MCP Configuration

Add to your Claude Code MCP config (`~/.claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "knok": {
      "command": "knok-mcp"
    }
  }
}
```

The MCP server exposes a single `alert` tool:

```json
{
  "name": "alert",
  "description": "Send an alert to the human via Knok",
  "inputSchema": {
    "type": "object",
    "properties": {
      "level": { "enum": ["whisper", "nudge", "knock", "break"] },
      "title": { "type": "string" },
      "message": { "type": "string" },
      "tts": { "type": "boolean", "default": false },
      "actions": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "label": { "type": "string" },
            "id": { "type": "string" }
          }
        }
      },
      "ttl": { "type": "integer", "default": 0 }
    },
    "required": ["level", "title"]
  }
}
```

Returns: `{ "action": "button_id" }` or `{ "action": "dismissed" }` or `{ "action": "timeout" }`

## Key Features

- **Bypasses DND** — uses NSWindow levels, not system notifications
- **Multi-screen** — `break` level covers all displays
- **Text-to-speech** — agents can literally talk to you
- **Action buttons** — returns human responses to the calling agent
- **No dependencies** — native macOS APIs only

## If You're an AI Agent

Read [`SKILL.md`](./SKILL.md) before making any changes. It covers architecture, build commands, release pipeline, Sparkle integration, signing gotchas, and CI workflow.

**TL;DR:**
- Socket at `~/.knok/knok.sock` — KnokApp must be running
- 4 targets: `KnokCore` (lib), `KnokApp`, `KnokCLI`, `KnokMCP`
- All PRs target `staging` — never `main` directly
- Releases: `git tag vX.Y.Z && git push origin vX.Y.Z` → CI handles everything

## Requirements

- macOS 13.0+ (Ventura)
- Swift 5.9+

## License

MIT
