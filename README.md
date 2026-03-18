# Knok

A native macOS menu bar app that gives AI agents a physical alert channel to interrupt humans. Bypasses Do Not Disturb by using NSWindow levels instead of system notifications.

## Why

AI agents run in the background. When they need human input -- approval, a decision, attention -- they have no reliable way to break through. System notifications get swallowed by DND, focus modes, and notification fatigue. Knok solves this by rendering alerts as native macOS windows at elevated window levels (`floating`, `modalPanel`, `screenSaver`), making them impossible to miss.

Agents connect via a Unix domain socket at `~/.knok/knok.sock`. Send a JSON payload, get back the human's response. Works from any language, any runtime.

## Architecture

```
+------------------+         +------------------+
|   Claude Code    |         |    Any Agent     |
|   (MCP client)   |         |  (HTTP, cron..)  |
+--------+---------+         +--------+---------+
         |                            |
         v                            v
+------------------+         +------------------+
|    knok-mcp      |         |    knok CLI      |
|  (stdio server)  |         |  (swift binary)  |
+--------+---------+         +--------+---------+
         |                            |
         +------------+---------------+
                      |
                      v
              ~/.knok/knok.sock
               (Unix Domain Socket)
                      |
                      v
             +--------+---------+
             |     Knok.app     |
             |  (menu bar app)  |
             |                  |
             |  SocketServer    |
             |  AlertEngine     |
             |  WindowManager   |
             |  SoundManager    |
             |  TTSManager      |
             +------------------+
```

Three binaries, one project:

1. **Knok.app** -- menu bar app that listens on the socket and renders alerts
2. **knok** -- CLI for scripts and agents
3. **knok-mcp** -- MCP server (stdio transport) for Claude Code, Cursor, etc.

## Alert Levels

| Level     | Window Level    | Behavior                                                        | Default TTL |
|-----------|-----------------|-----------------------------------------------------------------|-------------|
| `whisper` | `.floating`     | Small toast in bottom-right corner. Auto-dismisses.             | 5s          |
| `nudge`   | `.floating`     | Floating banner with action buttons. Stays until dismissed.     | manual      |
| `knock`   | `.modalPanel`   | Overlay bar at top of screen. Sound + optional TTS.             | manual      |
| `break`   | `.screenSaver`  | Full-screen takeover on all displays. Blur + pulsing icon. Must acknowledge. | manual |

All levels support custom action buttons, SF Symbols, hex accent colors, and text-to-speech.

## Installation

### Build from source

```bash
git clone https://github.com/TomasWard1/knok.git
cd knok

# Build all targets (app + CLI + MCP server)
swift build -c release

# Create .app bundle
mkdir -p /tmp/Knok.app/Contents/MacOS
cp .build/release/KnokApp /tmp/Knok.app/Contents/MacOS/KnokApp
cp Sources/KnokApp/Info.plist /tmp/Knok.app/Contents/Info.plist

# Launch
open /tmp/Knok.app

# Install CLI and MCP server to a directory in your PATH
cp .build/release/knok /usr/local/bin/knok
cp .build/release/knok-mcp /usr/local/bin/knok-mcp
```

The app runs as a menu bar icon (no dock icon). It creates the socket at `~/.knok/knok.sock` on launch.

## MCP Server

Knok ships an MCP server (`knok-mcp`) that exposes a single `alert` tool over stdio transport.

### Tool Schema

```json
{
  "name": "alert",
  "description": "Send an alert to the human via Knok. Urgency levels: whisper (menu bar flash), nudge (floating banner), knock (overlay), break (full-screen takeover). Returns the human's response.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "level": {
        "type": "string",
        "enum": ["whisper", "nudge", "knock", "break"],
        "description": "Urgency level"
      },
      "title": {
        "type": "string",
        "description": "Alert title"
      },
      "message": {
        "type": "string",
        "description": "Alert body text"
      },
      "tts": {
        "type": "boolean",
        "description": "Speak the message aloud via text-to-speech",
        "default": false
      },
      "actions": {
        "type": "array",
        "description": "Buttons for the human to respond with",
        "items": {
          "type": "object",
          "properties": {
            "label": { "type": "string" },
            "id": { "type": "string" },
            "url": {
              "type": "string",
              "description": "URL to open in browser when button is clicked"
            },
            "icon": {
              "type": "string",
              "description": "SF Symbol for the button icon"
            }
          }
        }
      },
      "ttl": {
        "type": "integer",
        "description": "Auto-dismiss after N seconds (0 = never)",
        "default": 0
      },
      "icon": {
        "type": "string",
        "description": "SF Symbol name for the alert icon (e.g. 'video.fill', 'bolt.fill')"
      },
      "color": {
        "type": "string",
        "description": "Hex accent color (e.g. '#A855F7'). Auto-detected from title if omitted"
      }
    },
    "required": ["level", "title"]
  }
}
```

### Response

The tool returns a JSON object with the human's action:

```json
{ "action": "dismissed" }
{ "action": "timeout" }
{ "action": "approve" }
```

The `action` field is either `"dismissed"`, `"timeout"`, or the `id` of the button the human clicked.

### Claude Code

Add to `~/.claude/settings.json` (global) or `.claude/settings.json` (project):

```json
{
  "mcpServers": {
    "knok": {
      "command": "/usr/local/bin/knok-mcp"
    }
  }
}
```

Or if using the build directory directly:

```json
{
  "mcpServers": {
    "knok": {
      "command": "/path/to/knok/.build/release/knok-mcp"
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "knok": {
      "command": "/usr/local/bin/knok-mcp"
    }
  }
}
```

## CLI

The `knok` CLI sends alerts from the command line. Each alert level is a subcommand.

### Usage

```
USAGE: knok <subcommand> <message> [--title <title>] [--tts] [--action <label:id[:url]>...] [--ttl <seconds>] [--icon <sf-symbol>] [--color <hex>]

SUBCOMMANDS:
  whisper     Send a whisper-level alert (menu bar flash)
  nudge       Send a nudge-level alert (floating banner)
  knock       Send a knock-level alert (overlay)
  break       Send a break-level alert (full-screen takeover)
```

### Flags

| Flag | Description |
|------|-------------|
| `--title <string>` | Alert title (defaults to the message argument) |
| `--tts` | Speak the message via text-to-speech |
| `--action <label:id[:url]>` | Add a button. Repeatable. Format: `Label:id` or `Label:id:https://...` |
| `--ttl <int>` | Auto-dismiss after N seconds (0 = never) |
| `--icon <string>` | SF Symbol name (e.g. `bolt.fill`) |
| `--color <string>` | Hex accent color (e.g. `#A855F7`) |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0    | Human clicked an action button |
| 1    | Alert was dismissed |
| 2    | Alert timed out |

### Examples

```bash
# Simple whisper -- appears and auto-dismisses
knok whisper "Build succeeded"

# Nudge with a title and body
knok nudge "PR #42 needs your review" --title "Code Review"

# Knock with action buttons
knok knock "Deploy to production?" \
  --title "Deploy Ready" \
  --action "Approve:approve" \
  --action "Reject:reject"

# Break with TTS, custom icon and color
knok break "Server is down" \
  --title "Critical Alert" \
  --tts \
  --icon "exclamationmark.triangle.fill" \
  --color "#FF4444"

# Action button that opens a URL
knok nudge "New PR from @alice" \
  --title "Pull Request" \
  --action "Open:open:https://github.com/org/repo/pull/42"

# Auto-dismiss after 10 seconds
knok nudge "Meeting in 5 minutes" --ttl 10

# Use exit code in scripts
knok knock "Ship it?" --action "Yes:yes" --action "No:no"
if [ $? -eq 0 ]; then
  echo "User approved"
fi
```

## Settings

Click the menu bar icon and select "Settings..." to configure:

| Tab        | Options                                                                 |
|------------|-------------------------------------------------------------------------|
| Sounds     | Global enable/disable, volume slider, per-level sound selection (Tink, Glass, Purr, Sosumi, etc.) |
| Speech     | Enable/disable TTS, voice selection, speed control                      |
| Appearance | Font size (small / medium / large)                                      |
| Behavior   | Show alerts in all Spaces, per-level auto-dismiss timers, launch at login |

The menu bar popover also shows a history of recent alerts (up to 20) with their level, response, and relative timestamp.

### Smart Defaults

Knok auto-detects icon and accent color from the alert title when not explicitly set:

- Titles containing "error" or "fail" -- red accent, error icon
- Titles containing "build", "deploy", or "pass" -- green accent, bolt/check icon
- Titles containing "pr" or "review" -- violet accent, pull request icon
- Everything else -- blue with a level-appropriate icon

## If You're an AI Agent

Read [`SKILL.md`](./SKILL.md) before making any changes. It covers architecture, build commands, release pipeline, Sparkle integration, signing gotchas, and CI workflow.

**TL;DR:**
- Socket at `~/.knok/knok.sock` — KnokApp must be running
- 4 targets: `KnokCore` (lib), `KnokApp`, `KnokCLI`, `KnokMCP`
- All PRs target `staging` — never `main` directly
- Releases: `git tag vX.Y.Z && git push origin vX.Y.Z` → CI handles everything

## Requirements

- macOS 13.0+ (Ventura)
- Swift 6.0+
- Xcode 16+ or a Swift 6.0 toolchain

## License

MIT -- see [LICENSE](LICENSE).
