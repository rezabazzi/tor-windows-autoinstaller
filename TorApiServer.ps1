#Requires -Version 5.1
<#
  TorApiServer.ps1 — v2.0 WebSocket API for Tor SOCKS Proxy

  Provides real-time monitoring and control of Tor via WebSocket.
  Connects to Tor's ControlPort (9051) and exposes:
    - GET /ws  — WebSocket: live status events + command interface
    - GET /api/status  — JSON: current Tor status snapshot

  WebSocket JSON protocol (client -> server):
    {"cmd": "status"}                 -> returns current status
    {"cmd": "restart"}                -> restart Tor service
    {"cmd": "circuit"}                -> circuit info
    {"cmd": "newnym"}                 -> request new identity
    {"cmd": "log", "tail": 50}        -> last N lines of notice log

  WebSocket JSON protocol (server -> client):
    {"type": "status", "data": {...}} -> periodic status push
    {"type": "log", "data": "..."}    -> log line events

  Runs as a service via NSSM (registered by Setup-TorService.ps1).
#>

[CmdletBinding()]
param(
    [int]$Port = 9052,
    [string]$TorControlHost = '127.0.0.1',
    [int]$TorControlPort = 9051,
    [int]$StatusIntervalSeconds = 10
)

$ErrorActionPreference = 'Continue'
$AppDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir    = Join-Path $AppDir 'logs'
$NoticeLog = Join-Path $LogDir 'tor-notice.log'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-ApiLog {
    param([string]$Message)
    $line = "[{0}] API: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path (Join-Path $LogDir 'torapi.log') -Value $line
}

Write-ApiLog "TorApiServer starting on port $Port..."

# ---- HTTP listener ----
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
    $listener.Start()
    Write-ApiLog "HTTP listener started on http://127.0.0.1:$Port/"
} catch {
    Write-ApiLog "FATAL: Failed to start listener: $($_.Exception.Message)"
    exit 1
}

# ---- Tor control connection ----
$torTcp = $null
$torReader = $null
$torWriter = $null
$torStream = $null

function Connect-TorControl {
    param(
        [string]$Host = '127.0.0.1',
        [int]$Port = 9051
    )
    try {
        if ($torTcp) {
            try { $torTcp.Close() } catch {}
        }
        $torTcp = New-Object System.Net.Sockets.TcpClient
        $torTcp.Connect($Host, $Port)
        $torStream = $torTcp.GetStream()
        $torReader = New-Object System.IO.StreamReader($torStream)
        $torWriter = New-Object System.IO.StreamWriter($torStream)
        $torWriter.AutoFlush = $true

        # Read greeting
        $greeting = $torReader.ReadLine()

        # Authenticate with cookie
        $cookiePath = Join-Path $AppDir 'control_auth_cookie'
        if (-not (Test-Path $cookiePath)) {
            # Try alternate location
            $cookiePath = (Get-ChildItem -Path $AppDir -Filter 'control_auth_cookie' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }
        if ($cookiePath -and (Test-Path $cookiePath)) {
            $cookie = (Get-Content $CookiePath -Encoding Byte | ForEach-Object { '{0:X2}' -f $_ }) -replace ' ',''
            $torWriter.WriteLine("AUTHENTICATE $cookie")
            $resp = $torReader.ReadLine()
            if ($resp -like '250*') {
                return $true
            }
        }

        # Try no-auth
        $torWriter.WriteLine("AUTHENTICATE")
        $resp = $torReader.ReadLine()
        return ($resp -like '250*')
    } catch {
        Write-ApiLog "TorControl connect failed: $($_.Exception.Message)"
        return $false
    }
}

function Send-TorCommand {
    param([string]$Command)
    try {
        if (-not $torTcp -or -not $torTcp.Connected) {
            if (-not (Connect-TorControl -Host $TorControlHost -Port $TorControlPort)) {
                return @{ success = $false; error = 'not_connected' }
            }
        }
        $torWriter.WriteLine($Command)
        $response = @()
        $line = $torReader.ReadLine()
        while ($line -and $line -notmatch '^250 OK$' -and $line -notmatch '^(5\d\d|6\d\d)') {
            $response += $line
            $line = $torReader.ReadLine()
        }
        if ($line -match '^250') {
            return @{ success = $true; data = $response }
        } else {
            return @{ success = $false; error = $line; data = $response }
        }
    } catch {
        return @{ success = $false; error = $_.Exception.Message }
    }
}

function Get-TorStatus {
    try {
        # Get various info
        $version = Send-TorCommand 'GETINFO version'
        $traffic = Send-TorCommand 'GETINFO traffic/read traffic/written'
        $uptime  = Send-TorCommand 'GETINFO uptime'
        $circuit = Send-TorCommand 'GETINFO circuit-status'
        $info    = Send-TorCommand 'GETINFO ns/all'

        # Parse version
        $ver = if ($version.success -and $version.data) {
            ($version.data | Where-Object { $_ -match 'version=' } | ForEach-Object {
                if ($_ -match 'version="?([^"\s]+)"?') { $matches[1] } else { $_ }
            }) -join ' '
        } else { 'unknown' }

        # Parse traffic
        $read = 0; $written = 0
        if ($traffic.success) {
            foreach ($l in $traffic.data) {
                if ($l -match 'traffic/read=(\d+)') { $read = [long]$matches[1] }
                if ($l -match 'traffic/written=(\d+)') { $written = [long]$matches[1] }
            }
        }

        # Parse uptime
        $up = 0
        if ($uptime.success -and $uptime.data -match 'uptime=(\d+)') {
            $up = [long]$matches[1]
        }

        # Get tor process info
        $torProc = Get-Process -Name 'tor' -ErrorAction SilentlyContinue
        $running = $torProc -ne $null
        $pid = if ($torProc) { $torProc.Id } else { 0 }
        $mem = if ($torProc) { [math]::Round($torProc.WorkingSet64 / 1MB, 2) } else { 0 }

        return @{
            timestamp   = (Get-Date).ToString('o')
            running     = $running
            pid         = $pid
            version     = $ver
            uptime      = $up
            memMB       = $mem
            bytesRead   = $read
            bytesWritten = $written
            bootstrapped = $false
        }
    } catch {
        @{ running = $false; error = $_.Exception.Message }
    }
}

# ---- WebSocket handler ----
$webSocketClients = [System.Collections.Concurrent.ConcurrentDictionary[System.Guid, System.Net.WebSockets.WebSockets]]::new()
$cts = New-Object System.Threading.CancellationTokenSource

function Send-WebSocketMessage {
    param(
        [System.Net.WebSockets.WebSocket]$Socket,
        [string]$Message,
        [System.Threading.CancellationToken]$Token
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $Token).Wait()
}

function Receive-WebSocketMessage {
    param(
        [System.Net.WebSockets.WebSocket]$Socket,
        [System.Threading.CancellationToken]$Token
    )
    $buffer = New-Object byte[] 4096
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
    $result = $Socket.ReceiveAsync($segment, $Token).Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
        return $null
    }
    return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
}

# Status push loop
$pushTimer = New-Object System.Timers.Timer
$pushTimer.Interval = $StatusIntervalSeconds * 1000
$pushTimer.AutoReset = $true
$pushTimer.Add_Elapsed({
    $status = Get-TorStatus
    # Check bootstrap
    if (Test-Path $NoticeLog) {
        $lastLine = Get-Content $NoticeLog -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine -match 'Bootstrapped 100%') { $status.bootstrapped = $true }
    }
    $json = @{ type = 'status'; data = $status } | ConvertTo-Json -Compress
    $badClients = @()
    foreach ($kvp in $webSocketClients) {
        try {
            Send-WebSocketMessage -Socket $kvp.Value -Message $json -Token $cts.Token
        } catch {
            $badClients += $kvp.Key
        }
    }
    foreach ($id in $badClients) {
        $s = $null
        $webSocketClients.TryRemove($id, [ref]$s) | Out-Null
    }
})
$pushTimer.Start()

Write-ApiLog "Status push timer started (${StatusIntervalSeconds}s interval)"

# ---- Main HTTP loop ----
while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # WebSocket upgrade
        if ($request.IsWebSocketRequest) {
            $wsContext = $context.AcceptWebSocketRequest($null)
            $ws = $wsContext.WebSocket
            $clientId = [System.Guid]::NewGuid()
            $webSocketClients.TryAdd($clientId, $ws) | Out-Null

            Write-ApiLog "WebSocket client connected: $clientId"

            try {
                while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    $msg = Receive-WebSocketMessage -Socket $ws -Token $cts.Token
                    if ($null -eq $msg) { break }

                    try {
                        $cmd = $msg | ConvertFrom-Json
                        switch ($cmd.cmd) {
                            'status' {
                                $st = Get-TorStatus
                                $reply = @{ type = 'status'; data = $st } | ConvertTo-Json -Compress
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                            'restart' {
                                $nssm = Join-Path $AppDir 'nssm.exe'
                                if (Test-Path $nssm) {
                                    & $nssm restart TorService 2>&1 | Out-Null
                                    $reply = @{ type = 'info'; data = 'restart_requested' } | ConvertTo-Json -Compress
                                } else {
                                    $reply = @{ type = 'error'; data = 'nssm_not_found' } | ConvertTo-Json -Compress
                                }
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                            'newnym' {
                                $res = Send-TorCommand 'SIGNAL NEWNYM'
                                $reply = @{ type = 'newnym'; data = $res } | ConvertTo-Json -Compress
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                            'circuit' {
                                $res = Send-TorCommand 'GETINFO circuit-status'
                                $reply = @{ type = 'circuit'; data = $res.data } | ConvertTo-Json -Compress
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                            'log' {
                                $tail = if ($cmd.tail) { [int]$cmd.tail } else { 20 }
                                $lines = if (Test-Path $NoticeLog) { Get-Content $NoticeLog -Tail $tail } else { @() }
                                $reply = @{ type = 'log'; data = $lines } | ConvertTo-Json -Compress
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                            default {
                                $reply = @{ type = 'error'; data = "unknown_command: $($cmd.cmd)" } | ConvertTo-Json -Compress
                                Send-WebSocketMessage -Socket $ws -Message $reply -Token $cts.Token
                            }
                        }
                    } catch {
                        $err = @{ type = 'error'; data = "parse_error: $($_.Exception.Message)" } | ConvertTo-Json -Compress
                        try { Send-WebSocketMessage -Socket $ws -Message $err -Token $cts.Token } catch {}
                    }
                }
            } finally {
                $webSocketClients.TryRemove($clientId, [ref]$null) | Out-Null
                Write-ApiLog "WebSocket client disconnected: $clientId"
            }
            continue
        }

        # REST API
        $response.Headers.Add('Access-Control-Allow-Origin', '*')
        $response.Headers.Add('Access-Control-Allow-Methods', 'GET, OPTIONS')

        if ($request.Url.LocalPath -eq '/api/status') {
            $status = Get-TorStatus
            if (Test-Path $NoticeLog) {
                $lastLines = Get-Content $NoticeLog -Tail 5 -ErrorAction SilentlyContinue
                if ($lastLines -match 'Bootstrapped 100%') { $status.bootstrapped = $true }
            }
            $json = $status | ConvertTo-Json -Compress
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } elseif ($request.Url.LocalPath -eq '/') {
            $html = @"
<!DOCTYPE html>
<html><head><title>Tor API</title></head>
<body>
<h1>Tor SOCKS Proxy API</h1>
<p>WebSocket endpoint: <code>ws://127.0.0.1:$Port/ws</code></p>
<p>REST endpoint: <code>GET /api/status</code></p>
<h2>WebSocket Commands</h2>
<ul>
<li><code>{"cmd":"status"}</code> — Get current Tor status</li>
<li><code>{"cmd":"restart"}</code> — Restart Tor service</li>
<li><code>{"cmd":"newnym"}</code> — Request new identity</li>
<li><code>{"cmd":"circuit"}</code> — Get circuit info</li>
<li><code>{"cmd":"log","tail":50}</code> — Get last N log lines</li>
</ul>
</body></html>
"@
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.ContentType = 'text/html'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } else {
            $response.StatusCode = 404
            $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"error":"not_found"}')
            $response.ContentType = 'application/json'
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        $response.Close()
    } catch {
        Write-ApiLog "Request handler error: $($_.Exception.Message)"
    }
}

$listener.Stop()
