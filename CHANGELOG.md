# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.0.0] - 2026-09-24

### Added
- **WebSocket API server** (`TorApiServer.ps1`) — real-time monitoring/control
  - WebSocket endpoint on `ws://127.0.0.1:9052/ws`
  - REST endpoint at `GET /api/status`
  - Commands: status, restart, newnym, circuit, log
  - Runs as `TorApiService` via NSSM
- **Browser Dashboard** (`WebDashboard.html` + `DashboardServer.ps1`)
  - Real-time monitoring UI on `http://127.0.0.1:8383`
  - Live status, controls, event log with auto-reconnect
  - Runs as `TorDashboardService` via NSSM
- **All major bridge transports supported**
  - obfs4, webtunnel, snowflake, meek, conjure
  - Sample configs for each in `bridges.d\`
  - Transport binaries in `PluggableTransports\`
- **Multi-transport watchdog** — auto-detects and activates any transport
  - Priority order: obfs4 → webtunnel → snowflake → meek → conjure
- **Tor ControlPort** (9051) for API communication
- **TorApiClient.ps1** — example interactive WebSocket client
- **WebDashboard.html** — dark-themed responsive monitoring UI

### Changed
- `torrc` — relative paths, ControlPort enabled, all transports
- `Setup-TorService.ps1` — installs TorApiService + TorDashboardService
- `Watchdog-TorAutoBridge.ps1` — multi-transport, log rotation handling
- `Tor-Installer.iss` — v2.0 packaging with all new files
- `README.md` — complete rewrite for v2.0
- `PSScriptAnalyzerSettings.psd1` — added PSReviewUnusedParameter exclusion

### Fixed
- Hardcoded absolute paths in `torrc` → relative paths
- Watchdog log rotation handling (offset reset on log shrink)
- PT detection: only one PT required (was requiring both)
- Uninstall now removes TorApiService and TorDashboardService
- CI workflow: pinned to actions/checkout@v4

### New Files
- `TorApiServer.ps1`
- `DashboardServer.ps1`
- `WebDashboard.html`
- `TorApiClient.ps1`
- `Source/bridges.d/meek-bridges.conf.sample`
- `Source/bridges.d/conjure-bridges.conf.sample`
- `Source/PluggableTransports/meek-client.exe`
- `Source/PluggableTransports/conjure-client.exe`

## [0.1.0] - 2026-08-13

### Added
- Initial release skeleton
- Basic Inno Setup installer
- Setup-TorService.ps1 (NSSM service setup)
- Watchdog-TorAutoBridge.ps1 (bridge auto-activation)
- Community files (README, LICENSE, CONTRIBUTING, SECURITY, templates)
- CI workflow (PSScriptAnalyzer)

[2.0.0]: https://github.com/rezabazzi/tor-windows-autoinstaller/releases/tag/v2.0.0
[0.1.0]: https://github.com/rezabazzi/tor-windows-autoinstaller/releases/tag/v0.1.0
