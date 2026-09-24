# Changelog

All notable changes to this project will be documented in this file.

Format: Keep a short summary with an "Unreleased" section at top.

## Unreleased
- Initial community files and CI workflow

## 2.0.0 - 2026-09-24
- **WebSocket API server** — real-time monitoring and control of Tor via WebSocket
  - Status, log streaming, circuit info, newnym, restart commands
  - REST endpoint at `GET /api/status`
  - Runs as an NSSM service (TorApiService)
  - Binds to `127.0.0.1:9052`
- **Snowflake pluggable transport support**
  - New `snowflake-client.exe` support (obfs4, webtunnel, snowflake)
  - New sample config: `bridges.d\snowflake-bridges.conf.sample`
  - Watchdog auto-detects and activates Snowflake bridges
- **Multi-transport watchdog** — now supports obfs4, webtunnel, and snowflake
  - Transport-aware bridge detection
  - Priority order: obfs4 → webtunnel → snowflake
- **Tor ControlPort** (9051) enabled for WebSocket API communication
- **torrc improvements**: relative paths, ControlPort, snowflake transport
- **Bug fixes**:
  - Fixed hard-coded absolute paths in `torrc` (now relative)
  - Fixed Watchdog-TorAutoBridge.ps1 log rotation handling (offset reset)
  - Fixed PT detection: only one PT required (was requiring both lyrebird.exe and snowflake-client.exe)
  - Fixed uninstall to also remove TorApiService
  - Fixed firewall rule program path in setup script
- **New files**:
  - `TorApiServer.ps1` — WebSocket API server
  - `Source/bridges.d/snowflake-bridges.conf.sample` — Snowflake bridge example
- **Updated documentation**:
  - README.md: WebSocket API docs, Snowflake transport docs, new configuration reference
  - Updated project structure, requirements, and troubleshooting

## 0.1.0 - 2026-08-13
- Initial release skeleton
