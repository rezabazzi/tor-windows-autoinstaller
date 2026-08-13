# Contributing

Thanks for your interest in contributing! This file describes the typical workflow and tools we expect contributors to use.

Filing issues
- Use the issue templates (bug_report.md, feature_request.md) to provide reproducible steps and environment details.

Developing
- Fork the repository and create a feature branch:
  git checkout -b feat/short-description

- Keep changes focused and use clear commit messages. Prefer small, reviewable commits.

Linting and static analysis
- We use PSScriptAnalyzer for PowerShell files. Run it locally before opening a PR, using the repo's settings file so your results match CI:
  Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning -Settings ./PSScriptAnalyzerSettings.psd1

- The repository includes a GitHub Actions workflow that runs this exact command on every PR and push to main, and fails the check if anything is found - it isn't just informational.

Lint rule exceptions
- Two default PSScriptAnalyzer rules are deliberately excluded via PSScriptAnalyzerSettings.psd1, not by accident:
  - `PSAvoidUsingWriteHost` - this project's scripts are run interactively by an admin (the installer even pauses for a keypress when run standalone outside the installer's silent flow). Write-Host is the right tool for that; the rule exists to protect module code meant to be composed in a pipeline, which doesn't apply here.
  - `PSUseShouldProcessForStateChangingFunctions` - flags the watchdog's private `Save-State` helper for its verb. It's an internal implementation detail that persists the watchdog's own tracking file, not a public cmdlet anyone would expect `-WhatIf`/`-Confirm` support on.
- If you think a new exception is warranted, say so explicitly in the PR description rather than adding it silently - the settings file is meant to stay a short, reasoned list.

Testing and building
- To build the installer locally you will need Inno Setup (ISCC.exe). Typical steps:
  1. Install Inno Setup from https://jrsoftware.org/
  2. Edit Tor-Installer.iss to set any paths/versions
  3. Run ISCC.exe Tor-Installer.iss to produce the installer

Security & sensitive data
- Do NOT commit secrets, credentials, tokens, or private keys to the repository.
- If you need to share a secret for CI or tests, use repository secrets (Actions) or a secure channel.

Creating a Pull Request
- Push your feature branch to your fork and open a pull request targeting this repository.
- Include:
  - Short description of change
  - Motivation and summary of approach
  - Testing steps or how to verify
  - Any follow-up tasks

CI and merging
- Wait for PSScriptAnalyzer checks to pass on the PR.
- Address any review comments and requested changes.
- When approved and CI is green the PR can be merged by a maintainer.

Maintainer tips
- Use the GitHub web UI or gh CLI:
  - gh pr checkout <number>
  - gh pr merge <number> --merge | --squash | --rebase

Thanks for contributing — your help improves the project for everyone.
