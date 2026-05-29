# Money-Making-Monitor

A cross-platform Bash monitoring script that keeps your passive income services—**EarnApp**, **Honeygain**, and **Grass**—running around the clock. Get notified on **Discord** the instant a service goes down.

## Quick Start

```bash
# 1. Configure services, webhook, and settings
bash install.sh

# 2. Start monitoring
bash monitor.sh
```

## Features

- **Cross-platform** — Works on Linux, macOS, and Windows (via Git Bash / MSYS2)
- **Interactive CLI** — Navigate with arrow keys, no external UI libraries needed
- **Discord webhook alerts** — Notifies you when services go down or recover
- **Smart notifications** — Alerts once per outage, once per recovery (no spam)
- **Selective monitoring** — Toggle each service on/off via the install wizard
- **Auto-restart** — Automatically restarts stopped services with configurable cooldown and retry limits
- **Docker-aware** — Monitors Honeygain and Grass as Docker containers on Linux
- **Persistent config** — Settings saved to a platform-appropriate config file
- **Full uninstall** — Clean removal of config and log files

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Setup wizard — select services, paste Discord webhook, configure settings, or uninstall |
| `monitor.sh` | Main monitor — live dashboard, continuous monitoring, auto-restart |

## Install Script (`install.sh`)

Interactive setup wizard with four main options:

1. **Install / Configure** — Runs through a three-step wizard:
   - **Service Selection** — Multi-select checkboxes with `[Space]` to toggle EarnApp, Honeygain, and Grass
   - **Discord Webhook** — Paste your webhook URL, with auto-validation and a test message
   - **Settings** — Adjust monitor interval, cooldown, max restart attempts, auto-restart toggle
2. **View Current Configuration** — Displays the saved config file
3. **Test Discord Webhook** — Sends a test embed to your Discord channel
4. **Uninstall** — Removes all config and log files (requires typing `UNINSTALL` to confirm)

## Monitor Script (`monitor.sh`)

Reads the config created by `install.sh` and offers:

1. **Live Dashboard** — Auto-refreshing status view with CPU/memory stats
2. **One-Time Status Check** — Quick snapshot of all services
3. **Continuous Monitoring** — Auto-restart loop with Discord alerts
4. **Restart All Stopped** — Batch restart anything that's down
5. **Restart Individual** — Sub-menu to pick a specific service
6. **View Logs** — Color-coded log viewer
7. **Settings** — Runtime adjustments

## Service Detection

| Service   | Windows            | macOS       | Linux                            |
|-----------|--------------------|-------------|----------------------------------|
| EarnApp   | `earnapp.exe`      | `EarnApp`   | Process / CLI / systemd          |
| Honeygain | `Honeygain.exe`    | `Honeygain` | Docker (`honeygain/honeygain`)   |
| Grass     | `Grass.exe`        | `Grass`     | Docker (`mrcolorrain/grass`)     |

## Discord Notifications

When a monitored service goes down, the monitor sends a rich embed to your Discord channel:

- 🔴 **Service DOWN** — Sent once when a service stops running
- 🟢 **Service RECOVERED** — Sent once when a service comes back online

Notifications include: service name, status, hostname, OS, and timestamp.

## Keyboard Controls

| Key       | Action                   |
|-----------|--------------------------|
| `↑` / `↓` | Navigate menu            |
| `Space`   | Toggle checkbox (install.sh) |
| `Enter`   | Select / confirm         |
| `Esc`     | Exit / go back           |
| `Q`       | Stop live dashboard or continuous monitoring |

## Configuration

The config file is stored at a platform-appropriate path:

| OS      | Config Path                                       | Log Path                                       |
|---------|---------------------------------------------------|-------------------------------------------------|
| Linux   | `~/.config/money-monitor/config.conf`             | `~/.local/share/money-monitor/monitor.log`      |
| macOS   | `~/.config/money-monitor/config.conf`             | `~/Library/Logs/money-monitor/monitor.log`      |
| Windows | `%APPDATA%/money-monitor/config.conf`             | `%APPDATA%/money-monitor/logs/monitor.log`      |

### Config File Format

```ini
# Services to monitor (true/false)
MONITOR_EARNAPP=true
MONITOR_HONEYGAIN=true
MONITOR_GRASS=false

# Discord webhook URL
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...

# Monitoring settings
MONITOR_INTERVAL=30
RESTART_COOLDOWN=60
MAX_RESTART_ATTEMPTS=3
AUTO_RESTART_ENABLED=true
```

## Requirements

- **Bash 4+** (for associative arrays)
- **Git Bash** or **MSYS2** on Windows
- **Docker** on Linux (for Honeygain and Grass container monitoring)
- **curl** (for Discord webhook notifications)
- Standard Unix utilities: `pgrep`, `ps`, `tput`, `date`, `tail`

## License

See [LICENSE](LICENSE) for details.
