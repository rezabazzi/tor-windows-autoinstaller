<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tor SOCKS Proxy v2.0 - Dashboard</title>
<style>
:root {
    --bg: #0d1117;
    --card: #161b22;
    --border: #30363d;
    --text: #e6edf3;
    --muted: #7d8590;
    --green: #3fb950;
    --red: #f85149;
    --blue: #58a6ff;
    --yellow: #d29922;
    --orange: #db6d28;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
}
.container {
    max-width: 1000px;
    margin: 0 auto;
    padding: 20px;
}
header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: 30px;
}
header h1 {
    font-size: 1.5em;
    color: var(--text);
}
header .version {
    color: var(--muted);
    font-size: 0.9em;
}
.status-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border-radius: 20px;
    font-size: 0.85em;
    font-weight: 500;
}
.status-badge.connected { background: rgba(63, 185, 80, 0.2); color: var(--green); }
.status-badge.disconnected { background: rgba(248, 81, 73, 0.2); color: var(--red); }
.status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: currentColor;
}
.grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
}
.card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 20px;
}
.card h2 {
    font-size: 0.8em;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--muted);
    margin-bottom: 8px;
}
.card .value {
    font-size: 1.8em;
    font-weight: bold;
    color: var(--text);
}
.card .sub {
    font-size: 0.8em;
    color: var(--muted);
    margin-top: 4px;
}
.controls {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-bottom: 24px;
}
.btn {
    padding: 10px 16px;
    border: 1px solid var(--border);
    background: var(--card);
    color: var(--text);
    border-radius: 8px;
    cursor: pointer;
    font-size: 0.9em;
    font-weight: 500;
    transition: all 0.2s;
}
.btn:hover {
    background: #21262d;
    border-color: var(--muted);
}
.btn.primary {
    background: var(--blue);
    border-color: var(--blue);
    color: white;
}
.btn.primary:hover { background: #4393e6; }
.btn.danger {
    border-color: var(--red);
    color: var(--red);
}
.btn.danger:hover { background: rgba(248, 81, 73, 0.1); }
.btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}
.section {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 20px;
    margin-bottom: 16px;
}
.section h3 {
    font-size: 1em;
    margin-bottom: 12px;
    color: var(--text);
}
.log-container {
    background: #000;
    border-radius: 8px;
    padding: 12px;
    max-height: 300px;
    overflow-y: auto;
    font-family: 'Courier New', monospace;
    font-size: 0.8em;
    line-height: 1.4;
}
.log-line {
    padding: 2px 0;
    border-bottom: 1px solid #1a1a1a;
    word-break: break-all;
}
.log-line.error { color: var(--red); }
.log-line.warn { color: var(--yellow); }
.log-line.bootstrap { color: var(--green); }
.log-line.info { color: var(--blue); }
.bridges-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.bridge-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 8px;
}
.bridge-item .name { font-weight: 500; }
.bridge-item .transport {
    font-size: 0.8em;
    color: var(--muted);
    background: #21262d;
    padding: 2px 8px;
    border-radius: 4px;
}
.bridge-item.active { border-color: var(--green); }
.full-width { grid-column: 1 / -1; }
footer {
    text-align: center;
    padding: 20px;
    color: var(--muted);
    font-size: 0.8em;
    border-top: 1px solid var(--border);
    margin-top: 40px;
}
</style>
</head>
<body>
<div class="container">
    <header>
        <div>
            <h1>Tor SOCKS Proxy <span class="version">v2.0</span></h1>
            <p style="color: var(--muted); margin-top: 4px;">Self-healing bridge automation</p>
        </div>
        <div id="connectionStatus" class="status-badge disconnected">
            <span class="status-dot"></span>
            <span id="connectionText">Disconnected</span>
        </div>
    </header>

    <div class="grid">
        <div class="card">
            <h2>Tor Status</h2>
            <div id="torStatus" class="value">Unknown</div>
            <div id="torUptime" class="sub">Uptime: --</div>
        </div>
        <div class="card">
            <h2>Process</h2>
            <div id="torPid" class="value">--</div>
            <div id="torMem" class="sub">Memory: --</div>
        </div>
        <div class="card">
            <h2>Traffic</h2>
            <div id="trafficIn" class="value">--</div>
            <div class="sub">In / Out</div>
        </div>
        <div class="card">
            <h2>Bridge</h2>
            <div id="bridgeStatus" class="value">Direct</div>
            <div id="bridgeTransport" class="sub">Transport: --</div>
        </div>
    </div>

    <div class="controls">
        <button class="btn primary" onclick="refreshStatus()">Refresh</button>
        <button class="btn" onclick="requestNewIdentity()">New Identity</button>
        <button class="btn danger" onclick="restartTor()">Restart Tor</button>
        <button class="btn" onclick="getCircuitInfo()">Circuit Info</button>
        <button class="btn" onclick="loadLogs()">View Logs</button>
    </div>

    <div class="section">
        <h3>Active Bridges</h3>
        <div id="bridgesList" class="bridges-list">
            <div class="bridge-item">
                <span class="name">No bridges active</span>
                <span class="transport">Direct connection</span>
            </div>
        </div>
    </div>

    <div class="section full-width">
        <h3>Event Log</h3>
        <div id="logContainer" class="log-container">
            <div class="log-line">Connecting to API...</div>
        </div>
    </div>

    <footer>
        Tor Windows AutoInstaller v2.0 | WebSocket API on port 9052 | Dashboard on port 8383
    </footer>
</div>

<script>
const API = 'http://127.0.0.1:9052';
let ws = null;
let reconnectTimer = null;
let isConnected = false;

function log(message, type = '') {
    const div = document.createElement('div');
    div.className = 'log-line ' + type;
    const time = new Date().toLocaleTimeString();
    div.textContent = `[${time}] ${message}`;
    const container = document.getElementById('logContainer');
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
}

function setConnection(connected) {
    isConnected = connected;
    const badge = document.getElementById('connectionStatus');
    const text = document.getElementById('connectionText');
    if (connected) {
        badge.className = 'status-badge connected';
        text.textContent = 'Connected';
    } else {
        badge.className = 'status-badge disconnected';
        text.textContent = 'Disconnected';
    }
}

function updateUI(data) {
    const torStatus = document.getElementById('torStatus');
    torStatus.textContent = data.running ? 'Running' : 'Stopped';
    torStatus.style.color = data.running ? 'var(--green)' : 'var(--red)';

    document.getElementById('torPid').textContent = data.pid || '--';
    document.getElementById('torMem').textContent = 'Memory: ' + (data.memMB || '--') + ' MB';
    document.getElementById('torUptime').textContent = 'Uptime: ' + formatUptime(data.uptime);
    document.getElementById('trafficIn').textContent = formatBytes(data.bytesRead) + ' / ' + formatBytes(data.bytesWritten);
}

function formatUptime(seconds) {
    if (!seconds || seconds < 0) return '--';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) return `${h}h ${m}m ${s}s`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
}

function formatBytes(bytes) {
    if (!bytes) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

async function refreshStatus() {
    try {
        const r = await fetch(`${API}/api/status`);
        if (r.ok) {
            const data = await r.json();
            updateUI(data);
            setConnection(true);
            log('Status refreshed: running=' + data.running, 'info');
        }
    } catch (e) {
        setConnection(false);
        log('Failed to refresh status: ' + e.message, 'error');
    }
}

async function requestNewIdentity() {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        log('WebSocket not connected', 'warn');
        return;
    }
    ws.send(JSON.stringify({ cmd: 'newnym' }));
    log('New identity requested', 'info');
}

async function restartTor() {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        log('WebSocket not connected', 'warn');
        return;
    }
    ws.send(JSON.stringify({ cmd: 'restart' }));
    log('Restart requested', 'warn');
}

async function getCircuitInfo() {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        log('WebSocket not connected', 'warn');
        return;
    }
    ws.send(JSON.stringify({ cmd: 'circuit' }));
    log('Circuit info requested', 'info');
}

async function loadLogs() {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        log('WebSocket not connected', 'warn');
        return;
    }
    ws.send(JSON.stringify({ cmd: 'log', tail: 50 }));
}

function connectWebSocket() {
    ws = new WebSocket(`ws://${API.replace('http://', '')}/ws`);

    ws.onopen = () => {
        setConnection(true);
        log('WebSocket connected', 'bootstrap');
        ws.send(JSON.stringify({ cmd: 'status' }));
    };

    ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            switch (msg.type) {
                case 'status':
                    updateUI(msg.data);
                    if (msg.data.bootstrapped) {
                        log('Bootstrapped 100%', 'bootstrap');
                    }
                    break;
                case 'log':
                    document.getElementById('logContainer').innerHTML = '';
                    if (Array.isArray(msg.data)) {
                        msg.data.forEach(line => {
                            let type = '';
                            if (line.includes('Bootstrapped 100%')) type = 'bootstrap';
                            else if (line.includes('error') || line.includes('Error')) type = 'error';
                            else if (line.includes('WARN')) type = 'warn';
                            log(line, type);
                        });
                    }
                    break;
                case 'circuit':
                    document.getElementById('logContainer').innerHTML = '';
                    if (Array.isArray(msg.data)) {
                        msg.data.forEach(line => log(line, 'info'));
                    }
                    break;
                case 'newnym':
                    log('New identity acknowledged', 'info');
                    break;
                case 'info':
                    log('Info: ' + JSON.stringify(msg.data), 'info');
                    break;
                case 'error':
                    log('Error: ' + msg.data, 'error');
                    break;
            }
        } catch (e) {
            log('Parse error: ' + e.message, 'error');
        }
    };

    ws.onclose = () => {
        setConnection(false);
        log('WebSocket disconnected - retrying in 3s', 'warn');
        reconnectTimer = setTimeout(connectWebSocket, 3000);
    };

    ws.onerror = () => {
        setConnection(false);
    };
}

// Initial connection
connectWebSocket();

// Periodic refresh
setInterval(() => {
    if (!isConnected) {
        refreshStatus();
    }
}, 5000);
</script>
</body>
</html>
