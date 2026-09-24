$ISCC = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
$ProjectDir = "C:\Users\MordadPC\tor-windows-autoinstaller"

Write-Host "Building installer using $ISCC"
Set-Location $ProjectDir

# Build
& $ISCC "Tor-Installer.iss" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!"
    Get-ChildItem Output\*.exe -ErrorAction SilentlyContinue
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE"
}
