# Contributing

Thanks for your interest in contributing! This file describes the typical workflow and tools we expect contributors to use.

Filing issues
- Use the issue templates (bug_report.md, feature_request.md) to provide reproducible steps and environment details.

Developing
- Fork the repository and create a feature branch:
  git checkout -b feat/short-description

- Keep changes focused and use clear commit messages. Prefer small, reviewable commits.

Linting and static analysis
- We use PSScriptAnalyzer for PowerShell files. Run it locally before opening a PR:
  Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path . -Recurse

- The repository includes a GitHub Actions workflow to run PSScriptAnalyzer on PRs.

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
