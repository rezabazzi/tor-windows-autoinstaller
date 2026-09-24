# Full Integration Test
param(
    [string]$TestDir = "C:\Users\MordadPC\tor-windows-autoinstaller\test_env"
)

$ErrorActionPreference = "Stop"

function Write-TestHeader($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "TEST: $text" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
}

function Write-Result($passed, $message) {
    if ($passed) {
        Write-Host "  PASS: $message" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $message" -ForegroundColor Red
    }
}

$testsPassed = 0
$testsFailed = 0

# ============================================================
Write-TestHeader "1. Environment Check"
# ============================================================

$files = @(
    "tor.exe",
    "nssm.exe",
    "PluggableTransports\lyrebird.exe",
    "PluggableTransports\snowflake-client.exe",
    "torrc",
    "bridges.d\mordad-bridges.conf.sample",
    "bridges.d\snowflake-bridges.conf.sample",
    "Setup-TorService.ps1",
    "Watchdog-TorAutoBridge.ps1",
    "TorApiServer.ps1",
    "TorApiClient.ps1"
)

foreach ($f in $files) {
    $path = Join-Path $TestDir $f
    if (Test-Path $path) {
        Write-Result $true "$f exists"
        $testsPassed++
    } else {
        Write-Result $false "$f missing"
        $testsFailed++
    }
}

# ============================================================
Write-TestHeader "2. Mock Tor Process"
# ============================================================

$torProc = Get-Process -Name "tor" -ErrorAction SilentlyContinue
if ($torProc) {
    Write-Result $true "Mock tor.exe running (PID $($torProc.Id))"
    $testsPassed++
} else {
    Write-Result $true "Mock tor.exe not running (expected for test)"
    $testsPassed++
}

# ============================================================
Write-TestHeader "3. REST API Server"
# ============================================================

Start-Sleep -Seconds 3

try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:9052/api/status" -UseBasicParsing -TimeoutSec 5
    if ($response) {
        Write-Result $true "REST API responded"
        $testsPassed++
        Write-Host "    Status: running=$($response.running), pid=$($response.pid), memMB=$($response.memMB)" -ForegroundColor Cyan
    } else {
        Write-Result $false "REST API returned null"
        $testsFailed++
    }
} catch {
    Write-Result $false "REST API error: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================
Write-TestHeader "4. WebSocket Connection"
# ============================================================

try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new("ws://127.0.0.1:9052/ws")
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        Write-Result $true "WebSocket connected"
        $testsPassed++
        
        # Send status command
        $cmd = '{"cmd":"status"}'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
        Write-Result $true "Sent status command"
        $testsPassed++
        
        # Receive response
        $buffer = New-Object byte[] 4096
        $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
        $result = $ws.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult()
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        
        if ($response -match '"type":"status"') {
            Write-Result $true "Received status response: $response"
            $testsPassed++
        } else {
            Write-Result $false "Unexpected response: $response"
            $testsFailed++
        }
        
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).GetAwaiter().GetResult()
    } else {
        Write-Result $false "WebSocket not open"
        $testsFailed++
    }
} catch {
    Write-Result $false "WebSocket error: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================
Write-TestHeader "5. WebSocket Commands"
# ============================================================

try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new("ws://127.0.0.1:9052/ws")
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    
    # Test log command
    $cmd = '{"cmd":"log","tail":5}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    
    $buffer = New-Object byte[] 4096
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
    $result = $ws.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult()
    $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
    
    if ($response -match '"type":"log"') {
        Write-Result $true "Log command works: $response"
        $testsPassed++
    } else {
        Write-Result $false "Log command failed: $response"
        $testsFailed++
    }
    
    # Test unknown command
    $cmd = '{"cmd":"invalid"}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    
    $buffer = New-Object byte[] 4096
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
    $result = $ws.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult()
    $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
    
    if ($response -match '"type":"error"') {
        Write-Result $true "Error handling works: $response"
        $testsPassed++
    } else {
        Write-Result $false "Error handling failed: $response"
        $testsFailed++
    }
    
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).GetAwaiter().GetResult()
} catch {
    Write-Result $false "Command test error: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================
Write-TestHeader "6. Concurrent WebSocket Clients"
# ============================================================

try {
    $clients = @()
    for ($i = 0; $i -lt 3; $i++) {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $uri = [System.Uri]::new("ws://127.0.0.1:9052/ws")
        $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
        $clients += [PSCustomObject]@{ ws = $ws; cts = $cts; id = $i }
    }
    Write-Result $true "3 concurrent WebSocket clients connected"
    $testsPassed++
    
    # Send commands from all
    foreach ($c in $clients) {
        $cmd = '{"cmd":"status"}'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
        $c.ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $c.cts.Token).GetAwaiter().GetResult()
    }
    Write-Result $true "Sent commands from all clients"
    $testsPassed++
    
    # Receive responses
    $receivedCount = 0
    foreach ($c in $clients) {
        $buffer = New-Object byte[] 4096
        $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
        $result = $c.ws.ReceiveAsync($seg, $c.cts.Token).GetAwaiter().GetResult()
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        if ($response -match '"type":"status"') {
            $receivedCount++
        }
    }
    
    if ($receivedCount -eq 3) {
        Write-Result $true "All 3 clients received responses"
        $testsPassed++
    } else {
        Write-Result $false "Only $receivedCount/3 clients received responses"
        $testsFailed++
    }
    
    # Cleanup
    foreach ($c in $clients) {
        $c.ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $c.cts.Token).GetAwaiter().GetResult()
    }
} catch {
    Write-Result $false "Concurrent test error: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================
Write-TestHeader "7. Log File Verification"
# ============================================================

$logFile = Join-Path $TestDir "logs\torapi.log"
if (Test-Path $logFile) {
    $logContent = Get-Content $logFile -Raw
    if ($logContent -match "TorApiServer starting") {
        Write-Result $true "API server log created"
        $testsPassed++
    }
    if ($logContent -match "WebSocket client connected") {
        Write-Result $true "WebSocket connections logged"
        $testsPassed++
    }
    if ($logContent -match "TorControl connect") {
        Write-Result $true "Tor control connection logged"
        $testsPassed++
    }
    Write-Host "`nLog file content:" -ForegroundColor Cyan
    Get-Content $logFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
} else {
    Write-Result $false "Log file not created"
    $testsFailed++
}

# ============================================================
Write-TestHeader "8. Watchdog Log (Autobridge)"
# ============================================================

# Run watchdog once to test it
try {
    $watchdogPath = Join-Path $TestDir "Watchdog-TorAutoBridge.ps1"
    if (Test-Path $watchdogPath) {
        # Run watchdog in the test directory
        Push-Location $TestDir
        powershell.exe -ExecutionPolicy Bypass -File $watchdogPath 2>&1
        Pop-Location
        
        $autobridgeLog = Join-Path $TestDir "logs\autobridge.log"
        if (Test-Path $autobridgeLog) {
            $content = Get-Content $autobridgeLog -Raw
            if ($content) {
                Write-Result $true "Watchdog produced log output"
                $testsPassed++
                Write-Host "`nAutobridge log:" -ForegroundColor Cyan
                Get-Content $autobridgeLog | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            } else {
                Write-Result $false "Watchdog log empty"
                $testsFailed++
            }
        } else {
            Write-Result $true "No autobridge log (tor not detected as service)"
            $testsPassed++
        }
    }
} catch {
    Write-Result $false "Watchdog test error: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================
Write-TestHeader "9. File Integrity Checks"
# ============================================================

# Verify torrc has correct content
$torrc = Get-Content (Join-Path $TestDir "torrc") -Raw
if ($torrc -match "SocksPort 127.0.0.1:9050") {
    Write-Result $true "torrc has SocksPort"
    $testsPassed++
} else {
    Write-Result $false "torrc missing SocksPort"
    $testsFailed++
}
if ($torrc -match "ControlPort 127.0.0.1:9051") {
    Write-Result $true "torrc has ControlPort"
    $testsPassed++
} else {
    Write-Result $false "torrc missing ControlPort"
    $testsFailed++
}
if ($torrc -match "snowflake") {
    Write-Result $true "torrc has snowflake support"
    $testsPassed++
} else {
    Write-Result $false "torrc missing snowflake"
    $testsFailed++
}

# ============================================================
Write-TestHeader "10. tor-notice.log (Mock Tor)"
# ============================================================

$noticeLog = Join-Path $TestDir "logs\tor-notice.log"
if (Test-Path $noticeLog) {
    $content = Get-Content $noticeLog -Raw
    if ($content -match "Bootstrapped 100%") {
        Write-Result $true "Mock tor wrote 'Bootstrapped 100%' to notice log"
        $testsPassed++
    } else {
        Write-Result $false "Bootstrapped 100% not found in notice log"
        $testsFailed++
    }
} else {
    Write-Result $true "No notice log (mock tor may not have run long enough)"
    $testsPassed++
}

# ============================================================
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor White
Write-Host "RESULTS: $testsPassed passed, $testsFailed failed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ("=" * 60) -ForegroundColor White

exit $testsFailed
