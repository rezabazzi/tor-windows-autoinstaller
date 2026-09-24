Start-Sleep -Seconds 2

$passed = 0
$failed = 0

Write-Host "=== Test 1: REST API ==="
try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9052/api/status' -UseBasicParsing
    Write-Host ("  running=" + $r.running + " pid=" + $r.pid + " memMB=" + $r.memMB)
    Write-Host "  PASSED"
    $passed++
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    $failed++
}

Write-Host "=== Test 2: WebSocket Status ==="
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    
    $cmd = '{"cmd":"status"}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    
    $buf = New-Object byte[] 4096
    $s = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $result = $ws.ReceiveAsync($s, $cts.Token).GetAwaiter().GetResult()
    $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
    Write-Host ("  " + $resp)
    
    # Proper close
    $ws.CloseOutputAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
    
    Write-Host "  PASSED"
    $passed++
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    $failed++
}

Write-Host "=== Test 3: Concurrent Clients ==="
try {
    $clients = @()
    for ($i = 0; $i -lt 3; $i++) {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
        $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
        $clients += [PSCustomObject]@{ ws = $ws; cts = $cts; id = $i }
    }
    Write-Host "  3 clients connected"
    
    foreach ($c in $clients) {
        $cmd = '{"cmd":"status"}'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
        $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
        $c.ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $c.cts.Token).GetAwaiter().GetResult()
    }
    
    $received = 0
    foreach ($c in $clients) {
        $buf = New-Object byte[] 4096
        $s = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
        $r = $c.ws.ReceiveAsync($s, $c.cts.Token).GetAwaiter().GetResult()
        $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
        if ($resp -match '"type":"status"') { $received++ }
    }
    
    Write-Host ("  $received/3 received responses")
    
    foreach ($c in $clients) {
        $c.ws.CloseOutputAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $c.cts.Token).GetAwaiter().GetResult()
    }
    
    Write-Host "  PASSED"
    $passed++
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    $failed++
}

Write-Host "=== Test 4: WebSocket Log Command ==="
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    
    $cmd = '{"cmd":"log","tail":3}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    
    $buf = New-Object byte[] 4096
    $s = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $result = $ws.ReceiveAsync($s, $cts.Token).GetAwaiter().GetResult()
    $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
    
    if ($resp -match '"type":"log"') {
        Write-Host "  PASSED"
        $passed++
    } else {
        Write-Host ("  Unexpected: " + $resp)
        $failed++
    }
    
    $ws.CloseOutputAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    $failed++
}

Write-Host "=== Test 5: Error Handling ==="
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    
    $cmd = '{"cmd":"invalid_command"}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    
    $buf = New-Object byte[] 4096
    $s = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $result = $ws.ReceiveAsync($s, $cts.Token).GetAwaiter().GetResult()
    $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
    
    if ($resp -match '"type":"error"') {
        Write-Host "  PASSED"
        $passed++
    } else {
        Write-Host ("  Unexpected: " + $resp)
        $failed++
    }
    
    $ws.CloseOutputAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    $failed++
}

Write-Host ""
Write-Host "=== RESULTS: $passed passed, $failed failed ==="
if ($failed -eq 0) { Write-Host "ALL TESTS PASSED" -ForegroundColor Green }
