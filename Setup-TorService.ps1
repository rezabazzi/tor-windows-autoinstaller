#Requires -Version 5.1
<#
  Setup-TorService.ps1  (replaces Setup-TorService.cmd)
  Installs/configures/starts TorService via NSSM, opens the firewall rule,
  and actually verifies Tor is alive afterward instead of trusting
  "sc query | RUNNING" (which is true almost instantly regardless of
  whether tor.exe itself survives, since NSSM's wrapper process comes up
  on its own).

  Safe to re-run any time (idempotent). Must run elevated (as Administrator).

  Can be run two ways:
    1. Automatically by Tor-Installer-Setup.exe right after the file copy.
    2. Manually (as admin) on a machine where the installer already copied
       files but the service never got created/started correctly.

  Everything is logged to logs\install.log AND written to the console, so
  a silent double-click won't look like "nothing happened" - if the window
  closes immediately, the log file will still have a record of whatever
  did or didn't run.
#>

[CmdletBinding()]
param(
    # Passed by the installer's [Run] step so the automatic install never
    # blocks waiting for a keypress. Omit this when double-clicking the
    # script manually and it will pause before closing, so a fast
    # success/failure never looks like "nothing happened".
    [switch]$Silent
)

$ErrorActionPreference = 'Continue'

$AppDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Nssm       = Join-Path $AppDir 'nssm.exe'
$TorExe     = Join-Path $AppDir 'tor.exe'
$Torrc      = Join-Path $AppDir 'torrc'
$PtExe      = Join-Path $AppDir 'PluggableTransports\lyrebird.exe'
$LogDir     = Join-Path $AppDir 'logs'
$LogFile    = Join-Path $LogDir 'install.log'
$NoticeLog  = Join-Path $LogDir 'tor-notice.log'
$SvcName    = 'TorService'
$FwRuleName = 'Tor SOCKS Proxy'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Exit-Script {
    param([int]$Code)
    Write-Log "===== Setup-TorService.ps1 finished with exit code $Code ====="
    # Keep the window open if double-clicked directly (not via the installer's
    # hidden [Run] step) so "nothing happened" can never be the takeaway.
    if ($Host.Name -eq 'ConsoleHost' -and -not $Silent) {
        Write-Host ""
        Write-Host "Press Enter to close this window..."
        [void][System.Console]::ReadLine()
    }
    exit $Code
}

Write-Log "===== Setup-TorService.ps1 started ====="
Write-Log "AppDir=$AppDir"

# ---- Sanity checks: fail loudly, not silently ----
$missing = @()
foreach ($f in @(@{Path=$Nssm;Name='nssm.exe'}, @{Path=$TorExe;Name='tor.exe'}, @{Path=$Torrc;Name='torrc'}, @{Path=$PtExe;Name='PluggableTransports\lyrebird.exe'})) {
    if (-not (Test-Path $f.Path)) { $missing += $f.Name }
}
if ($missing.Count -gt 0) {
    Write-Log ("ERROR: Missing required file(s): " + ($missing -join ', '))
    Write-Host ""
    Write-Host "ERROR: Missing required file(s): $($missing -join ', ')"
    Write-Host "Check $AppDir and re-run this script."
    Exit-Script 1
}

# ---- Zero-byte / stubbed-file check (AV quarantine often leaves a 0-byte
#      or truncated file behind instead of deleting it outright) ----
$corrupt = @()
foreach ($f in @(@{Path=$Nssm;Name='nssm.exe'}, @{Path=$TorExe;Name='tor.exe'}, @{Path=$PtExe;Name='lyrebird.exe'})) {
    $item = Get-Item $f.Path -ErrorAction SilentlyContinue
    if ($item -and $item.Length -eq 0) { $corrupt += $f.Name }
}
if ($corrupt.Count -gt 0) {
    Write-Log ("ERROR: File(s) present but 0 bytes (likely AV-quarantined): " + ($corrupt -join ', '))
    Write-Host ""
    Write-Host "ERROR: These files exist but are empty - your antivirus almost"
    Write-Host "certainly stripped them right after copy: $($corrupt -join ', ')"
    Write-Host "Add $AppDir as a Defender/AV exclusion, then re-run the"
    Write-Host "installer so [Files] re-copies clean binaries."
    Exit-Script 1
}

# ---- Admin check ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: Not running as Administrator."
    Write-Host ""
    Write-Host "This script must be run as Administrator. Right-click it and"
    Write-Host "choose 'Run with PowerShell as administrator', then try again."
    Exit-Script 1
}

# ---- Best-effort Defender exclusion for the install folder, so a
#      same-second scan can't eat tor.exe/lyrebird.exe/nssm.exe right as the
#      service launches them. Silently skipped if Defender is managed,
#      Tamper Protection is on, or a third-party AV owns the module. ----
Write-Log "Attempting best-effort Defender exclusion for $AppDir ..."
try {
    Add-MpPreference -ExclusionPath $AppDir -ErrorAction Stop
    Write-Log "Defender exclusion added (or already present)."
} catch {
    Write-Log "Defender exclusion skipped: $($_.Exception.Message)"
}

# ---- Does the service already exist? ----
$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Log "Service $SvcName already exists - skipping install, will reapply config."
} else {
    Write-Log "Installing service $SvcName via NSSM..."
    $out = & $Nssm install $SvcName $TorExe '-f' $Torrc 2>&1
    $out | Add-Content -Path $LogFile
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: nssm install failed with code $LASTEXITCODE"
        Write-Host "ERROR: nssm install failed. See $LogFile for details."
        Exit-Script 1
    }
    Write-Log "nssm install succeeded."
}

# ---- Apply config (idempotent - safe to always reapply) ----
Write-Log "Applying service configuration..."
& $Nssm set $SvcName AppDirectory $AppDir                                          *>> $LogFile
& $Nssm set $SvcName DisplayName 'Tor SOCKS Proxy'                                 *>> $LogFile
& $Nssm set $SvcName Description 'Tor SOCKS5 proxy (auto-installed, port 9050)'     *>> $LogFile
& $Nssm set $SvcName Start SERVICE_AUTO_START                                       *>> $LogFile
& $Nssm set $SvcName AppStdout (Join-Path $LogDir 'service-stdout.log')             *>> $LogFile
& $Nssm set $SvcName AppStderr (Join-Path $LogDir 'service-stderr.log')             *>> $LogFile
& $Nssm set $SvcName AppRotateFiles 1                                              *>> $LogFile
& $Nssm set $SvcName AppRestartDelay 5000                                          *>> $LogFile
& $Nssm set $SvcName AppExit Default Restart                                       *>> $LogFile
Write-Log "Service configuration applied."

# ---- Firewall rule (idempotent) ----
$rule = Get-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
if ($rule) {
    Write-Log "Firewall rule already exists - skipping."
} else {
    Write-Log "Adding firewall rule..."
    try {
        New-NetFirewallRule -DisplayName $FwRuleName -Direction Outbound -Action Allow -Program $TorExe -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        Write-Log "Firewall rule added."
    } catch {
        Write-Log "WARNING: failed to add firewall rule: $($_.Exception.Message)"
    }
}

# ---- Register the auto-bridge watchdog scheduled task (idempotent) ----
# This is what makes bridge activation fully hands-off: Watchdog-TorAutoBridge.ps1
# runs every 5 min + at boot and decides on its own whether direct Tor
# connections are working or bridges need to be switched on - no manual
# .conf renaming, no re-running this installer.
Write-Log "Registering TorAutoBridge-Watchdog scheduled task..."
try {
    $watchdogScript = Join-Path $AppDir 'Watchdog-TorAutoBridge.ps1'
    $taskName = 'TorAutoBridge-Watchdog'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$watchdogScript`""
    $trigBoot  = New-ScheduledTaskTrigger -AtStartup
    $trigLoop  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigBoot, $trigLoop) -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "TorAutoBridge-Watchdog scheduled task registered (every 5 min + at boot, as SYSTEM)."
} catch {
    Write-Log "WARNING: could not register TorAutoBridge-Watchdog scheduled task: $($_.Exception.Message). Bridges will still work if you activate a bridges.d\*.conf manually - they just won't be switched on automatically."
}

# ---- Start the service ----

Write-Log "Starting $SvcName..."
try {
    & $Nssm start $SvcName *>> $LogFile
} catch {
    Write-Log "nssm start threw: $($_.Exception.Message) (continuing to real health check anyway)"
}

# ---- REAL health check: NSSM's own wrapper process comes up almost
#      instantly regardless of whether tor.exe itself survives, so poll for
#      up to ~15s for an actual tor.exe process AND a bootstrap line in the
#      notice log before declaring success. ----
$torAlive = $false
$bootstrapped = $false
for ($i = 0; $i -lt 15; $i++) {
    if (Get-Process -Name 'tor' -ErrorAction SilentlyContinue) { $torAlive = $true }
    if (Test-Path $NoticeLog) {
        if (Select-String -Path $NoticeLog -Pattern 'Bootstrapped 100%' -SimpleMatch -ErrorAction SilentlyContinue) {
            $bootstrapped = $true
        }
    }
    if ($bootstrapped) { break }
    Start-Sleep -Seconds 1
}

if ($bootstrapped) {
    Write-Log "SUCCESS: tor.exe is running and reported Bootstrapped 100%."
    Write-Host ""
    Write-Host "Tor service is installed, running, and connected."
    Exit-Script 0
} elseif ($torAlive) {
    Write-Log "WARNING: tor.exe process is alive but never reached Bootstrapped 100% within 15s - likely a bridge/network problem, not an install problem. Check $NoticeLog."
    Write-Host ""
    Write-Host "Tor process started but has not finished connecting yet."
    Write-Host "Check $NoticeLog - this is usually a bridge/network issue,"
    Write-Host "not an installer problem."
    Exit-Script 0
} else {
    Write-Log "ERROR: tor.exe never appeared as a running process. NSSM wrapper may be alive while tor.exe itself crashes/exits immediately (missing DLL, quarantined lyrebird.exe, bad torrc line)."
    Write-Host ""
    Write-Host "ERROR: Tor did not actually start, even though the service"
    Write-Host "wrapper may show as RUNNING. Check, in this order:"
    Write-Host "  - $LogFile"
    Write-Host "  - $(Join-Path $LogDir 'service-stderr.log')"
    Write-Host "  - $NoticeLog"
    Write-Host "  - whether tor.exe / lyrebird.exe are still full-size files"
    Write-Host "    (0-byte = your antivirus ate them - add an exclusion and"
    Write-Host "    re-run this script)"
    Exit-Script 1
}
