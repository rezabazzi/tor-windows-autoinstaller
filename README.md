# Tor Windows Autoinstaller

[![CI (PSScriptAnalyzer)](https://github.com/rezabazzi/tor-windows-autoinstaller/actions/workflows/powershell-lint.yml/badge.svg)](https://github.com/rezabazzi/tor-windows-autoinstaller/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A fully automated Windows installer that packages Tor and runs it as a resilient Windows service. The installer and helpers are implemented using PowerShell and Inno Setup.

Key goals
- Provide a native Windows installer that installs and configures Tor.
- Run Tor as a background service that self-recovers and can be updated.
- Offer simple management scripts for installation, configuration, and updates.

Quick links
- Repository: https://github.com/rezabazzi/tor-windows-autoinstaller
- Issues: https://github.com/rezabazzi/tor-windows-autoinstaller/issues
- Pull Requests: https://github.com/rezabazzi/tor-windows-autoinstaller/pulls

Requirements
- Windows 10 or later (x64 recommended)
- Administrator privileges to run installers and register services
- Inno Setup (ISCC.exe) to build the installer locally (optional for maintainers)

Getting started (clone)
1. Clone the repository:

   git clone https://github.com/rezabazzi/tor-windows-autoinstaller.git
   cd tor-windows-autoinstaller

2. Work on the add/community-files branch or create a feature branch:

   git checkout -b feat/my-change

Build / test locally (maintainers)
- Install Inno Setup: https://jrsoftware.org/isinfo.php
- Build the installer:

  1. Review and update variables in Tor-Installer.iss if needed.
  2. Run ISCC.exe on Tor-Installer.iss:
     "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" Tor-Installer.iss

- PowerShell scripts
  - Setup-TorService.ps1 — main service installer & configuration script
  - Watchdog-TorAutoBridge.ps1 — service watchdog helper

Usage examples
- Install and configure Tor as a service (run as Administrator):
  pwsh .\Setup-TorService.ps1 -Install

- Start the Tor service:
  Start-Service -Name Tor

- Stop the Tor service:
  Stop-Service -Name Tor

Repository structure
- Tor-Installer.iss      — Inno Setup script for building the installer
- Setup-TorService.ps1  — PowerShell installer & configuration helper
- Watchdog-TorAutoBridge.ps1 — Watchdog/service helper
- Source/                — supporting files used by the installer

Contributing
See CONTRIBUTING.md for how to run linters, tests, and how to propose changes. Short version:
- Fork the repo
- Create a topic branch
- Run PSScriptAnalyzer locally: Install-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path . -Recurse
- Open a PR and reference related issues

Security
See SECURITY.md for the vulnerability disclosure process.

License
This project is licensed under the MIT License — see LICENSE.

Maintainers & contacts
- Repo owner: @rezabazzi
