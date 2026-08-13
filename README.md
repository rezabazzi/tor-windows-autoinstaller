# Tor Windows Autoinstaller

Fully automatic Windows installer that turns Tor into a permanent, self-healing background service.

[![Actions Status](https://github.com/rezabazzi/tor-windows-autoinstaller/actions/workflows/powershell-lint.yml/badge.svg)](https://github.com/rezabazzi/tor-windows-autoinstaller/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Quick summary

This repository provides a fully automatic installer for Tor on Windows. It installs Tor as a background service that will restart itself if it fails and includes configuration and update helpers implemented in PowerShell and Inno Setup.

## What's included

- PowerShell scripts to install, configure, and manage Tor as a Windows service.
- Inno Setup installer scripts to build a native Windows installer.

## Requirements

- Windows 10 or later
- Administrator privileges for installation

## Installation (build and test locally)

1. Clone the repo:

   git clone https://github.com/rezabazzi/tor-windows-autoinstaller.git

2. Review the Inno Setup scripts in the repo and build the installer using Inno Setup (ISCC.exe).

3. Run the generated installer as Administrator.

## Usage

See the scripts in the repo for available commands and options. Typical tasks:

- Install Tor as a service
- Configure Tor settings
- Start/stop the Tor service

## Contributing

See CONTRIBUTING.md for details on how to contribute.

## Security

See SECURITY.md for the disclosure policy. For now, please report security issues by opening an issue and marking it as a security report.

## License

This project is licensed under the MIT License — see the LICENSE file for details.
