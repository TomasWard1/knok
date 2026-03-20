<p align="center">
  <img src="https://raw.githubusercontent.com/TomasWard1/knok-landing/main/public/images/og-banner.png" alt="Knok — Let your AI agent interrupt you" width="100%" />
</p>

<p align="center">
  <a href="https://github.com/TomasWard1/knok/releases/latest"><img src="https://img.shields.io/github/v/release/TomasWard1/knok?style=flat-square&color=blue" alt="Release"></a>
  <a href="https://github.com/TomasWard1/knok/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/TomasWard1/knok/build.yml?style=flat-square" alt="Build"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/TomasWard1/knok?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square" alt="macOS 13+">
</p>

<h3 align="center">Your AI agent sends an alert → you click a button → the agent gets your response.<br>Works through DND, Focus modes, and fullscreen apps.</h3>

## Quick Start

1. **Download [Knok.app](https://knokknok.app/)** — open the DMG, drag to Applications, launch.
2. **Give your agent the integration guide** — point it to [`SKILL.md`](./SKILL.md) or add the MCP config below.

That's it. Knok runs in the menu bar, listens on a Unix socket, and your agent handles the rest.

### MCP Setup (optional — agents can also use the socket directly)

<details>
<summary><b>Claude Code</b></summary>

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
</details>

<details>
<summary><b>Codex CLI</b></summary>

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.knok]
command = "/Applications/Knok.app/Contents/MacOS/knok-mcp"
```
</details>

<details>
<summary><b>Windsurf</b></summary>

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
</details>

## Why

AI agents run in the background. When they need human input — approval, a decision, attention — they have no reliable way to break through. System notifications get swallowed by DND, Focus modes, and notification fatigue.

Knok renders alerts as native macOS windows at elevated window levels, making them impossible to miss. The agent sends a question, the human responds with action buttons, and the agent gets the answer back — a complete bidirectional channel.

## Why Not...

- **`osascript` / `display dialog`** Blocks the process, respects DND, looks like it's from 2005. No urgency tiers, no MCP. It works, but it's not built for agents.
- **terminal-notifier** Fires a macOS notification and forgets about it. DND eats it. No response back. One-way street.
- **ntfy.sh** Great for push notifications to your phone. But push-only, your agent can't get an answer back. Doesn't bypass DND on desktop.
- **Pushover** Same deal: push-only, needs an account, no MCP, no DND bypass on macOS.

Knok is the only tool purpose-built for **agent ↔ human** communication: bidirectional, breaks through DND, 4 urgency tiers, and native MCP support.

## Alert Levels

| Level | What it does | When to use it |
|-------|-------------|----------------|
| `whisper` | Small toast, bottom-right. Auto-dismisses in 5s. | Task finished, FYI, no action needed |
| `nudge` | Floating banner with buttons. Stays until dismissed. | Need a decision, not urgent |
| `knock` | Overlay bar at top of screen. Sound + optional TTS. | Time-sensitive, needs response now |
| `break` | Full-screen takeover on all displays. Must acknowledge. | Critical — stop everything |

All levels support custom action buttons, SF Symbols icons, hex accent colors, and text-to-speech.

**Smart defaults:** Knok auto-detects icon and color from the title — "error" → red, "build" → green, "PR" → violet. No config needed for common cases.

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

Three binaries ship inside Knok.app:

| Binary | Role |
|--------|------|
| **Knok.app** | Menu bar app — renders alerts, manages the socket |
| **knok-cli** | CLI for scripts and shell agents |
| **knok-mcp** | MCP server (stdio) for Claude Code, Codex, Windsurf, etc. |

**Four ways to connect:**
1. **MCP tool** — your agent calls the `alert` tool natively
2. **Unix socket** — send JSON to `~/.knok/knok.sock`, get response back
3. **CLI** — `knok whisper "done"` from any script or shell
4. **HTTP** — `POST /alert` for remote agents (VPS, CI/CD) via Tailscale or SSH tunnel

## For AI Agents

Knok ships with [`SKILL.md`](./SKILL.md) — a structured integration guide designed for LLM consumption. It includes:

- **Decision tree** for choosing the right connection method
- **Priority order**: socket → HTTP → CLI → MCP
- **Full payload schema** with smart defaults
- **Response format** and exit code semantics
- **Troubleshooting table** for common errors
- **Remote access setup** via Tailscale, SSH tunnels, or Cloudflare Tunnel

Point your agent at SKILL.md and it will know how to use Knok autonomously.

### Quick Examples

```bash
# Socket — fastest, always works if Knok.app is running
echo '{"level":"nudge","title":"Deploy?","actions":[{"label":"Yes","id":"yes"},{"label":"No","id":"no"}]}' | nc -U ~/.knok/knok.sock

# CLI — great for shell scripts
knok knock "Ship to prod?" --action "Approve:approve" --action "Reject:reject"

# HTTP — for remote agents (VPS, CI/CD)
curl -X POST http://your-mac.tail12345.ts.net:9999/alert \
  -H "Authorization: Bearer knk_yourtoken" \
  -H "Content-Type: application/json" \
  -d '{"level":"break","title":"Server Down","message":"3 endpoints failing"}'
```

## CLI Reference

```
USAGE: knok <level> <message> [options]
LEVELS: whisper, nudge, knock, break
```

| Flag | Description |
|------|-------------|
| `--title <string>` | Alert title (defaults to the message) |
| `--tts` | Speak the message via text-to-speech |
| `--action <label:id[:url]>` | Add a button. Repeatable. |
| `--ttl <int>` | Auto-dismiss after N seconds |
| `--icon <string>` | SF Symbol name (e.g. `bolt.fill`) |
| `--color <string>` | Hex accent color (e.g. `#A855F7`) |

**Exit codes:** `0` = action clicked · `1` = dismissed · `2` = timed out

```bash
# Use exit codes in scripts
knok knock "Deploy?" --action "Yes:yes" --action "No:no"
if [ $? -eq 0 ]; then
  echo "Approved"
fi
```

## Settings

Click the menu bar icon → Settings:

| Tab | Options |
|-----|---------|
| **Sounds** | Global toggle, volume, per-level sound selection |
| **Speech** | TTS toggle, voice, speed |
| **Appearance** | Font size (small / medium / large) |
| **Behavior** | Show in all Spaces, per-level auto-dismiss, launch at login |
| **Network** | HTTP server toggle, port, auth token, bind address |

The menu bar popover shows a history of recent alerts with level, response, and timestamp.

## Security

- **No telemetry. No analytics. No phone-home.** Zero data collection. Alert history lives in memory only.
- **Localhost by default.** The HTTP server binds to `127.0.0.1`. Remote access requires explicit opt-in via Tailscale IP — never exposed on local WiFi or public networks.
- **Socket secured.** `~/.knok/knok.sock` is `chmod 0600`, parent directory is `0700`. Only your user can connect.
- **Signed and notarized.** Code-signed with Developer ID, notarized by Apple, auto-updates verified with EdDSA signatures via Sparkle.

## Building from Source

For contributors or if you prefer building yourself:

```bash
git clone https://github.com/TomasWard1/knok.git
cd knok
swift build -c release
swift test
```

Requires macOS 13+, Swift 6.0+, Xcode 16+.

## License

MIT — see [LICENSE](LICENSE).
