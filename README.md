# Tor Windows AutoInstaller

A zero-touch Windows installer that turns Tor into a **permanent, self-healing background service** — no manual configuration, no bridge-fiddling, no babysitting after reboots. **v2.0 now includes Snowflake transport support and a real-time WebSocket monitoring/control API.**

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
- [WebSocket API](#websocket-api) (v2.0)
- [Snowflake Transport](#snowflake-transport) (v2.0)
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
- **Real health verification, not a fake success message.** The installer doesn't trust "service shows RUNNING" (NSSM's wrapper process comes up instantly regardless of whether `tor.exe` itself is alive) — it polls for an actual `tor.exe` process *and* a `Bootstrapped 100%` line in Tor's own log before declaring success.
- **Self-healing bridge activation.** A scheduled watchdog task decides on its own whether direct Tor connections are working; if they're stuck for ~15 minutes it automatically switches on a bridge configuration and restarts the service — no manual `.conf` renaming.
- **Multi-transport support.** Supports obfs4, webtunnel, and **Snowflake** (v2.0) pluggable transports — the watchdog auto-activates whichever bridge config exists on disk.
- **Anti-thrashing guard.** If bridges are already on and still failing, the watchdog logs a single alert and stops auto-restarting instead of looping forever against dead bridges.
- **Antivirus-quarantine aware.** Detects the classic "AV silently zeroes out `tor.exe`/`lyrebird.exe`/`snowflake-client.exe`/`nssm.exe` on a clean machine" failure mode and reports it clearly instead of failing silently. Also makes a best-effort Windows Defender exclusion request for the install folder.
- **Idempotent everywhere.** The install script, the service config, and the firewall rule can all be re-applied safely at any time without creating duplicates or breaking an existing setup.
- **Clean uninstall.** Removes the service, the firewall rule, and the scheduled task — nothing left behind.
- **Full audit trail.** Every step is logged (`install.log`, `autobridge.log`, `torapi.log`, `service-stdout.log`, `service-stderr.log`, Tor's own `tor-notice.log`, `snowflake-client.log`), so failures are diagnosable instead of "it just didn't work."
- **🔌 Real-time WebSocket API (v2.0).** Connect to `ws://127.0.0.1:9052/ws` for live status monitoring, circuit info, log streaming, and Tor control commands (restart, newnym, etc.). REST endpoint at `GET /api/status`.

---

## How It Works

```
Tor-Installer-Setup.exe   (Inno Setup)
        │
        ├─ copies tor.exe, nssm.exe, lyrebird.exe, snowflake-client.exe, torrc, PowerShell scripts
        │
        └─ runs Setup-TorService.ps1
                 │
                 ├─ verifies no file was AV-quarantined (0-byte check)
                 ├─ requests a Defender exclusion (best-effort)
                 ├─ installs + configures TorService via NSSM
                 ├─ opens the outbound firewall rule
                 ├─ registers the TorAutoBridge-Watchdog scheduled task
                 ├─ starts the TorApiService (WebSocket API)
                 ├─ starts the service
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
```

The SOCKS proxy is always available at `127.0.0.1:9050` once the service is running — direct or via bridge, transparently.

---

## Requirements

- Windows 10 or 11, 64-bit
- Administrator rights to install (the installer requests elevation automatically)
- Nothing else — the installer is self-contained (Tor binary, NSSM, and pluggable transports all ship inside it)

---

## Installation

1. Download `Tor-Installer-Setup.exe` from [Releases](../../releases).
2. Run it. Approve the "Do you want to allow this app to make changes to your device?" prompt.
3. That's it. The SOCKS proxy is live at `127.0.0.1:9050` within a few seconds, and stays that way across reboots.

No settings screens, no bridge configuration, no restart required afterward.

---

## Using the Proxy

The installer only starts the proxy — it doesn't reroute any application automatically. Point whatever you want through Tor at `127.0.0.1:9050` (SOCKS5).

### Firefox

1. Menu (☰, top right) → **Settings**
2. Scroll to **General** → **Network Settings** → **Settings...**
3. Select **Manual proxy configuration**
4. Set **SOCKS Host**: `127.0.0.1`, **Port**: `9050`, type **SOCKS v5**
5. Check **"Proxy DNS when using SOCKS v5"** — important, otherwise DNS lookups leak outside Tor
6. OK

### Telegram Desktop (Windows)

1. Menu (☰, top left) → **Settings**
2. **Advanced** → **Connection type**
3. **Use custom proxy** → **Add proxy**
4. Type: **SOCKS5**, Server: `127.0.0.1`, Port: `9050` (leave username/password blank)
5. Save, then enable it from the proxy list

> Since the port only listens on `127.0.0.1`, these settings only work on the machine Tor is installed on — not from phones or other machines on the network (see [Configuration Reference](#configuration-reference) to change that).

---

## Bridges — Fully Automatic

Most censorship-circumvention Tor setups require someone to manually paste bridge lines into a config file whenever the direct connection gets blocked. This project removes that step entirely.

- `bridges.d\` starts empty (or with inert `*.conf.sample` fallbacks) — Tor connects directly by default.
- **`TorAutoBridge-Watchdog`** (installed automatically as a Scheduled Task) checks `tor-notice.log` every 5 minutes.
- If the direct connection hasn't bootstrapped for ~15 minutes, it activates the first available `bridges.d\*.conf.sample` (strips the `.sample` extension) and restarts the service — automatically. The watchdog prioritizes obfs4 first, then webtunnel, then Snowflake.
- If bridges are already active and it's *still* stuck 15 minutes later, it logs one alert and stops touching the service, so it never restart-loops against bridges that are simply dead. At that point the fix is a human dropping in fresh bridge lines (bridges age out — get current ones from [bridges.torproject.org](https://bridges.torproject.org/)).

Manual override is always available: activate/remove a `.conf` yourself and run `nssm restart TorService` any time — the watchdog only acts after ~15 minutes of a stuck bootstrap.

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

// Request status
ws.send(JSON.stringify({ cmd: 'status' }));

// Request new identity
ws.send(JSON.stringify({ cmd: 'newnym' }));

// Restart Tor service
ws.send(JSON.stringify({ cmd: 'restart' }));

// Get circuit info
ws.send(JSON.stringify({ cmd: 'circuit' }));

// Get last 50 log lines
ws.send(JSON.stringify({ cmd: 'log', tail: 50 }));
```

### Quick Start (PowerShell)

```powershell
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
$ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None).Wait()

# Send a command
$cmd = '{"cmd":"status"}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetBytes($_) }
$ws.SendAsync([System.ArraySegment[byte]]::New($cmd), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

# Receive response
$buffer = New-Object byte[] 4096
$result = $ws.ReceiveAsync([System.ArraySegment[byte]]::New($buffer), [System.Threading.CancellationToken]::None).Result
$response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$response | ConvertFrom-Json
```

### REST API

For simple one-shot queries, use the HTTP endpoint:

```powershell
# PowerShell
Invoke-RestMethod -Uri 'http://127.0.0.1:9052/api/status'
```

```bash
# curl
curl http://127.0.0.1:9052/api/status
```

Response:
```json
{
    "timestamp": "2026-09-24T12:00:00.0000000Z",
    "running": true,
    "pid": 1234,
    "version": "0.4.8.12",
    "uptime": 3600,
    "memMB": 45.23,
    "bytesRead": 1048576,
    "bytesWritten": 524288,
    "bootstrapped": true
}
```

### WebSocket Protocol

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

## Snowflake Transport

**v2.0 feature.** [Snowflake](https://snowflake.torproject.org/) is a pluggable transport that uses WebRTC to connect to the Tor network through temporary browser-based proxies. It's effective against deep packet inspection and works even when obfs4/webtunnel bridges are blocked.

### Setup

1. Download `snowflake-client.exe` from [anti-censorship/pluggable-transports/snowflake](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake)
2. Place it in the `PluggableTransports\` folder (or use the installer which ships it)
3. A sample bridge config ships as `bridges.d\snowflake-bridges.conf.sample`
4. Get fresh Snowflake bridge lines from [bridges.torproject.org](https://bridges.torproject.org/)
5. The watchdog auto-activates Snowflake bridges when direct connections are stuck

### How It Works

Snowflake uses a broker-based approach:
- The client contacts a broker server to find available Snowflake proxies
- These proxies are run by volunteers via browser extensions or standalone apps
- Traffic is obfuscated as WebRTC video calls, making it hard to detect/block

### Configuration

The sample config (`snowflake-bridges.conf.sample`) includes:
```
UseBridges 1
ClientTransportPlugin snowflake exec PluggableTransports\snowflake-client.exe -log logs/snowflake-client.log
Bridge snowflake <ip>:<port> <fingerprint>
```

The watchdog automatically tries Snowflake bridges after obfs4/webtunnel options.

---

## Configuration Reference

| Setting | Where | Default |
|---|---|---|
| SOCKS listen address | `torrc` → `SocksPort` | `127.0.0.1:9050` (loopback only) |
| Tor ControlPort | `torrc` → `ControlPort` | `127.0.0.1:9051` (loopback only) |
| WebSocket API port | `TorApiServer.ps1` | `127.0.0.1:9052` (loopback only) |
| Who's allowed to connect | `torrc` → `SocksPolicy` | loopback only |
| Bridge configs | `bridges.d\*.conf` | none active by default |
| Watchdog interval | Scheduled Task trigger | every 5 min + at boot |
| Stuck-bootstrap threshold | `$FailThreshold` | 3 checks (~15 min) |
| Status push interval | `TorApiServer.ps1` | 10 seconds |
| Service auto-restart on crash | NSSM `AppExit` | `Default Restart`, 5s delay |

To share the proxy on the LAN instead of loopback-only, change `SocksPort` in `torrc` to `0.0.0.0:9050` — only then do real `192.168.x.x` client addresses become visible to the `SocksPolicy` LAN rule.

---

## Logs & Troubleshooting

| File | What it tells you |
|---|---|
| `logs\install.log` | Installer run: file checks, NSSM install/config, firewall rule, scheduled task registration, initial health check |
| `logs\autobridge.log` | Watchdog decisions: healthy/stuck counts, bridge activations, stale-bridge alerts |
| `logs\torapi.log` | WebSocket API server events |
| `logs\torapi-stdout.log` / `torapi-stderr.log` | Raw output from the API server (via NSSM) |
| `logs\service-stdout.log` / `service-stderr.log` | Raw output from the wrapped `tor.exe` process (via NSSM) |
| `logs\tor-notice.log` | Tor's own log — bootstrap percentage, SOCKS connection denials, bridge/circuit errors |
| `logs\snowflake-client.log` | Snowflake transport log (if enabled) |

Common symptoms:

- **"Denying socks connection from untrusted address 127.0.0.1"** in `tor-notice.log` → `SocksPolicy` in `torrc` doesn't explicitly accept `127.0.0.1/32`. Fix the policy and restart the service.
- **Files exist but are 0 bytes right after install** → antivirus quarantined them. Add the install folder as an AV exclusion and re-run the installer.
- **Service shows "Running" but nothing actually connects** → check `service-stderr.log` and `tor-notice.log` for the real reason `tor.exe` isn't functioning; NSSM's wrapper being "Running" doesn't guarantee `tor.exe` is healthy.
- **WebSocket API not responding** → verify `TorApiService` is running via `Get-Service TorApiService` or check `logs\torapi.log`.
- **Snowflake not working** → check `logs\snowflake-client.log` for broker connectivity issues; the broker may be blocked.

---

## Uninstalling

Run the uninstaller from **Settings → Apps**, or `unins000.exe` in the install folder. It removes:

- The `TorService` Windows service
- The `TorApiService` (WebSocket API, if installed)
- The outbound firewall rule
- The `TorAutoBridge-Watchdog` scheduled task
- All installed files

---

## Project Structure

```
Tor-Installer.iss              # Inno Setup script — packaging, [Files], [Run], uninstall cleanup
Setup-TorService.ps1           # Post-install: NSSM service, firewall rule, watchdog registration, real health check
Watchdog-TorAutoBridge.ps1     # Scheduled Task: automatic bridge decision + activation (multi-transport)
TorApiServer.ps1               # WebSocket API server (v2.0) — real-time monitoring and control
PSScriptAnalyzerSettings.psd1  # Lint rule config used both locally and in CI
Source/
  ├─ tor.exe                   # Tor client (Expert Bundle)
  ├─ nssm.exe                  # Service wrapper
  ├─ torrc                     # Tor config (SocksPort, ControlPort, %include bridges.d)
  ├─ PluggableTransports/
  │    ├─ lyrebird.exe         # obfs4 / webtunnel pluggable transport binary
  │    └─ snowflake-client.exe # Snowflake pluggable transport binary (v2.0)
  └─ bridges.d/
       ├─ README.txt           # Bridge format + how auto-activation works
       ├─ mordad-bridges.conf.sample   # Inert example bridge set (obfs4/webtunnel)
       └─ snowflake-bridges.conf.sample # Inert Snowflake bridge example (v2.0)
```

At install time this deploys to `{app}` (default `C:\Tor`), plus a `logs\` and `data\` directory created automatically.

---

## Building the Installer

Requires [Inno Setup](https://jrsoftware.org/isinfo.php) 6.x.

```
ISCC.exe Tor-Installer.iss
```

Output: `Tor-Installer-Setup.exe` in the compiler's default output directory.

---

## Security & Privacy Notes

- The proxy binds to `127.0.0.1` only by default — it is not exposed to the network unless you explicitly change `SocksPort`.
- The WebSocket API also binds to `127.0.0.1` only — remote clients cannot connect.
- No telemetry, no phone-home. All logging stays local in `{app}\logs\`.
- The Defender exclusion request is best-effort and non-fatal — it will silently no-op on managed/enterprise machines where Defender policy is locked down, or where Tamper Protection is enabled.
- This project doesn't route any application through Tor automatically — you decide what uses the proxy, and only that traffic goes through it.

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure process.

---

## Known Limitations

- The watchdog can only **switch between** "no bridges" and whatever `bridges.d\*.conf.sample` files already exist on disk — it cannot discover or fetch brand-new bridges on its own (that would itself require a working connection first). Keeping at least one current bridge sample on disk is still a manual, periodic task.
- Bridge lines age out over time as relays get blocked or rotated; refresh `bridges.d\*.conf.sample` from [bridges.torproject.org](https://bridges.torproject.org/) periodically.
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
- Security issues: see [SECURITY.md](SECURITY.md) — do not report vulnerabilities in public issues

---

## Quick Summary

This project is a fully automatic Windows installer that turns Tor into a permanent, self-healing background service — no manual configuration and no user intervention required.

**Key features:**
- One-click install, no forms or settings to fill in
- Runs as a real Windows service, always in the background, even after reboots
- Real connection health verification (not just the service's "Running" status)
- Automatic bridge activation when the direct connection is blocked — supports obfs4, webtunnel, and Snowflake transports
- Detects when antivirus software has quarantined a required file
- 🔌 **WebSocket API** for real-time monitoring and control (v2.0)
- **Snowflake transport support** for advanced censorship circumvention (v2.0)
- Clean, complete removal on uninstall (service, firewall rule, scheduled task)
- Full logging at every step for easy troubleshooting
