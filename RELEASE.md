# Release process

This document describes the minimal steps to create a release for this project.

1. Update CHANGELOG.md with notable changes for the version.
2. Bump version in build metadata:
   - `Tor-Installer.iss` → `#define MyAppVersion "X.Y"`
3. Place required binaries in the Source folder:
   - `tor.exe` (from Tor Expert Bundle)
   - `*.dll` (dependencies: libssl, libcrypto, libevent, zlib)
   - `PluggableTransports\lyrebird.exe` (from Tor Expert Bundle)
   - `PluggableTransports\snowflake-client.exe` (from lyrebird repo)
   - `PluggableTransports\meek-client.exe` (from meek repo)
   - `PluggableTransports\conjure-client.exe` (from conjure repo)
   - `nssm.exe` (from nssm.cc)
4. Build the installer using Inno Setup:
   ```
   ISCC.exe Tor-Installer.iss
   ```
   Output: `Output\Tor-Installer-Setup.exe`
5. Test the installer on a clean Windows VM.
6. Create a Git tag for the release:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```
7. Create a GitHub Release for the tag and attach `Output\Tor-Installer-Setup.exe`.

Optional:
- Sign release artifacts.
- Publish release notes and update docs.
