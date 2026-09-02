# DSH Server Setup

Run [DeepSeek Harness](https://github.com/deepseek-ai/dsh) on a remote VPS with reverse proxy, systemd service, and optional Basic Auth.

This is a production-tested setup for running DSH on an Ubuntu server (ARM64 or x64) with:

- **systemd service** — auto-restart, logging, persistence
- **Reverse proxy** — HTTP + WebSocket with `crypto.randomUUID` polyfill and loopback trust patch
- **Basic Auth** (optional) — protect your instance from unauthorized access
- **Telegram bridge** (optional) — notifications and cron alerts to your phone

## Architecture

```
Browser/Phone
     │
     ▼
dsh-proxy (0.0.0.0:3080)  ← Basic Auth + WebSocket + polyfills
     │
     ▼
DSH (127.0.0.1:3079)      ← bound to localhost only
     │
     ▼
DeepSeek API / MCP servers / Filesystem
```

## Quick Start

### 1. Install prerequisites

```bash
# Node.js (via fnm or nvm)
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install 24

# pnpm
npm install -g pnpm

# DSH
npm install -g @deepseek-ai/dsh

# http-proxy (for the reverse proxy)
cd dsh-proxy/node && npm install
```

### 2. Clone this repo

```bash
git clone git@github.com:YOUR_USER/dsh-server-setup.git
cd dsh-server-setup
```

### 3. Configure

Copy the example env and edit:

```bash
cp .env.example .env
# Edit .env with your settings
```

### 4. Install the systemd service

```bash
sudo cp systemd/dsh.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dsh
sudo systemctl start dsh
```

### 5. Verify

```bash
# Check DSH is running
curl -s http://127.0.0.1:3079/ | head -5

# Check proxy is accessible
curl -s http://YOUR_SERVER_IP:3080/ | head -5
```

## Files

```
dsh-server-setup/
├── README.md                    # This file
├── .env.example                 # Environment variables template
├── run.sh                       # DSH + proxy wrapper script
├── systemd/
│   └── dsh.service              # Systemd unit file
├── dsh-proxy/
│   └── node/
│       ├── index.js             # Proxy entry point
│       ├── proxy-core.js        # HTTP + WebSocket reverse proxy
│       └── package.json         # Dependencies (http-proxy)
└── scripts/
    ├── setup.sh                 # First-time setup script
    └── update.sh                # Update script
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DSH_PORT` | `3079` | DSH listen port (localhost only) |
| `PROXY_PORT` | `3080` | Proxy listen port (0.0.0.0) |
| `DSH_HOME` | `~/.dsh` | DSH home directory |
| `PROXY_USERNAME` | *(empty)* | Basic Auth username (empty = no auth) |
| `PROXY_PASSWORD` | *(empty)* | Basic Auth password |

### Basic Auth

To enable authentication, set both `PROXY_USERNAME` and `PROXY_PASSWORD` in the systemd service or `.env`:

```ini
Environment=PROXY_USERNAME=admin
Environment=PROXY_PASSWORD=your-secure-password
```

Without auth, anyone with the URL can access your DSH instance.

### HTTPS

This proxy does **not** handle HTTPS. For production, put a TLS terminator in front:

- **Cloudflare Tunnel** — `cloudflared tunnel --url http://127.0.0.1:3080`
- **Caddy** — auto HTTPS with `reverse_proxy localhost:3080`
- **Nginx + Let's Encrypt** — standard reverse proxy config

## Reverse Proxy Features

The included proxy (`dsh-proxy`) does more than simple forwarding:

### `crypto.randomUUID` polyfill
DSH's frontend uses `crypto.randomUUID()` for RPC IDs, but this API is only available in secure contexts (HTTPS/localhost). When accessing via LAN IP or public URL, the polyfill injects a compatible implementation using `getRandomValues()`.

### Loopback trust patch
DSH 0.1.1+ checks `location.hostname` to determine if the browser is local. Non-loopback hosts get degraded behavior (memory-only mode, no settings). The proxy patches the client JS to treat proxied connections as loopback, enabling full functionality.

### WebSocket support
The proxy forwards WebSocket connections for real-time DSH features (streaming, live updates).

### Public path whitelist
`/manifest.webmanifest`, `/favicon.svg`, and `/favicon.ico` are served without auth so browsers can fetch PWA metadata without credentials.

## Telegram Integration (Optional)

For cron notifications to Telegram, see the `cron-telegram-bridge` setup:

```bash
# Create the bridge script at ~/.dsh/scripts/cron-telegram-bridge.js
# Create systemd service
sudo cp systemd/cron-telegram-bridge.service /etc/systemd/system/
sudo systemctl enable cron-telegram-bridge
sudo systemctl start cron-telegram-bridge
```

## Troubleshooting

### DSH won't start
- Check logs: `journalctl -u dsh -f`
- Verify Node.js is in PATH: `which node`
- Check DSH home exists: `ls ~/.dsh/`

### Proxy returns 502
- DSH may not be ready yet (wait 10-30 seconds after start)
- Check DSH is listening: `curl http://127.0.0.1:3079/`
- Check ports: `ss -tlnp | grep -E '3079|3080'`

### WebSocket not working
- The proxy must forward `Upgrade` and `Connection` headers
- If behind another proxy (nginx/Caddy), ensure WebSocket is enabled there too

### Settings page shows "unavailable in this browser"
- The loopback patch may not be applied
- Check the proxy is using the patched `proxy-core.js`
- Clear browser cache and reload

## License

MIT
