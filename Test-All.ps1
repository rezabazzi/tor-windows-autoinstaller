Start-Sleep -Seconds 3

Write-Host "=== Test 1: REST API ==="
try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9052/api/status' -UseBasicParsing
    Write-Host ("  running=" + $r.running + " pid=" + $r.pid + " memMB=" + $r.memMB)
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
}

Write-Host "=== Test 2: WebSocket ==="
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $uri = [System.Uri]::new('ws://127.0.0.1:9052/ws')
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    Write-Host "  Connected"
    
    $cmd = '{"cmd":"status"}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    Write-Host "  Sent command"
    
    $buf = New-Object byte[] 4096
    $s = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $result = $ws.ReceiveAsync($s, $cts.Token).GetAwaiter().GetResult()
    $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
    Write-Host ("  Received: " + $resp)
    
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
    Write-Host "  PASSED"
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
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
        Write-Host ("  Client $i connected")
    }
    
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
    
    Write-Host ("  $received/3 clients received responses")
    
    foreach ($c in $clients) {
        $c.ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $c.cts.Token).GetAwaiter().GetResult()
    }
    
    if ($received -eq 3) { Write-Host "  PASSED" } else { Write-Host "  FAILED" }
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
}

Write-Host "=== All tests complete ==="
