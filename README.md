# Tor Windows AutoInstaller

A zero-touch Windows installer that turns Tor into a **permanent, self-healing background service** — no manual configuration, no bridge-fiddling, no babysitting after reboots. **v2.0 now includes full bridge provider support (obfs4, webtunnel, snowflake, meek, conjure), a real-time WebSocket API, and a browser dashboard on port 8383.**

[![CI (PSScriptAnalyzer)](https://github.com/rezabazzi/tor-windows-autoinstaller/actions/workflows/powershell-lint.yml/badge.svg)](https://github.com/rezabazzi/tor-windows-autoinstaller/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Built for environments where a machine needs a working Tor SOCKS proxy at all times (e.g. behind aggressive DPI/censorship) but the person using it isn't expected to be technical, and the machine may have nothing pre-installed.

Quick links
- Repository: https://github.com/rezabazzi/tor-windows-autoinstaller
- Issues: https://github.com/rezabazzi/tor-windows-autoinstaller/issues
- Pull Requests: https://github.com/rezabazzi/tor-windows-autoinstaller/pulls
- Latest release: https://github.com/rezabazzi/tor-windows-autoinstaller/releases

---

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Using the Proxy](#using-the-proxy)
- [Bridges — Fully Automatic](#bridges--fully-automatic)
- [Supported Transports](#supported-transports)
- [WebSocket API](#websocket-api)
- [Web Dashboard](#web-dashboard)
- [Configuration Reference](#configuration-reference)
- [Logs & Troubleshooting](#logs--troubleshooting)
- [Uninstalling](#uninstalling)
- [Project Structure](#project-structure)
- [Building the Installer](#building-the-installer)
- [Security & Privacy Notes](#security--privacy-notes)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)
- [Maintainers & Contacts](#maintainers--contacts)

---

## Features

- **One-click, fully automatic install.** Run the `.exe`, approve the UAC prompt, done. No dialogs to fill in, no bridge lines to paste.
- **Runs as a real Windows service** (via [NSSM](https://nssm.cc/)) — starts on boot, restarts on crash, no logged-in user required.
- **Real health verification, not a fake success message.** The installer doesn't trust "service shows RUNNING" — it polls for an actual `tor.exe` process *and* a `Bootstrapped 100%` line in Tor's own log before declaring success.
- **Self-healing bridge activation.** A scheduled watchdog task decides on its own whether direct Tor connections are working; if they're stuck for ~15 minutes it automatically switches on a bridge configuration and restarts the service.
- **All bridge providers supported.** obfs4, webtunnel, snowflake, meek, and conjure — the watchdog auto-activates whichever bridge config exists on disk.
- **Anti-thrashing guard.** If bridges are already on and still failing, the watchdog logs a single alert and stops auto-restarting.
- **Antivirus-quarantine aware.** Detects AV-quarantined files and reports clearly.
- **Idempotent everywhere.** Safe to re-run any time without duplicates.
- **Clean uninstall.** Removes services, firewall rules, scheduled tasks — nothing left behind.
- **Full audit trail.** Every step logged locally.
- **🔌 Real-time WebSocket API.** Connect to `ws://127.0.0.1:9052/ws` for live status, circuit info, log streaming, and control commands.
- **🌐 Browser Dashboard (v2.0).** Open `http://127.0.0.1:8383` for a real-time monitoring UI.

---

## How It Works

```
Tor-Installer-Setup.exe   (Inno Setup)
        │
        ├─ copies tor.exe, nssm.exe, PT binaries, torrc, scripts
        │
        └─ runs Setup-TorService.ps1
                 │
                 ├─ verifies no file was AV-quarantined (0-byte check)
                 ├─ requests a Defender exclusion (best-effort)
                 ├─ installs + configures TorService via NSSM
                 ├─ opens the outbound firewall rule
                 ├─ registers the TorAutoBridge-Watchdog scheduled task
                 ├─ installs TorApiService (WebSocket API on 9052)
                 ├─ installs TorDashboardService (Web UI on 8383)
                 ├─ starts all services
                 └─ polls for a REAL bootstrap (tor.exe alive + "Bootstrapped 100%")

TorAutoBridge-Watchdog.ps1   (Scheduled Task — every 5 min + at boot)
        │
        ├─ healthy? → do nothing
        ├─ stuck ~15 min, bridges OFF?  → activate bridges.d\*.conf.sample, restart service
        └─ stuck ~15 min, bridges ON already? → log one alert, stop auto-restarting

TorApiServer.ps1   (NSSM service — runs continuously)
        │
        ├─ WebSocket server on 127.0.0.1:9052
        ├─ Connects to Tor ControlPort (9051)
        ├─ Periodic status push to all connected clients
        ├─ Commands: status, restart, newnym, circuit, log
        └─ REST endpoint: GET /api/status

DashboardServer.ps1   (NSSM service — runs continuously)
        │
        └─ HTTP server on 127.0.0.1:8383 serving WebDashboard.html
```

The SOCKS proxy is always available at `127.0.0.1:9050` once the service is running — direct or via bridge, transparently.

---

## Requirements

- Windows 10 or 11, 64-bit
- Administrator rights to install (the installer requests elevation automatically)
- Nothing else — the installer is self-contained (Tor binary, NSSM, and all pluggable transports ship inside it)

---

## Installation

1. Download `Tor-Installer-Setup.exe` from [Releases](../../releases).
2. Run it. Approve the UAC prompt.
3. That's it. The SOCKS proxy is live at `127.0.0.1:9050` within a few seconds, the WebSocket API is on `9052`, and the dashboard is at `http://127.0.0.1:8383`.

No settings screens, no bridge configuration, no restart required afterward.

---

## Using the Proxy

The installer only starts the proxy — it doesn't reroute any application automatically. Point whatever you want through Tor at `127.0.0.1:9050` (SOCKS5).

### Firefox

1. Menu → Settings → General → Network Settings → Settings
2. Select **Manual proxy configuration**
3. SOCKS Host: `127.0.0.1`, Port: `9050`, type **SOCKS v5**
4. Check **"Proxy DNS when using SOCKS v5"**
5. OK

### Telegram Desktop

1. Menu → Settings → Advanced → Connection type
2. Use custom proxy → Add proxy
3. Type: **SOCKS5**, Server: `127.0.0.1`, Port: `9050`
4. Save and enable

---

## Bridges — Fully Automatic

Most censorship-circumvention Tor setups require someone to manually paste bridge lines into a config file whenever the direct connection gets blocked. This project removes that step entirely.

- `bridges.d\` starts with inert `*.conf.sample` fallbacks — Tor connects directly by default.
- **`TorAutoBridge-Watchdog`** (installed automatically as a Scheduled Task) checks `tor-notice.log` every 5 minutes.
- If the direct connection hasn't bootstrapped for ~15 minutes, it activates the first available `bridges.d\*.conf.sample` (strips the `.sample` extension) and restarts the service — automatically.
- If bridges are already active and it's *still* stuck 15 minutes later, it logs one alert and stops touching the service, so it never restart-loops.

---

## Supported Transports

This project supports **all major Tor pluggable transports**:

| Transport | Binary | Description |
|-----------|--------|-------------|
| **obfs4** | `lyrebird.exe` | Scrambles traffic to look like random noise. Most widely used. |
| **webtunnel** | `lyrebird.exe` | Makes Tor traffic look like regular HTTPS traffic. Effective against DPI. |
| **snowflake** | `snowflake-client.exe` | Uses WebRTC to connect through volunteer browser proxies. Effective when brokers are not blocked. |
| **meek** | `meek-client.exe` | Uses domain fronting to make connections appear to go to popular CDN domains (Azure, Amazon, Google). |
| **conjure** | `conjure-client.exe` | Uses phantom IP addresses to circumvent censorship. |

The watchdog prioritizes bridges in this order: obfs4 → webtunnel → snowflake → meek → conjure. This ordering balances reliability with circumvention capability.

### Getting Bridge Lines

Get fresh bridge lines from [bridges.torproject.org](https://bridges.torproject.org/) or via email/tox. Replace the sample bridge configs with your own and rename them (drop `.sample`) to activate.

---

## WebSocket API

**v2.0 feature.** The WebSocket API server provides real-time monitoring and control of your Tor service through a simple JSON protocol.

### Quick Start (Browser)

```javascript
const ws = new WebSocket('ws://127.0.0.1:9052/ws');

ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    console.log(msg.type, msg.data);
};

ws.send(JSON.stringify({ cmd: 'status' }));
ws.send(JSON.stringify({ cmd: 'newnym' }));
ws.send(JSON.stringify({ cmd: 'restart' }));
ws.send(JSON.stringify({ cmd: 'circuit' }));
ws.send(JSON.stringify({ cmd: 'log', tail: 50 }));
```

### REST API

```bash
# PowerShell
Invoke-RestMethod -Uri 'http://127.0.0.1:9052/api/status'

# curl
curl http://127.0.0.1:9052/api/status
```

### Protocol

**Client → Server Commands:**

| Command | Description |
|---------|-------------|
| `{"cmd":"status"}` | Get current Tor status (version, uptime, traffic, memory) |
| `{"cmd":"restart"}` | Restart the Tor service |
| `{"cmd":"newnym"}` | Request a new Tor identity (new circuit) |
| `{"cmd":"circuit"}` | Get active circuit information |
| `{"cmd":"log","tail":50}` | Get the last N lines of the Tor notice log |

**Server → Client Events:**

| Event | Description |
|-------|-------------|
| `{"type":"status","data":{...}}` | Periodic status push (every 10s by default) |
| `{"type":"log","data":"..."}` | Log line events |
| `{"type":"error","data":"..."}` | Error responses |

---

## Web Dashboard

**v2.0 feature.** Open `http://127.0.0.1:8383` in your browser for a real-time monitoring dashboard.

Features:
- Live Tor status (running, PID, memory, uptime, traffic)
- WebSocket connection with auto-reconnect
- Command buttons: Refresh, New Identity, Restart, Circuit Info, View Logs
- Event log with color-coded messages
- Responsive dark-themed UI

---

## Configuration Reference

| Setting | Where | Default |
|---|---|---|
| SOCKS listen address | `torrc` → `SocksPort` | `127.0.0.1:9050` (loopback only) |
| Tor ControlPort | `torrc` → `ControlPort` | `127.0.0.1:9051` (loopback only) |
| WebSocket API port | `TorApiServer.ps1` | `127.0.0.1:9052` (loopback only) |
| Web Dashboard port | `DashboardServer.ps1` | `127.0.0.1:8383` (loopback only) |
| Who's allowed to connect | `torrc` → `SocksPolicy` | loopback only |
| Bridge configs | `bridges.d\*.conf` | none active by default |
| Watchdog interval | Scheduled Task trigger | every 5 min + at boot |
| Stuck-bootstrap threshold | `$FailThreshold` | 3 checks (~15 min) |
| Status push interval | `TorApiServer.ps1` | 10 seconds |
| Service auto-restart on crash | NSSM `AppExit` | `Default Restart`, 5s delay |

To share the proxy on the LAN, change `SocksPort` in `torrc` to `0.0.0.0:9050`.

---

## Logs & Troubleshooting

| File | What it tells you |
|---|---|
| `logs\install.log` | Installer run: file checks, NSSM install/config, firewall rule, scheduled task registration |
| `logs\autobridge.log` | Watchdog decisions: healthy/stuck counts, bridge activations, stale-bridge alerts |
| `logs\torapi.log` | WebSocket API server events |
| `logs\tor-dashboard.log` | Dashboard server events |
| `logs\service-stdout.log` / `service-stderr.log` | Raw output from the wrapped `tor.exe` process |
| `logs\tor-notice.log` | Tor's own log — bootstrap percentage, SOCKS connection denials, bridge/circuit errors |
| `logs\snowflake-client.log` | Snowflake transport log (if enabled) |

Common symptoms:

- **"Denying socks connection from untrusted address 127.0.0.1"** → `SocksPolicy` in `torrc` doesn't explicitly accept `127.0.0.1/32`. Fix the policy and restart the service.
- **Files exist but are 0 bytes right after install** → antivirus quarantined them. Add the install folder as an AV exclusion and re-run the installer.
- **Service shows "Running" but nothing actually connects** → check `service-stderr.log` and `tor-notice.log` for the real reason.
- **WebSocket API not responding** → verify `TorApiService` is running via `Get-Service TorApiService` or check `logs\torapi.log`.
- **Dashboard not loading** → verify `TorDashboardService` is running or open `http://127.0.0.1:8383` in your browser.
- **Snowflake not working** → check `logs\snowflake-client.log` for broker connectivity issues.

---

## Uninstalling

Run the uninstaller from **Settings → Apps**, or `unins000.exe` in the install folder. It removes:

- The `TorService` Windows service
- The `TorApiService` (WebSocket API)
- The `TorDashboardService` (Web Dashboard)
- The outbound firewall rule
- The `TorAutoBridge-Watchdog` scheduled task
- All installed files

---

## Project Structure

```
Tor-Installer.iss              # Inno Setup script — packaging, [Files], [Run], uninstall cleanup
Setup-TorService.ps1           # Post-install: NSSM service, firewall rule, watchdog, API server, dashboard
Watchdog-TorAutoBridge.ps1     # Scheduled Task: automatic bridge decision + activation (multi-transport)
TorApiServer.ps1               # WebSocket API server — real-time monitoring and control
DashboardServer.ps1            # HTTP server for web dashboard (port 8383)
WebDashboard.html              # Browser-based monitoring UI
TorApiClient.ps1               # Example WebSocket client
PSScriptAnalyzerSettings.psd1  # Lint rule config
Source/
  ├─ tor.exe                   # Tor client (Expert Bundle)
  ├─ nssm.exe                  # Service wrapper
  ├─ *.dll                     # Tor dependencies (libssl, libcrypto, libevent, zlib)
  ├─ torrc                     # Tor config (SocksPort, ControlPort, %include bridges.d)
  ├─ PluggableTransports/
  │    ├─ lyrebird.exe          # obfs4 / webtunnel
  │    ├─ snowflake-client.exe  # snowflake
  │    ├─ meek-client.exe       # meek
  │    └─ conjure-client.exe    # conjure
  └─ bridges.d/
       ├─ README.txt            # Bridge format documentation
       ├─ mordad-bridges.conf.sample      # obfs4/webtunnel example
       ├─ snowflake-bridges.conf.sample   # snowflake example
       ├─ meek-bridges.conf.sample        # meek example
       └─ conjure-bridges.conf.sample     # conjure example
```

At install time this deploys to `{app}` (default `C:\Tor`), plus `logs\` and `data\` directories created automatically.

---

## Building the Installer

Requires [Inno Setup](https://jrsoftware.org/isinfo.php) 6.x and the Tor Expert Bundle binaries.

1. Install Inno Setup from https://jrsoftware.org/
2. Download the Tor Expert Bundle from https://www.torproject.org/download/tor/
3. Place `tor.exe`, `*.dll`, `geoip`, `geoip6`, `PluggableTransports\lyrebird.exe`, `PluggableTransports\snowflake-client.exe`, `PluggableTransports\meek-client.exe`, `PluggableTransports\conjure-client.exe`, and `nssm.exe` in `Source\`
4. Run:
   ```
   ISCC.exe Tor-Installer.iss
   ```
5. Output: `Output\Tor-Installer-Setup.exe`

---

## Security & Privacy Notes

- The proxy binds to `127.0.0.1` only by default — it is not exposed to the network.
- The WebSocket API and Dashboard also bind to `127.0.0.1` only.
- No telemetry, no phone-home. All logging stays local.
- The Defender exclusion request is best-effort and non-fatal.
- This project doesn't route any application through Tor automatically — you decide what uses the proxy.

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure process.

---

## Known Limitations

- The watchdog can only switch between "no bridges" and whatever `bridges.d\*.conf.sample` files already exist on disk — it cannot discover or fetch brand-new bridges on its own.
- Bridge lines age out over time; refresh `bridges.d\*.conf.sample` from [bridges.torproject.org](https://bridges.torproject.org/) periodically.
- Tested on Windows 10/11 64-bit only.
- Snowflake requires access to the broker server — if the broker is blocked, Snowflake will not work.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, lint requirements, and how to open a PR.

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## Maintainers & Contacts

- Repo owner: [@rezabazzi](https://github.com/rezabazzi)
- Bugs/features: open an issue using the provided templates
- Security issues: see [SECURITY.md](SECURITY.md)

---

## Quick Summary

This project is a fully automatic Windows installer that turns Tor into a permanent, self-healing background service.

**Key features:**
- One-click install, no forms or settings to fill in
- Runs as a real Windows service, always in the background, even after reboots
- Real connection health verification
- Automatic bridge activation when the direct connection is blocked
- Supports all major transports: obfs4, webtunnel, snowflake, meek, conjure
- Detects when antivirus software has quarantined a required file
- 🔌 WebSocket API for real-time monitoring and control
- 🌐 Browser dashboard on port 8383
- Clean, complete removal on uninstall
- Full logging at every step
