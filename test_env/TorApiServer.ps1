#Requires -Version 5.1
<#
  TorApiServer.ps1 - v2.0 WebSocket API for Tor SOCKS Proxy

  Provides real-time monitoring and control of Tor via WebSocket.
  Uses raw TcpListener with non-blocking client handling.

  Runs as a service via NSSM (registered by Setup-TorService.ps1).
#>

[CmdletBinding()]
param(
    [int]$ApiPort = 9052,
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

Write-ApiLog "TorApiServer starting on port $ApiPort..."

# ---- WebSocket helpers ----
function Get-WebSocketHandshakeResponse {
    param([string]$SecWebSocketKey)
    $magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    $hash = [System.Security.Cryptography.SHA1]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($SecWebSocketKey + $magic)
    )
    return [Convert]::ToBase64String($hash)
}

function Read-WebSocketFrame {
    param(
        [System.IO.Stream]$Stream,
        [int]$TimeoutMs = 2000
    )
    try {
        $header = New-Object byte[] 2
        $read = $Stream.Read($header, 0, 2)
        if ($read -lt 2) { return $null }

        $fin = ($header[0] -band 0x80) -ne 0
        $opcode = $header[0] -band 0x0F
        $masked = ($header[1] -band 0x80) -ne 0
        $len = $header[1] -band 0x7F

        if ($len -eq 126) {
            $ext = New-Object byte[] 2
            $Stream.Read($ext, 0, 2) | Out-Null
            $len = [BitConverter]::ToUInt16($ext, 0)
        } elseif ($len -eq 127) {
            $ext = New-Object byte[] 8
            $Stream.Read($ext, 0, 8) | Out-Null
            $len = [BitConverter]::ToUInt64($ext, 0)
        }

        $mask = $null
        if ($masked) {
            $mask = New-Object byte[] 4
            $Stream.Read($mask, 0, 4) | Out-Null
        }

        if ($len -gt 1MB) { return $null }

        $data = New-Object byte[] $len
        $total = 0
        while ($total -lt $len) {
            $r = $Stream.Read($data, $total, $len - $total)
            if ($r -eq 0) { return $null }
            $total += $r
        }

        if ($masked) {
            for ($i = 0; $i -lt $len; $i++) {
                $data[$i] = $data[$i] -bxor $mask[$i % 4]
            }
        }

        return @{
            Opcode = $opcode
            Data = $data
            Close = ($opcode -eq 0x08)
        }
    } catch {
        return $null
    }
}

function Write-WebSocketFrame {
    param(
        [System.IO.Stream]$Stream,
        [string]$Message
    )
    $data = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $len = $data.Length

    if ($len -lt 126) {
        $frame = New-Object byte[] (2 + $len)
        $frame[0] = 0x81
        $frame[1] = $len
        [Array]::Copy($data, 0, $frame, 2, $len)
    } else {
        $frame = New-Object byte[] (4 + $len)
        $frame[0] = 0x81
        $frame[1] = 126
        $frame[2] = ($len -shr 8) -band 0xFF
        $frame[3] = $len -band 0xFF
        [Array]::Copy($data, 0, $frame, 4, $len)
    }

    $Stream.Write($frame, 0, $frame.Length)
    $Stream.Flush()
}

# ---- HTTP request parser ----
function Get-HttpRequest {
    param([System.IO.Stream]$Stream)
    $buffer = New-Object byte[] 4096
    $sb = New-Object System.Text.StringBuilder

    while ($true) {
        $read = $Stream.Read($buffer, 0, 4096)
        if ($read -eq 0) { return $null }
        $sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)) | Out-Null
        $content = $sb.ToString()
        $hdrEnd = $content.IndexOf("`r`n`r`n")
        if ($hdrEnd -ge 0) {
            $headers = $content.Substring(0, $hdrEnd)
            $lines = $headers -split "`r`n"
            $requestLine = $lines[0]
            $parts = $requestLine -split ' '
            if ($parts.Count -lt 2) { return $null }

            $result = @{
                Method = $parts[0]
                Path = $parts[1]
                Headers = @{}
                WebSocketKey = $null
            }

            for ($i = 1; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match '^([^:]+):\s*(.+)$') {
                    $result.Headers[$matches[1].Trim()] = $matches[2].Trim()
                }
            }

            if ($result.Headers.ContainsKey('Sec-WebSocket-Key')) {
                $result.WebSocketKey = $result.Headers['Sec-WebSocket-Key']
            }

            return $result
        }
    }
}

function Send-HttpResponse {
    param(
        [System.IO.Stream]$Stream,
        [int]$StatusCode,
        [string]$ContentType,
        [byte[]]$Body
    )
    $statusText = switch ($StatusCode) {
        200 { 'OK' }
        404 { 'Not Found' }
        default { 'Error' }
    }
    $headers = "HTTP/1.1 $StatusCode $statustext`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $hdr = [System.Text.Encoding]::UTF8.GetBytes($headers)
    $Stream.Write($hdr, 0, $hdr.Length)
    if ($body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

# ---- Tor control ----
$torTcp = $null
$torReader = $null
$torWriter = $null

function Connect-TorControl {
    param(
        [string]$HostName = '127.0.0.1',
        [int]$ControlPort = 9051
    )
    try {
        if ($torTcp) {
            try { $torTcp.Close() } catch { Write-ApiLog "Close failed: $($_.Exception.Message)" }
        }
        $torTcp = New-Object System.Net.Sockets.TcpClient
        $torTcp.Connect($HostName, $ControlPort)
        $stream = $torTcp.GetStream()
        $torReader = New-Object System.IO.StreamReader($stream)
        $torWriter = New-Object System.IO.StreamWriter($stream)
        $torWriter.AutoFlush = $true

        $greeting = $torReader.ReadLine()

        $cookiePath = Join-Path $AppDir 'control_auth_cookie'
        if (-not (Test-Path $cookiePath)) {
            $cookiePath = (Get-ChildItem -Path $AppDir -Filter 'control_auth_cookie' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }
        if ($cookiePath -and (Test-Path $cookiePath)) {
            $cookie = (Get-Content $CookiePath -Encoding Byte | ForEach-Object { '{0:X2}' -f $_ }) -replace ' ',''
            $torWriter.WriteLine("AUTHENTICATE $cookie")
            $resp = $torReader.ReadLine()
            if ($resp -like '250*') { return $true }
        }

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
            if (-not (Connect-TorControl -HostName $TorControlHost -ControlPort $TorControlPort)) {
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
        $version = Send-TorCommand 'GETINFO version'
        $traffic = Send-TorCommand 'GETINFO traffic/read traffic/written'
        $uptime  = Send-TorCommand 'GETINFO uptime'

        $ver = if ($version.success -and $version.data) {
            ($version.data | Where-Object { $_ -match 'version=' } | ForEach-Object {
                if ($_ -match 'version="?([^"\s]+)"?') { $matches[1] } else { $_ }
            }) -join ' '
        } else { 'unknown' }

        $read = 0; $written = 0
        if ($traffic.success) {
            foreach ($l in $traffic.data) {
                if ($l -match 'traffic/read=(\d+)') { $read = [long]$matches[1] }
                if ($l -match 'traffic/written=(\d+)') { $written = [long]$matches[1] }
            }
        }

        $up = 0
        if ($uptime.success -and $uptime.data -match 'uptime=(\d+)') {
            $up = [long]$matches[1]
        }

        $torProc = Get-Process -Name 'tor' -ErrorAction SilentlyContinue
        $running = $null -ne $torProc
        $procPid = if ($torProc) { $torProc.Id } else { 0 }
        $mem = if ($torProc) { [math]::Round($torProc.WorkingSet64 / 1MB, 2) } else { 0 }

        return @{
            timestamp   = (Get-Date).ToString('o')
            running     = $running
            pid         = $procPid
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

# ---- WebSocket client management ----
$webSocketClients = [System.Collections.Generic.List[PSCustomObject]]::new()
$cts = New-Object System.Threading.CancellationTokenSource

# Status push loop
$pushTimer = New-Object System.Timers.Timer
$pushTimer.Interval = $StatusIntervalSeconds * 1000
$pushTimer.AutoReset = $true
$pushTimer.Add_Elapsed({
    $status = Get-TorStatus
    if (Test-Path $NoticeLog) {
        $lastLine = Get-Content $NoticeLog -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine -match 'Bootstrapped 100%') { $status.bootstrapped = $true }
    }
    $json = @{ type = 'status'; data = $status } | ConvertTo-Json -Compress
    $badClients = @()
    foreach ($clientInfo in $webSocketClients) {
        try {
            if ($clientInfo.Client.Connected) {
                Write-WebSocketFrame -Stream $clientInfo.Stream -Message $json
            } else {
                $badClients.Add($clientInfo)
            }
        } catch {
            $badClients.Add($clientInfo)
        }
    }
    foreach ($c in $badClients) {
        $webSocketClients.Remove($c) | Out-Null
        try { $c.Client.Close() } catch {}
    }
})
$pushTimer.Start()

Write-ApiLog "Status push timer started (${StatusIntervalSeconds}s interval)"

# ---- Main TCP listener ----
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $ApiPort)
$listener.Start()
Write-ApiLog "TCP listener started on 127.0.0.1:$ApiPort"

# Use a simple non-blocking approach with a pool of client handlers
$clientPool = [System.Collections.Generic.List[System.Management.Automation.PowerShell]]::new()

while ($true) {
    try {
        # Check for new connections (non-blocking)
        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()

            $request = Get-HttpRequest -Stream $stream
            if ($null -eq $request) { $client.Close(); continue }

            if ($request.WebSocketKey) {
                $accept = Get-WebSocketHandshakeResponse -SecWebSocketKey $request.WebSocketKey
                $response = "HTTP/1.1 101 Switching Protocols`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Accept: $accept`r`n`r`n"
                $hdr = [System.Text.Encoding]::UTF8.GetBytes($response)
                $stream.Write($hdr, 0, $hdr.Length)
                $stream.Flush()

                $clientInfo = [PSCustomObject]@{
                    Client = $client
                    Stream = $stream
                }
                $webSocketClients.Add($clientInfo) | Out-Null
                Write-ApiLog "WebSocket client connected ($($webSocketClients.Count) total)"
                continue
            }

            # REST API
            if ($request.Path -eq '/api/status') {
                $status = Get-TorStatus
                if (Test-Path $NoticeLog) {
                    $lastLines = Get-Content $NoticeLog -Tail 5 -ErrorAction SilentlyContinue
                    if ($lastLines -match 'Bootstrapped 100%') { $status.bootstrapped = $true }
                }
                $json = $status | ConvertTo-Json -Compress
                $body = [System.Text.Encoding]::UTF8.GetBytes($json)
                Send-HttpResponse -Stream $stream -StatusCode 200 -ContentType 'application/json' -Body $body
            } elseif ($request.Path -eq '/api/ping') {
                $json = @{ status = 'ok'; time = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
                $body = [System.Text.Encoding]::UTF8.GetBytes($json)
                Send-HttpResponse -Stream $stream -StatusCode 200 -ContentType 'application/json' -Body $body
            } else {
                $json = @{ error = 'not_found' } | ConvertTo-Json -Compress
                $body = [System.Text.Encoding]::UTF8.GetBytes($json)
                Send-HttpResponse -Stream $stream -StatusCode 404 -ContentType 'application/json' -Body $body
            }
            $client.Close()
        }

        # Handle WebSocket clients (non-blocking check)
        $badClients = @()
        foreach ($clientInfo in $webSocketClients) {
            try {
                $stream = $clientInfo.Stream
                if (-not $clientInfo.Client.Connected) {
                    $badClients.Add($clientInfo)
                    continue
                }

                # Non-blocking check for data
                if ($stream.DataAvailable) {
                    $frame = Read-WebSocketFrame -Stream $stream -TimeoutMs 100
                    if ($null -eq $frame) { continue }
                    if ($frame.Close) {
                        $badClients.Add($clientInfo)
                        continue
                    }

                    $msg = [System.Text.Encoding]::UTF8.GetString($frame.Data)
                    try {
                        $cmd = $msg | ConvertFrom-Json
                        switch ($cmd.cmd) {
                            'status' {
                                $st = Get-TorStatus
                                $reply = @{ type = 'status'; data = $st } | ConvertTo-Json -Compress
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                            'restart' {
                                $nssm = Join-Path $AppDir 'nssm.exe'
                                if (Test-Path $nssm) {
                                    & $nssm restart TorService 2>&1 | Out-Null
                                    $reply = @{ type = 'info'; data = 'restart_requested' } | ConvertTo-Json -Compress
                                } else {
                                    $reply = @{ type = 'error'; data = 'nssm_not_found' } | ConvertTo-Json -Compress
                                }
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                            'newnym' {
                                $res = Send-TorCommand 'SIGNAL NEWNYM'
                                $reply = @{ type = 'newnym'; data = $res } | ConvertTo-Json -Compress
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                            'circuit' {
                                $res = Send-TorCommand 'GETINFO circuit-status'
                                $reply = @{ type = 'circuit'; data = $res.data } | ConvertTo-Json -Compress
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                            'log' {
                                $tail = if ($cmd.tail) { [int]$cmd.tail } else { 20 }
                                $lines = if (Test-Path $NoticeLog) { Get-Content $NoticeLog -Tail $tail } else { @() }
                                $reply = @{ type = 'log'; data = $lines } | ConvertTo-Json -Compress
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                            default {
                                $reply = @{ type = 'error'; data = "unknown_command: $($cmd.cmd)" } | ConvertTo-Json -Compress
                                Write-WebSocketFrame -Stream $stream -Message $reply
                            }
                        }
                    } catch {
                        $err = @{ type = 'error'; data = "parse_error: $($_.Exception.Message)" } | ConvertTo-Json -Compress
                        try { Write-WebSocketFrame -Stream $stream -Message $err } catch {}
                    }
                }
            } catch {
                $badClients.Add($clientInfo)
            }
        }
        foreach ($c in $badClients) {
            $webSocketClients.Remove($c) | Out-Null
            try { $c.Client.Close() } catch {}
        }

        Start-Sleep -Milliseconds 100
    } catch {
        Write-ApiLog "Request handler error: $($_.Exception.Message)"
    }
}

$listener.Stop()
