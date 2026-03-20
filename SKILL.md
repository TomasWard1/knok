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
   - Claude Code: look for `knok` in `~/.claude.json` under `mcpServers`
   - Codex CLI: look for `knok` in `~/.codex/config.toml` under `[mcp_servers]`
   - Windsurf: look for `knok` in `~/.codeium/windsurf/mcp_config.json` under `mcpServers`
2. If not configured, add the MCP server entry (see [MCP Setup](#mcp-setup) below)
3. Inform the user they need to restart the session for the MCP server to load

### "Send me a notification" / "Alert me"

Use this priority order — pick the first one available:

1. **Socket (always works locally)** — fastest, no setup needed, just requires Knok.app running:
   ```bash
   echo '{"level":"nudge","title":"Title","message":"Body"}' | nc -U ~/.knok/knok.sock
   ```
2. **HTTP (remote agents)** — works over the network (VPS, CI/CD, cloud agents):
   ```bash
   curl -X POST http://<host>:9999/alert \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"level":"nudge","title":"Title","message":"Body"}'
   ```
3. **CLI** — if `/Applications/Knok.app/Contents/MacOS/knok-cli` exists:
   ```bash
   /Applications/Knok.app/Contents/MacOS/knok-cli nudge "Body" --title "Title"
   ```
4. **MCP tool** — if `knok` MCP server is configured, call the `alert` tool directly

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

### Via HTTP (recommended for remote agents)

```bash
# Simple notification (use Tailscale hostname or IP)
curl -X POST http://your-mac.tail12345.ts.net:9999/alert \
  -H "Authorization: Bearer knk_yourtoken" \
  -H "Content-Type: application/json" \
  -d '{"level":"whisper","title":"Build Done","message":"All tests passed"}'

# With actions (waits for response)
curl -X POST http://your-mac.tail12345.ts.net:9999/alert \
  -H "Authorization: Bearer knk_yourtoken" \
  -H "Content-Type: application/json" \
  -d '{"level":"nudge","title":"Deploy Ready","message":"Deploy v2.1.0?","actions":[{"label":"Approve","id":"approve"},{"label":"Reject","id":"reject"}]}'
```

**Setup:**
1. Set `"bindAddress"` to your Tailscale IP (e.g. `"100.x.x.x"`) in `~/.knok/config.json` (default is localhost-only)
2. Open Knok Settings → Network tab, copy the auth token
3. The HTTP server runs on port 9999 by default (configurable)
4. Use your Tailscale hostname or IP from the remote machine

**Auth:** Every request needs `Authorization: Bearer <token>` header. Get the token from Knok Settings → Network tab, or from `~/.knok/config.json`.

**Errors:** `401` = bad/missing token · `400` = bad JSON · `405` = not POST

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

## HTTP Protocol

- **Endpoint:** `POST /alert` on port 9999 (configurable in `~/.knok/config.json`)
- **Bind:** `127.0.0.1` by default (localhost only). Set `bindAddress` to `"0.0.0.0"` for remote access.
- **Auth:** `Authorization: Bearer <token>` header (token from `~/.knok/config.json`)
- **Request:** `Content-Type: application/json` — same payload schema as socket
- **Response:** JSON `{"action":"..."}` with HTTP status 200
- **Errors:** 401 (bad token) · 400 (bad JSON) · 405 (wrong method) · 404 (wrong path)
- **Config file:** `~/.knok/config.json`

```json
{
  "httpServer": {
    "enabled": true,
    "port": 9999,
    "authRequired": true,
    "token": "knk_...",
    "bindAddress": "127.0.0.1"
  }
}
```

### Remote Access (VPS / Cloud Agents)

By default the HTTP server only listens on localhost. To allow remote agents to connect:

1. Install [Tailscale](https://tailscale.com) on both machines (recommended — zero-config VPN, encrypted, authenticated)
2. Set `"bindAddress"` to your Mac's Tailscale IP (e.g. `"100.x.x.x"`) in `~/.knok/config.json`. This exposes Knok only on the Tailscale network — not on local WiFi or public networks. Local CLI and MCP still work via the Unix socket.
3. Restart Knok, then use your Mac's Tailscale IP or MagicDNS hostname from the remote agent

```bash
# From your VPS (on the same tailnet)
curl -X POST http://your-mac.tail12345.ts.net:9999/alert \
  -H "Authorization: Bearer knk_yourtoken" \
  -H "Content-Type: application/json" \
  -d '{"level":"nudge","title":"Deploy Done"}'
```

**Without Tailscale:** Use SSH tunnel (`ssh -L 9999:localhost:9999 your-mac`) or Cloudflare Tunnel. Both work with `bindAddress: "127.0.0.1"` (default) since the tunnel handles remote transport.

## MCP Setup

All binaries ship inside Knok.app — no separate install needed.

### Claude Code

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "knok": {
      "command": "/Applications/Knok.app/Contents/MacOS/knok-mcp"
    }
  }
}
```

### Codex CLI

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.knok]
command = "/Applications/Knok.app/Contents/MacOS/knok-mcp"
```

### Windsurf

Add to `~/.codeium/windsurf/mcp_config.json`:

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
| HTTP `401 Unauthorized` | Check token matches `~/.knok/config.json` or Knok Settings → Network |
| HTTP `Connection refused` on remote | Check `bindAddress` is `"0.0.0.0"` in config, firewall allows port 9999, and use Tailscale |
| HTTP server not starting | Check Knok Settings → Network → "Enable HTTP server" is on |
