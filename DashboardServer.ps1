# Web Dashboard Server for Port 8383
# Serves the HTML dashboard that connects to the WebSocket API

$DashboardDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = 8383

Write-Host "Starting Web Dashboard on http://127.0.0.1:$Port"

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

Write-Host "Dashboard running at http://127.0.0.1:$Port"
Write-Host "Press Ctrl+C to stop"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
        # Serve dashboard HTML
        $htmlPath = Join-Path $DashboardDir "dashboard.html"
        if (Test-Path $htmlPath) {
            $html = Get-Content $htmlPath -Raw -Encoding UTF8
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } else {
            $response.StatusCode = 404
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Dashboard not found")
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        $response.Close()
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}

$listener.Stop()
