#Requires -Version 5.1
<#
  Watchdog-TorAutoBridge.ps1

  Runs on a schedule (every 5 min + at boot, registered by Setup-TorService.ps1
  as a Scheduled Task). Decides on its own whether TorService needs bridges,
  with zero manual .conf renaming:

    1. If Tor is bootstrapping fine without bridges -> does nothing.
    2. If Tor has been stuck (not reaching "Bootstrapped 100%") for ~15
       minutes with bridges OFF -> automatically activates the first
       available bridges.d\*.conf.sample (by stripping ".sample") and
       restarts TorService.
    3. If bridges are already ON and it's STILL stuck 15 minutes later ->
       logs a one-time alert (these specific bridges are probably dead/
       blocked) and stops auto-restarting, so it doesn't restart-loop
       forever chasing bridges that can't work. Fix at that point means
       dropping fresh bridge lines in bridges.d\ - the watchdog can't
       invent working bridges out of thin air, only switch between
       "no bridges" and "the bridge files that exist on disk".

  Idempotent, safe to run concurrently-by-accident (state file guards it).
#>

[CmdletBinding()]
param()

$AppDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgesDir  = Join-Path $AppDir 'bridges.d'
$LogDir      = Join-Path $AppDir 'logs'
$NoticeLog   = Join-Path $LogDir 'tor-notice.log'
$LogFile     = Join-Path $LogDir 'autobridge.log'
$StateFile   = Join-Path $BridgesDir '.autobridge-state.json'
$SvcName     = 'TorService'
$Nssm        = Join-Path $AppDir 'nssm.exe'

# How long a stuck bootstrap has to persist (in watchdog runs) before we act.
# With the 5-minute scheduled-task interval this is ~15 minutes.
$FailThreshold = 3

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $BridgesDir)) { New-Item -ItemType Directory -Path $BridgesDir -Force | Out-Null }

function Write-WatchdogLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line
}

function Get-AutoBridgeState {
    if (Test-Path $StateFile) {
        try {
            return (Get-Content $StateFile -Raw | ConvertFrom-Json)
        } catch {
            Write-WatchdogLog "State file unreadable ($($_.Exception.Message)) - falling back to default state."
        }
    }
    return [PSCustomObject]@{
        TorPid          = 0
        TorStartTime    = $null
        Offset          = 0
        FailCount       = 0
        BridgesEnabled  = $false
        AutoEnabledAt   = $null
        AlertedStale    = $false
    }
}

function Save-State($state) {
    $state | ConvertTo-Json | Set-Content -Path $StateFile
}

function Get-ActiveBridgeConfCount {
    (Get-ChildItem -Path $BridgesDir -Filter '*.conf' -File -ErrorAction SilentlyContinue).Count
}

$torProc = Get-Process -Name 'tor' -ErrorAction SilentlyContinue
if (-not $torProc) {
    Write-WatchdogLog "tor.exe not running - attempting 'nssm start $SvcName' and exiting this cycle."
    try { & $Nssm start $SvcName *>> $LogFile } catch { Write-WatchdogLog "nssm start failed: $($_.Exception.Message)" }
    exit 0
}

$state = Get-AutoBridgeState

# Detect a fresh tor.exe instance (service restarted since our last check,
# whether we did it or something else did) - reset the tracked log offset
# and failure counter so we only judge THIS instance's bootstrap, not a
# stale one from a previous run.
$currentStartTime = $torProc.StartTime.ToString('o')
if ($state.TorPid -ne $torProc.Id -or $state.TorStartTime -ne $currentStartTime) {
    $offset = 0
    if (Test-Path $NoticeLog) { $offset = (Get-Item $NoticeLog).Length }
    $state.TorPid       = $torProc.Id
    $state.TorStartTime = $currentStartTime
    $state.Offset       = $offset
    $state.FailCount    = 0
    $state.BridgesEnabled = (Get-ActiveBridgeConfCount) -gt 0
    Write-WatchdogLog "New tor.exe instance detected (PID $($torProc.Id)) - watching from log offset $offset. Bridges currently $(if ($state.BridgesEnabled) {'ON'} else {'OFF'})."
}

# ---- Health check: did "Bootstrapped 100%" appear since our tracked offset? ----
$healthy = $false
if (Test-Path $NoticeLog) {
    $len = (Get-Item $NoticeLog).Length
    if ($len -gt $state.Offset) {
        $stream = [System.IO.File]::Open($NoticeLog, 'Open', 'Read', 'ReadWrite')
        try {
            $stream.Seek($state.Offset, 'Begin') | Out-Null
            $reader = New-Object System.IO.StreamReader($stream)
            $tail = $reader.ReadToEnd()
            if ($tail -match 'Bootstrapped 100%') { $healthy = $true }
        } finally {
            $reader.Dispose(); $stream.Dispose()
        }
    }
}

if ($healthy) {
    Write-WatchdogLog "Healthy: Bootstrapped 100% seen for PID $($torProc.Id)."
    $state.FailCount = 0
    Save-State $state
    exit 0
}

$state.FailCount++
Write-WatchdogLog "Not yet bootstrapped (check $($state.FailCount)/$FailThreshold for PID $($torProc.Id))."

if ($state.FailCount -lt $FailThreshold) {
    Save-State $state
    exit 0
}

# ---- Threshold reached: decide what to do ----
if (-not $state.BridgesEnabled) {
    $sample = Get-ChildItem -Path $BridgesDir -Filter '*.conf.sample' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sample) {
        $target = Join-Path $BridgesDir ($sample.BaseName)   # strips ".sample"
        Write-WatchdogLog "Direct connection stuck for ~$($FailThreshold * 5) min. Auto-activating bridges: $($sample.Name) -> $(Split-Path -Leaf $target)"
        Copy-Item -Path $sample.FullName -Destination $target -Force
        try { & $Nssm restart $SvcName *>> $LogFile } catch { Write-WatchdogLog "nssm restart failed: $($_.Exception.Message)" }

        # Reset tracking for the instance that's about to come up.
        Start-Sleep -Seconds 2
        $state.BridgesEnabled = $true
        $state.AutoEnabledAt  = (Get-Date).ToString('o')
        $state.FailCount      = 0
        $state.TorPid         = 0          # force a re-detect next run
        $state.TorStartTime   = $null
        Save-State $state
    } else {
        Write-WatchdogLog "Direct connection stuck for ~$($FailThreshold * 5) min, but no bridges.d\*.conf.sample available to auto-activate. Nothing more this watchdog can do automatically - drop a bridge conf into $BridgesDir manually."
        Save-State $state
    }
} else {
    if (-not $state.AlertedStale) {
        Write-WatchdogLog "ALERT: bridges are enabled but still stuck ~$($FailThreshold * 5) min after activation. These bridges are likely dead or also blocked. Not restarting again automatically to avoid a restart loop - get fresh bridge lines (https://bridges.torproject.org/) into $BridgesDir and either replace the active .conf or restart the service by hand once you have new ones."
        $state.AlertedStale = $true
    }
    Save-State $state
}
