#Requires -Version 5.1
<#
  TorApiClient.ps1 - Example WebSocket client for Tor SOCKS Proxy API

  Demonstrates connecting to the WebSocket API and interacting with Tor.
  Run this after installing the v2.0+ installer.

  Usage:
    .\TorApiClient.ps1            # Connect and receive status updates
    .\TorApiClient.ps1 -Command status
    .\TorApiClient.ps1 -Command newnym
    .\TorApiClient.ps1 -Command log -Tail 30
    .\TorApiClient.ps1 -Command restart
    .\TorApiClient.ps1 -Command circuit
#>

[CmdletBinding()]
param(
    [string]$Uri = 'ws://127.0.0.1:9052/ws',
    [ValidateSet('status', 'newnym', 'restart', 'circuit', 'log', 'interactive')]
    [string]$Command = 'interactive',
    [int]$Tail = 20
)

$ErrorActionPreference = 'Continue'

function Connect-TorApiWebSocket {
    param([string]$WebSocketUri)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new($WebSocketUri)
    try {
        $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
        return @{ Socket = $ws; Token = $cts.Token }
    } catch {
        Write-Error "Failed to connect to Tor API at $WebSocketUri. Is TorApiService running? Error: $($_.Exception.Message)"
        exit 1
    }
}

function Send-ApiCommand {
    param(
        [System.Net.WebSockets.WebSocket]$Socket,
        [System.Threading.CancellationToken]$Token,
        [string]$Command,
        [hashtable]$Params = @{}
    )
    $payload = @{ cmd = $Command } + $Params
    $json = $payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $Token).GetAwaiter().GetResult()
}

function Receive-ApiMessage {
    param(
        [System.Net.WebSockets.WebSocket]$Socket,
        [System.Threading.CancellationToken]$Token
    )
    $buffer = New-Object byte[] 4096
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
    $result = $Socket.ReceiveAsync($segment, $Token).GetAwaiter().GetResult()
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
        return $null
    }
    return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
}

# Connect
Write-Host "Connecting to Tor API at $Uri ..." -ForegroundColor Cyan
$connection = Connect-TorApiWebSocket -WebSocketUri $Uri
$ws = $connection.Socket
$token = $connection.Token
Write-Host "Connected!" -ForegroundColor Green

if ($Command -eq 'interactive') {
    Write-Host ""
    Write-Host "=== Tor WebSocket API Interactive Client ===" -ForegroundColor Yellow
    Write-Host "Commands: status, newnym, restart, circuit, log, quit"
    Write-Host ""

    # Send initial status request
    Send-ApiCommand -Socket $ws -Token $token -Command 'status'
    Send-ApiCommand -Socket $ws -Token $token -Command 'log' -Params @{ tail = 10 }

    while ($true) {
        $userInput = Read-Host "tor>"
        if ($userInput -eq 'quit' -or $userInput -eq 'exit') { break }
        if ($userInput -eq 'status') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'status'
        } elseif ($userInput -eq 'newnym') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'newnym'
        } elseif ($userInput -eq 'restart') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'restart'
        } elseif ($userInput -eq 'circuit') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'circuit'
        } elseif ($userInput -eq 'log') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'log' -Params @{ tail = $Tail }
        } elseif ($userInput -match '^log\s+(\d+)') {
            Send-ApiCommand -Socket $ws -Token $token -Command 'log' -Params @{ tail = [int]$matches[1] }
        } elseif ($userInput -eq 'help') {
            Write-Host "Commands: status, newnym, restart, circuit, log [N], quit"
        } else {
            Write-Host "Unknown command: $userInput (try 'help')"
        }
        Start-Sleep -Milliseconds 500
    }
} else {
    # One-shot command
    switch ($Command) {
        'status' {
            Send-ApiCommand -Socket $ws -Token $token -Command 'status'
            Start-Sleep -Milliseconds 500
            $response = Receive-ApiMessage -Socket $ws -Token $token
            if ($response) {
                $parsed = $response | ConvertFrom-Json
                Write-Output ($parsed.data | ConvertTo-Json -Depth 5)
            }
        }
        'newnym' {
            Send-ApiCommand -Socket $ws -Token $token -Command 'newnym'
            Start-Sleep -Milliseconds 500
            $response = Receive-ApiMessage -Socket $ws -Token $token
            Write-Output $response
        }
        'restart' {
            Send-ApiCommand -Socket $ws -Token $token -Command 'restart'
            Write-Host "Restart command sent."
        }
        'circuit' {
            Send-ApiCommand -Socket $ws -Token $token -Command 'circuit'
            Start-Sleep -Milliseconds 500
            $response = Receive-ApiMessage -Socket $ws -Token $token
            if ($response) {
                $parsed = $response | ConvertFrom-Json
                Write-Output ($parsed.data -join "`n")
            }
        }
        'log' {
            Send-ApiCommand -Socket $ws -Token $token -Command 'log' -Params @{ tail = $Tail }
            Start-Sleep -Milliseconds 500
            $response = Receive-ApiMessage -Socket $ws -Token $token
            if ($response) {
                $parsed = $response | ConvertFrom-Json
                Write-Output ($parsed.data -join "`n")
            }
        }
    }
}

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'Done', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
Write-Host "Disconnected."
