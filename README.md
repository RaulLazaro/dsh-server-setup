# DSH Server Setup

Run [DeepSeek Harness](https://github.com/deepseek-ai/dsh) on a remote VPS with reverse proxy as a DSH plugin.

This is a production-tested setup for running DSH on an Ubuntu server (ARM64 or x64) with:

- **systemd service** — auto-restart, logging, persistence
- **Reverse proxy plugin** — [smanx/dsh-proxy](https://github.com/smanx/dsh-proxy) runs inside DSH, configurable from Settings
- **Basic Auth** (optional) — protect your instance from unauthorized access
- **Telegram bridge** (optional) — notifications and cron alerts to your phone

## Architecture

```
Browser/Phone
     │
     ▼
DSH (0.0.0.0:3080)        ← dsh-proxy plugin handles external access
     │
     ▼
DSH core (127.0.0.1:3079) ← internal port
     │
     ▼
DeepSeek API / MCP servers / Filesystem
```

The proxy runs as a DSH plugin — no separate process needed. It starts and stops with `dsh web`.

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
```

### 2. Create a web profile

```bash
mkdir -p ~/.dsh/profiles/web
cd ~/.dsh/profiles/web
```

### 3. Add plugins

```bash
# Core (already installed with dsh)
# Reverse proxy
pnpm add github:smanx/dsh-proxy

# Your other plugins
pnpm add dshmarket dsh-cron dsh-mnemon dsh-free-search dsh-config-manager ...
```

### 4. Configure the profile

**`~/.dsh/profiles/web/package.json`:**

```json
{
  "name": "dsh-profile-web",
  "private": true,
  "dependencies": {
    "@smanx/dsh-proxy": "github:smanx/dsh-proxy",
    "dshmarket": "^1.39.0"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "@smanx/dsh-proxy",
        "dshmarket"
      ]
    }
  }
}
```

**`~/.dsh/profiles/web/cordis.patch.yml`:**

```yaml
# dsh-proxy: reverse proxy for LAN/remote access
- id: dsh-proxy
  name: "@smanx/dsh-proxy"
  config:
    listenPort: 3080
    # username: admin       # Uncomment to enable Basic Auth
    # password: changeme    # Uncomment to enable Basic Auth
```

### 5. Install the systemd service

```bash
sudo cp systemd/dsh.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dsh
sudo systemctl start dsh
```

### 6. Verify

```bash
# Check DSH is running
curl -s http://127.0.0.1:3079/ | head -5

# Check proxy is accessible
curl -s http://YOUR_SERVER_IP:3080/ | head -5
```

## Configuration

### Proxy Settings (via UI)

Go to **Settings → LAN Proxy** in the DSH web GUI to:

- Start/stop the proxy
- Change the listen port
- Set username and password for Basic Auth
- View connection status

### Proxy Settings (via cordis.patch.yml)

```yaml
- id: dsh-proxy
  name: "@smanx/dsh-proxy"
  config:
    listenPort: 3080        # External port (0.0.0.0)
    username: admin         # Basic Auth username (empty = disabled)
    password: changeme      # Basic Auth password
```

### HTTPS

The proxy does **not** handle HTTPS. For production, put a TLS terminator in front:

- **Cloudflare Tunnel** — `cloudflared tunnel --url http://127.0.0.1:3080`
- **Caddy** — auto HTTPS with `reverse_proxy localhost:3080`
- **Nginx + Let's Encrypt** — standard reverse proxy config

## Reverse Proxy Features

The proxy ([smanx/dsh-proxy](https://github.com/smanx/dsh-proxy), MIT license) provides:

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

### Proxy not accessible
- Check if the plugin loaded: Settings → Plugins → dsh-proxy
- Check port is open: `ss -tlnp | grep 3080`
- Check firewall: `sudo ufw allow 3080/tcp`

### WebSocket not working
- The proxy must forward `Upgrade` and `Connection` headers
- If behind another proxy (nginx/Caddy), ensure WebSocket is enabled there too

### Settings page shows "unavailable in this browser"
- The loopback patch may not be applied
- Check the proxy plugin is enabled in Settings → Plugins
- Clear browser cache and reload

## Files

```
dsh-server-setup/
├── README.md                    # This file
├── PLUGINS.md                   # Plugin stack list
├── run.sh                       # DSH wrapper script
├── systemd/
│   └── dsh.service              # Systemd unit file
└── dsh-proxy/                   # Standalone proxy (alternative)
    └── node/
        ├── index.js
        ├── proxy-core.js
        └── package.json
```

## Plugins

See [PLUGINS.md](PLUGINS.md) for a full list of installed plugins with descriptions.

## Credits

- **Reverse proxy** — [smanx/dsh-proxy](https://github.com/smanx/dsh-proxy) (MIT license). Also provides [Go builds](https://github.com/smanx/dsh-proxy/releases) for standalone deployments.
- **DSH** — [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) by DeepSeek AI

## License

MIT
