# Tor Windows AutoInstaller

A zero-touch Windows installer that turns Tor into a **permanent, self-healing background service** — no manual configuration, no bridge-fiddling, no babysitting after reboots.

Built for environments where a machine needs a working Tor SOCKS proxy at all times (e.g. behind aggressive DPI/censorship) but the person using it isn't expected to be technical, and the machine may have nothing pre-installed.

> Repo: [github.com/rezabazzi](https://github.com/rezabazzi) — rename this repo to whatever you like (`tor-windows-autoinstaller` suggested).

---

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Using the Proxy](#using-the-proxy)
- [Bridges — Fully Automatic](#bridges--fully-automatic)
- [Configuration Reference](#configuration-reference)
- [Logs & Troubleshooting](#logs--troubleshooting)
- [Uninstalling](#uninstalling)
- [Project Structure](#project-structure)
- [Building the Installer](#building-the-installer)
- [Security & Privacy Notes](#security--privacy-notes)
- [Known Limitations](#known-limitations)
- [License](#license)

---

## Features

- **One-click, fully automatic install.** Run the `.exe`, approve the UAC prompt, done. No dialogs to fill in, no bridge lines to paste.
- **Runs as a real Windows service** (via [NSSM](https://nssm.cc/)) — starts on boot, restarts on crash, no logged-in user required.
- **Real health verification, not a fake success message.** The installer doesn't trust "service shows RUNNING" (NSSM's wrapper process comes up instantly regardless of whether `tor.exe` itself is alive) — it polls for an actual `tor.exe` process *and* a `Bootstrapped 100%` line in Tor's own log before declaring success.
- **Self-healing bridge activation.** A scheduled watchdog task decides on its own whether direct Tor connections are working; if they're stuck for ~15 minutes it automatically switches on a bridge configuration and restarts the service — no manual `.conf` renaming.
- **Anti-thrashing guard.** If bridges are already on and still failing, the watchdog logs a single alert and stops auto-restarting instead of looping forever against dead bridges.
- **Antivirus-quarantine aware.** Detects the classic "AV silently zeroes out `tor.exe`/`lyrebird.exe`/`nssm.exe` on a clean machine" failure mode and reports it clearly instead of failing silently. Also makes a best-effort Windows Defender exclusion request for the install folder.
- **Idempotent everywhere.** The install script, the service config, and the firewall rule can all be re-applied safely at any time without creating duplicates or breaking an existing setup.
- **Clean uninstall.** Removes the service, the firewall rule, and the scheduled task — nothing left behind.
- **Full audit trail.** Every step is logged (`install.log`, `autobridge.log`, `service-stdout.log`, `service-stderr.log`, Tor's own `tor-notice.log`), so failures are diagnosable instead of "it just didn't work."

---

## How It Works

```
Tor-Installer-Setup.exe   (Inno Setup)
        │
        ├─ copies tor.exe, nssm.exe, lyrebird.exe, torrc, PowerShell scripts
        │
        └─ runs Setup-TorService.ps1
                 │
                 ├─ verifies no file was AV-quarantined (0-byte check)
                 ├─ requests a Defender exclusion (best-effort)
                 ├─ installs + configures TorService via NSSM
                 ├─ opens the outbound firewall rule
                 ├─ registers the TorAutoBridge-Watchdog scheduled task
                 ├─ starts the service
                 └─ polls for a REAL bootstrap (tor.exe alive + "Bootstrapped 100%")

TorAutoBridge-Watchdog.ps1   (Scheduled Task — every 5 min + at boot)
        │
        ├─ healthy? → do nothing
        ├─ stuck ~15 min, bridges OFF?  → activate bridges.d\*.conf.sample, restart service
        └─ stuck ~15 min, bridges ON already? → log one alert, stop auto-restarting
```

The SOCKS proxy is always available at `127.0.0.1:9050` once the service is running — direct or via bridge, transparently.

---

## Requirements

- Windows 10 or 11, 64-bit
- Administrator rights to install (the installer requests elevation automatically)
- Nothing else — the installer is self-contained (Tor binary, NSSM, and the obfs4/webtunnel pluggable transport all ship inside it)

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

- `bridges.d\` starts empty (or with one inert `*.conf.sample` fallback) — Tor connects directly by default.
- **`TorAutoBridge-Watchdog`** (installed automatically as a Scheduled Task) checks `tor-notice.log` every 5 minutes.
- If the direct connection hasn't bootstrapped for ~15 minutes, it activates the first available `bridges.d\*.conf.sample` (strips the `.sample` extension) and restarts the service — automatically.
- If bridges are already active and it's *still* stuck 15 minutes later, it logs one alert and stops touching the service, so it never restart-loops against bridges that are simply dead. At that point the fix is a human dropping in fresh bridge lines (bridges age out — get current ones from [bridges.torproject.org](https://bridges.torproject.org/)).

Manual override is always available: activate/remove a `.conf` yourself and run `nssm restart TorService` any time — the watchdog only acts after ~15 minutes of a stuck bootstrap, so it won't fight a manual change.

---

## Configuration Reference

| Setting | Where | Default |
|---|---|---|
| SOCKS listen address | `torrc` → `SocksPort` | `127.0.0.1:9050` (loopback only) |
| Who's allowed to connect | `torrc` → `SocksPolicy` | loopback only — **must explicitly include `127.0.0.1/32`**, since a loopback-bound `SocksPort` makes every client appear as `127.0.0.1` |
| Bridge configs | `bridges.d\*.conf` | none active by default; `*.conf.sample` files are inert fallbacks |
| Watchdog interval | `Watchdog-TorAutoBridge.ps1` → Scheduled Task trigger | every 5 minutes + at boot |
| Stuck-bootstrap threshold | `Watchdog-TorAutoBridge.ps1` → `$FailThreshold` | 3 checks (~15 min) |
| Service auto-restart on crash | NSSM `AppExit` | `Default Restart`, 5s delay |
| Logs directory | `{install dir}\logs\` | — |

To share the proxy on the LAN instead of loopback-only, change `SocksPort` in `torrc` to `0.0.0.0:9050` — only then do real `192.168.x.x` client addresses become visible to the `SocksPolicy` LAN rule.

---

## Logs & Troubleshooting

| File | What it tells you |
|---|---|
| `logs\install.log` | Installer run: file checks, NSSM install/config, firewall rule, scheduled task registration, initial health check |
| `logs\autobridge.log` | Watchdog decisions: healthy/stuck counts, bridge activations, stale-bridge alerts |
| `logs\service-stdout.log` / `service-stderr.log` | Raw output from the wrapped `tor.exe` process (via NSSM) |
| `logs\tor-notice.log` | Tor's own log — bootstrap percentage, SOCKS connection denials, bridge/circuit errors |

Common symptoms:

- **"Denying socks connection from untrusted address 127.0.0.1"** in `tor-notice.log` → `SocksPolicy` in `torrc` doesn't explicitly accept `127.0.0.1/32`. Fix the policy and restart the service.
- **Files exist but are 0 bytes right after install** → antivirus quarantined them. Add the install folder as an AV exclusion and re-run the installer.
- **Service shows "Running" but nothing actually connects** → check `service-stderr.log` and `tor-notice.log` for the real reason `tor.exe` isn't functioning; NSSM's wrapper being "Running" doesn't guarantee `tor.exe` is healthy.

---

## Uninstalling

Run the uninstaller from **Settings → Apps**, or `unins000.exe` in the install folder. It removes:

- The `TorService` Windows service
- The outbound firewall rule
- The `TorAutoBridge-Watchdog` scheduled task
- All installed files

---

## Project Structure

```
Tor-Installer.iss              # Inno Setup script — packaging, [Files], [Run], uninstall cleanup
Setup-TorService.ps1           # Post-install: NSSM service, firewall rule, watchdog registration, real health check
Watchdog-TorAutoBridge.ps1     # Scheduled Task: automatic bridge decision + activation
Source/
  ├─ tor.exe                   # Tor client (Expert Bundle)
  ├─ nssm.exe                  # Service wrapper
  ├─ torrc                     # Tor config (SocksPort, SocksPolicy, %include bridges.d)
  ├─ PluggableTransports/
  │    └─ lyrebird.exe         # obfs4 / webtunnel pluggable transport binary
  └─ bridges.d/
       ├─ README.txt           # Bridge format + how auto-activation works
       └─ mordad-bridges.conf.sample   # Inert example bridge set
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
- No telemetry, no phone-home. All logging stays local in `{app}\logs\`.
- The Defender exclusion request is best-effort and non-fatal — it will silently no-op on managed/enterprise machines where Defender policy is locked down, or where Tamper Protection is enabled.
- This project doesn't route any application through Tor automatically — you decide what uses the proxy, and only that traffic goes through it.

---

## Known Limitations

- The watchdog can only **switch between** "no bridges" and whatever `bridges.d\*.conf.sample` files already exist on disk — it cannot discover or fetch brand-new bridges on its own (that would itself require a working connection first). Keeping at least one current bridge sample on disk is still a manual, periodic task.
- Bridge lines age out over time as relays get blocked or rotated; refresh `bridges.d\*.conf.sample` from [bridges.torproject.org](https://bridges.torproject.org/) periodically.
- Tested on Windows 10/11 64-bit only.

---

## License

Choose one and drop it in `LICENSE` — MIT is a reasonable default for a project like this if you want it maximally reusable:

```
MIT License

Copyright (c) 2026 Reza Bazzi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Quick Summary

This project is a fully automatic Windows installer that turns Tor into a permanent, self-healing background service — no manual configuration and no user intervention required.

**Key features:**
- One-click install, no forms or settings to fill in
- Runs as a real Windows service, always in the background, even after reboots
- Real connection health verification (not just the service's "Running" status)
- Automatic bridge activation when the direct connection is blocked — no manual config editing
- Detects when antivirus software has quarantined a required file
- Clean, complete removal on uninstall (service, firewall rule, scheduled task)
- Full logging at every step for easy troubleshooting

Full technical details and the Firefox/Telegram setup guide are in the sections above.
