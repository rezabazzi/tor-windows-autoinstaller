# Contributing

Thanks for your interest in contributing! This file describes the typical workflow and tools we expect contributors to use.

## Filing Issues
- Use the issue templates (bug_report.md, feature_request.md) to provide reproducible steps and environment details.

## Developing
- Fork the repository and create a feature branch:
  ```bash
  git checkout -b feat/short-description
  git checkout -b fix/short-description
  ```

- Keep changes focused and use clear commit messages. Prefer small, reviewable commits.

## Project Architecture (v2.0)
```
Tor-Installer.iss          # Inno Setup — packaging
Setup-TorService.ps1       # Post-install: service setup, firewall, watchdog, API server, dashboard
Watchdog-TorAutoBridge.ps1 # Scheduled task: multi-transport bridge activation
TorApiServer.ps1           # WebSocket API: real-time monitoring and control
DashboardServer.ps1        # HTTP server for web dashboard (port 8383)
WebDashboard.html          # Browser-based monitoring UI
TorApiClient.ps1           # Example WebSocket client
PSScriptAnalyzerSettings.psd1
Source/
  tor.exe, nssm.exe, *.dll
  torrc                    # Config (relative paths, ControlPort, bridges include)
  PluggableTransports/
    lyrebird.exe           # obfs4/webtunnel
    snowflake-client.exe   # snowflake
    meek-client.exe        # meek
    conjure-client.exe     # conjure
  bridges.d/
    mordad-bridges.conf.sample      # obfs4/webtunnel example
    snowflake-bridges.conf.sample   # snowflake example
    meek-bridges.conf.sample        # meek example
    conjure-bridges.conf.sample     # conjure example
```

## Linting and Static Analysis
We use PSScriptAnalyzer for PowerShell files. Run it locally before opening a PR:
```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning -Settings ./PSScriptAnalyzerSettings.psd1
```

The repository includes a GitHub Actions workflow that runs this exact command on every PR and push to main.

## Lint Rule Exceptions
Four default PSScriptAnalyzer rules are deliberately excluded via `PSScriptAnalyzerSettings.psd1`:

1. `PSAvoidUsingWriteHost` — scripts are run interactively by an admin. Write-Host is correct for that.
2. `PSUseShouldProcessForStateChangingFunctions` — flags the watchdog's private `Save-State` helper. It's internal, not a public cmdlet.
3. `PSUseDeclaredVarsMoreThanAssignments` — the WebSocket API server shares state across functions via script-scoped variables.
4. `PSReviewUnusedParameter` — flags `TorControlHost` and `TorControlPort` in `TorApiServer.ps1` which ARE used in nested script blocks but PSScriptAnalyzer can't resolve cross-block usage.

## Testing and Building
To build the installer locally:
1. Install Inno Setup from https://jrsoftware.org/
2. Place required binaries in the Source folder (see Tor-Installer.iss header)
3. Run `ISCC.exe Tor-Installer.iss` to produce the installer

## Security & Sensitive Data
- Do NOT commit secrets, credentials, tokens, or private keys to the repository.

## Creating a Pull Request
- Push your feature branch to your fork and open a pull request.
- Include: description, motivation, testing steps, follow-up tasks.

## CI and Merging
- Wait for PSScriptAnalyzer checks to pass.
- Address review comments.
- When approved and CI is green, the PR can be merged.
