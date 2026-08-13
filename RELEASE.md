# Release process

This document describes the minimal steps to create a release for this project.

1. Update CHANGELOG.md with notable changes for the version.
2. Bump version in any build metadata (if used).
3. Build the installer using Inno Setup:
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" Tor-Installer.iss
4. Test the installer on a clean Windows VM.
5. Create a Git tag for the release:
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
6. Create a GitHub Release for the tag and attach the built installer.

Optional:
- Sign release artifacts.
- Publish release notes and update docs.
