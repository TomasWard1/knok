---
name: knok
description: Use when an AI agent needs to alert, notify, or interrupt the human. Covers how to connect to Knok via socket, CLI, or MCP and send notifications with the right urgency level.
---

# Knok — Agent Integration Guide

Knok gives AI agents a physical alert channel to interrupt humans on macOS. Alerts render as native windows at elevated window levels — they bypass Do Not Disturb.

**Prerequisite:** Knok.app must be running (menu bar icon visible).

## Quick Start

### Option 1: MCP Tool (Claude Code, Cursor, etc.)

If `knok-mcp` is configured as an MCP server, call the `alert` tool directly:

```json
{
  "level": "nudge",
  "title": "Build Complete",
  "message": "All 42 tests passed. Ready to deploy.",
  "actions": [
    { "label": "Deploy", "id": "deploy" },
    { "label": "Skip", "id": "skip" }
  ]
}
```

### Option 2: CLI

```bash
knok nudge "All 42 tests passed" \
  --title "Build Complete" \
  --action "Deploy:deploy" \
  --action "Skip:skip"
```

### Option 3: Raw Socket

```bash
echo '{"level":"nudge","title":"Build Complete","message":"All 42 tests passed","actions":[{"label":"Deploy","id":"deploy"},{"label":"Skip","id":"skip"}]}' | nc -U ~/.knok/knok.sock
```

## Alert Levels

Pick the right level for your situation:

| Level | Use When | Behavior |
|-------|----------|----------|
| `whisper` | FYI, no action needed | Small toast, auto-dismisses in 5s |
| `nudge` | Need attention but not urgent | Floating banner, stays until dismissed |
| `knock` | Important, needs response soon | Overlay bar + sound, hard to miss |
| `break` | Critical, stop everything | Full-screen takeover on all displays, must acknowledge |

**Decision guide:**
- Task finished, just informing → `whisper`
- Need a decision, can wait → `nudge`
- Need a decision, time-sensitive → `knock`
- Something is broken / blocking → `break`

## Payload Schema

```json
{
  "level": "whisper|nudge|knock|break",
  "title": "string (required)",
  "message": "string (optional — body text)",
  "tts": false,
  "actions": [
    {
      "label": "Button Text",
      "id": "action_id",
      "url": "https://... (optional — opens on click)",
      "icon": "sf.symbol.name (optional)"
    }
  ],
  "ttl": 0,
  "icon": "sf.symbol.name (optional)",
  "color": "#hex (optional)"
}
```

Only `level` and `title` are required. Everything else has sensible defaults.

### Smart Defaults

When `icon` and `color` are omitted, Knok auto-detects from the title:
- "error", "fail" → red accent, error icon
- "build", "deploy", "pass" → green accent, success icon
- "pr", "review" → violet accent, PR icon
- Everything else → blue, level-appropriate icon

## Response

Every alert returns a JSON response when the human interacts:

```json
{ "action": "deploy" }
```

| Value | Meaning |
|-------|---------|
| `"{action_id}"` | Human clicked a button with that id |
| `"dismissed"` | Human closed the alert without clicking a button |
| `"timeout"` | TTL expired with no interaction |

**CLI exit codes:** 0 = action clicked, 1 = dismissed, 2 = timeout.

## Socket Protocol Details

For agents connecting directly (not via CLI or MCP):

- **Path:** `~/.knok/knok.sock` (Unix domain socket, SOCK_STREAM)
- **Format:** JSON + newline delimiter (`\n`) — the newline is **required**
- **Flow:** Connect → send JSON payload + `\n` → read JSON response + `\n` → close
- **No authentication** — any process that can write to the socket can send alerts
- **Max payload:** 1MB
- **Timeout:** 300s (server-side)

## Common Patterns

### Ask for approval before a risky action
```bash
knok knock "Deploy v2.1.0 to production?" \
  --title "Deploy Ready" \
  --action "Approve:approve" \
  --action "Reject:reject"

if [ $? -eq 0 ]; then
  echo "Approved"
else
  echo "Rejected or dismissed"
fi
```

### Notify completion with a link
```bash
knok nudge "PR #42 is ready for review" \
  --title "Pull Request" \
  --action "Open PR:open:https://github.com/org/repo/pull/42"
```

### Critical alert with TTS
```bash
knok break "Server health check failed — 3 endpoints down" \
  --title "Production Alert" \
  --tts \
  --icon "exclamationmark.triangle.fill" \
  --color "#FF4444"
```

### Fire-and-forget notification
```bash
knok whisper "Lint passed, no issues found"
```

## Setup

### MCP Server (Claude Code)

Add to `~/.claude/settings.json` or `.claude/settings.json`:

```json
{
  "mcpServers": {
    "knok": {
      "command": "/usr/local/bin/knok-mcp"
    }
  }
}
```

### MCP Server (Cursor)

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

### CLI

```bash
# If built from source
cp .build/release/knok /usr/local/bin/knok
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Connection refused` / socket not found | Knok.app isn't running — launch it |
| Alert sent but nothing appears | Check menu bar for Knok icon; restart app if needed |
| Response is `{"action":"error"}` | Invalid JSON payload — check schema above |
| TTS doesn't work | Enable in Knok Settings → Speech tab |
