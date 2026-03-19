---
name: knok
description: Use when an AI agent needs to alert, notify, or interrupt the human. Covers how to connect to Knok via socket, CLI, or MCP and send notifications with the right urgency level.
---

# Knok — Agent Integration Guide

Knok gives AI agents a physical alert channel to interrupt humans on macOS. Alerts bypass Do Not Disturb.

**Prerequisite:** Knok.app must be running (menu bar icon visible).

## Agent Decision Tree

### "Configure knok" / "Set up knok"

1. Check if MCP is already configured:
   - Claude Code: look for `knok` in `~/.claude/settings.json` or `.claude/settings.json` under `mcpServers`
   - Cursor: look for `knok` in `.cursor/mcp.json` under `mcpServers`
2. If not configured, add the MCP server entry (see [MCP Setup](#mcp-setup) below)
3. Inform the user they need to restart the session for the MCP server to load

### "Send me a notification" / "Alert me"

Use this priority order — pick the first one available:

1. **Socket (always works)** — fastest, no setup needed, just requires Knok.app running:
   ```bash
   echo '{"level":"nudge","title":"Title","message":"Body"}' | nc -U ~/.knok/knok.sock
   ```
2. **CLI** — if `/Applications/Knok.app/Contents/MacOS/knok-cli` exists:
   ```bash
   /Applications/Knok.app/Contents/MacOS/knok-cli nudge "Body" --title "Title"
   ```
3. **MCP tool** — if `knok` MCP server is configured, call the `alert` tool directly

## Alert Levels

| Level | When | Behavior |
|-------|------|----------|
| `whisper` | FYI, no action needed | Toast, auto-dismisses 5s |
| `nudge` | Need attention, not urgent | Banner, stays until dismissed |
| `knock` | Important, needs response | Overlay + sound |
| `break` | Critical, stop everything | Full-screen takeover, must acknowledge |

**Quick guide:** finished task → `whisper` · need decision → `nudge` · time-sensitive → `knock` · broken/blocking → `break`

## Sending Alerts

### Via Socket (recommended for agents)

```bash
echo '{"level":"whisper","title":"Build Done","message":"All tests passed"}' | nc -U ~/.knok/knok.sock
```

The newline at the end is **required**. `echo` adds it automatically.

**With actions:**
```bash
echo '{"level":"nudge","title":"Deploy Ready","message":"Deploy v2.1.0 to production?","actions":[{"label":"Approve","id":"approve"},{"label":"Reject","id":"reject"}]}' | nc -U ~/.knok/knok.sock
```

### Via CLI

```bash
# Simple notification
/Applications/Knok.app/Contents/MacOS/knok-cli whisper "Lint passed, no issues"

# With title and actions
/Applications/Knok.app/Contents/MacOS/knok-cli knock "Deploy v2.1.0 to production?" \
  --title "Deploy Ready" \
  --action "Approve:approve" \
  --action "Reject:reject"

# With link
/Applications/Knok.app/Contents/MacOS/knok-cli nudge "PR #42 is ready for review" \
  --title "Pull Request" \
  --action "Open PR:open:https://github.com/org/repo/pull/42"

# Critical with TTS
/Applications/Knok.app/Contents/MacOS/knok-cli break "3 endpoints down" \
  --title "Production Alert" \
  --tts --icon "exclamationmark.triangle.fill" --color "#FF4444"
```

### Via MCP Tool

If configured, call the `alert` tool with this schema:

```json
{
  "level": "nudge",
  "title": "Build Complete",
  "message": "All 42 tests passed.",
  "actions": [
    { "label": "Deploy", "id": "deploy" },
    { "label": "Skip", "id": "skip" }
  ]
}
```

## Payload Schema

```json
{
  "level": "whisper|nudge|knock|break",
  "title": "string (required)",
  "message": "string (optional)",
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

Only `level` and `title` are required. Smart defaults auto-detect icon/color from title keywords (error→red, build/deploy→green, pr/review→violet).

## Response

```json
{ "action": "approve" }
```

| Value | Meaning |
|-------|---------|
| `"{action_id}"` | Human clicked that button |
| `"dismissed"` | Closed without clicking |
| `"timeout"` | TTL expired |

**CLI exit codes:** 0 = action, 1 = dismissed, 2 = timeout.

## Socket Protocol

- **Path:** `~/.knok/knok.sock` (Unix domain, SOCK_STREAM)
- **Format:** JSON + `\n` delimiter (required)
- **Flow:** Connect → send JSON + `\n` → read response + `\n` → close
- **Max payload:** 1MB · **Timeout:** 300s

## MCP Setup

All binaries ship inside Knok.app — no separate install needed.

### Claude Code

Add to `~/.claude/settings.json` or `.claude/settings.json`:

```json
{
  "mcpServers": {
    "knok": {
      "command": "/Applications/Knok.app/Contents/MacOS/knok-mcp"
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
      "command": "/Applications/Knok.app/Contents/MacOS/knok-mcp"
    }
  }
}
```

### CLI PATH alias (optional)

```bash
sudo ln -sf /Applications/Knok.app/Contents/MacOS/knok-cli /usr/local/bin/knok
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Connection refused` / socket not found | Knok.app isn't running — launch it |
| Alert sent but nothing appears | Check menu bar for Knok icon; restart app if needed |
| Response is `{"action":"error"}` | Invalid JSON — check schema above |
| TTS doesn't work | Enable in Knok Settings → Speech tab |
