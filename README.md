# DSH Server Setup

Run [DeepSeek Harness](https://github.com/deepseek-ai/dsh) on a remote VPS with reverse proxy as a DSH plugin.

This is a production-tested setup for running DSH on an Ubuntu server (ARM64 or x64) with:

## Features

- **systemd service** — auto-restart, logging, persistence
- **Reverse proxy plugin** — [smanx/dsh-proxy](https://github.com/smanx/dsh-proxy) runs inside DSH, configurable from Settings
- **Basic Auth** (optional) — protect your instance from unauthorized access
- **File upload & preview** — built-in in DSH 0.1.5+ (no plugin needed)
- **PWA support** — install-as-app via custom plugin
- **Trusted host** — remote access via domain name without token in URL

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
# Node.js 24+ (via fnm recommended)
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install 24

# pnpm
npm install -g pnpm

# DSH
npm install -g @deepseek-ai/dsh@0.1.5-rc.1
```

### 2. Create a web profile

```bash
mkdir -p ~/.dsh/profiles/web
cd ~/.dsh/profiles/web
```

### 3. Add plugins

```bash
# Reverse proxy
pnpm add github:smanx/dsh-proxy

# Other recommended plugins
pnpm add dshmarket dsh-mnemon dsh-free-search dsh-config-manager dsh-mcp-sync
```

### 4. Configure the profile

**`~/.dsh/profiles/web/package.json`:**

```json
{
  "name": "dsh-profile-web",
  "private": true,
  "dependencies": {
    "@smanx/dsh-proxy": "github:smanx/dsh-proxy",
    "dshmarket": "^1.45.1"
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

### 5. Configure credentials

Create `~/.dsh/.credentials.yaml`:

```yaml
version: 1
refs:
  OPENCODE_GO_API_KEY: sk-your-api-key-here
records: {}
```

### 6. Install the systemd service

```bash
sudo cp systemd/dsh.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dsh
sudo systemctl start dsh
```

### 7. Verify

```bash
# Check DSH is running
curl -s http://127.0.0.1:3079/ | head -5

# Check proxy is accessible
curl -s http://YOUR_SERVER_IP:3080/ | head -5

# Check logs
journalctl -u dsh -f
```

## Updating DSH

The `update_all.sh` script handles updates automatically via cron. To update manually:

```bash
# Update DSH
npm install -g @deepseek-ai/dsh@latest

# Restart service
sudo systemctl restart dsh
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

### HTTPS / Remote Access

The proxy does **not** handle HTTPS. For production, put a TLS terminator in front:

- **[Pangolin](https://github.com/fosrl/pangolin)** (recommended) — self-hosted identity-aware VPN + reverse proxy with WireGuard, dashboard, and access control
- **Cloudflare Tunnel** — `cloudflared tunnel --url http://127.0.0.1:3080`
- **Caddy** — auto HTTPS with `reverse_proxy localhost:3080`
- **Nginx + Let's Encrypt** — standard reverse proxy config

### Pangolin Setup

[Pangolin](https://github.com/fosrl/pangolin) is a self-hosted tunnel that gives you HTTPS + authentication + WireGuard VPN without opening ports. It runs as Docker containers on the same VPS.

**1. Install Pangolin:**

```bash
git clone https://github.com/fosrl/pangolin.git ~/pangolin
cd ~/pangolin
bash install.sh
```

**2. Configure (`~/pangolin/config/config.yml`):**

```yaml
domain: yourdomain.com

letsencrypt:
  email: you@yourdomain.com
  useLetsEncrypt: true

flask_secret: <random-secret>  # Generate with: openssl rand -hex 32
jwt_secret: <random-secret>    # Generate with: openssl rand -hex 32
```

**3. Add DSH resource in Pangolin dashboard:**

1. Open `https://yourdomain.com` → login
2. Go to **Resources** → **New Resource**
3. Set:
   - Name: `dsh`
   - Protocol: `HTTP`
   - Target IP: `127.0.0.1`
   - Target Port: `3080`
4. Create a **Target** (the Gerbil client) and generate a config
5. On your VPS, add the Gerbil client:

```bash
sudo nano /etc/pangolin/client/config.yml
sudo systemctl restart pangolin-client
```

**4. Access DSH:**

```
https://dsh.yourdomain.com
```

**Advantages over direct proxy:**
- HTTPS with automatic Let's Encrypt certificates
- Built-in authentication (email-based or SSO)
- WireGuard VPN option for full network access
- Access control and audit logs
- No need to open additional ports

## Reverse Proxy Features

The proxy ([smanx/dsh-proxy](https://github.com/smanx/dsh-proxy), MIT license) provides:

### `crypto.randomUUID` polyfill
DSH's frontend uses `crypto.randomUUID()` for RPC IDs, but this API is only available in secure contexts (HTTPS/localhost). When accessing via LAN IP or public URL, the polyfill injects a compatible implementation using `getRandomValues()`.

### Loopback trust patch
DSH checks `location.hostname` to determine if the browser is local. Non-loopback hosts get degraded behavior (memory-only mode, no settings). The proxy patches the client JS to treat proxied connections as loopback, enabling full functionality.

### WebSocket support
The proxy forwards WebSocket connections for real-time DSH features (streaming, live updates).

### Public path whitelist
`/manifest.webmanifest`, `/favicon.svg`, and `/favicon.ico` are served without auth so browsers can fetch PWA metadata without credentials.

## DSH 0.1.5 Changes

### Built-in features (no plugins needed)
- **File upload** — drag & drop or paste images directly in chat
- **File preview** — sidebar with syntax highlighting, PDF, images
- **Sidebar** — multi-tab, split view, fullscreen for files and deliverables

### Removed features
- **Telegram integration** — both `dsh-telegram` and `dsh-telegram-bridge` are broken with DSH 0.1.5
- **Cron scheduler** — `dsh-cron` Host-side doesn't start
- **Webhook** — removed, was used with cron

### Known issues
- `dsh-telegram` v0.2.0 — Host-side `apply()` never executes
- `dsh-telegram-bridge` — depends on `apiProxy` which doesn't exist in DSH 0.1.5
- `dsh-cron` (@goodandready) — Host-side doesn't start, no logs generated

## OpenCode Go Session Header

OpenCode Go requires an `x-opencode-session` header on every request for per-conversation
routing and prompt-cache affinity. A request without it is answered with
`400 MissingSessionID`. DSH's built-in pi-ai route does not send it — see the open upstream
discussion [DSH #5495](https://github.com/deepseek-ai/deepseek-harness/discussions/5495).

The fix is the provider plugin
[scavanger2221/dsh-llm-opencode-go](https://github.com/scavanger2221/dsh-llm-opencode-go), which
owns the `opencode-go` route and stamps the harness session id on every request — one id per
conversation, under both `x-opencode-session` and the `x-deepseek-harness-session-id` OpenCode
also recognizes:

```bash
dsh plugin --profile web add github:scavanger2221/dsh-llm-opencode-go#v0.1.2
```

Use **v0.1.2 or later**: it declares `@earendil-works/pi-ai` as a peer dependency, which the
harness already provides. v0.1.0 depended on it and pulled pi-ai's whole transitive closure,
which can abort the install on a fresh `$DSH_HOME`.

The package registers its own row through its bundle patch, so listing it in
`dsh.profile.bundles` is all that is required. Do **not** also declare the row by hand in the
profile's `cordis.patch.yml`, and do **not** keep the old static workaround in
`~/.dsh/settings.yaml`:

```yaml
# Don't: it competes with the plugin for the same route.
llm-pi-ai:
  providers:
    opencode-go:
      headers:
        x-opencode-session: "dsh-global"
```

`llm.registerAdapter` is all-or-nothing and refuses a duplicate route with `DUPLICATE_ADAPTER`,
so only one of the two can serve `opencode-go` and the winner depends on load order. Verify the
plugin is the owner — there must be exactly one row:

```bash
dsh --profile web --dump-config | grep -A5 '^- id: llm-opencode-go'
```

### Why the value matters

The header value is the prompt-cache partition key, measured against the Go endpoint:

| Request | Cache |
|---------|-------|
| same value as the previous request | `cached_tokens > 0` (hit) |
| a different value | `cached_tokens: 0` (miss) |
| no header | `400 MissingSessionID` |

A static value such as `dsh-global` is accepted and does hit the cache inside a conversation, but
it puts every conversation in a single cache partition and defeats Go's per-session routing. The
plugin's per-session id is what OpenCode asks for.

**Upstream status:** discussion [#5495](https://github.com/deepseek-ai/deepseek-harness/discussions/5495)
is still open; the plugin is the working setup in the meantime.

## Troubleshooting

### DSH won't start
- Check logs: `journalctl -u dsh -f`
- Verify Node.js is in PATH: `which node`
- Check DSH home exists: `ls ~/.dsh/`
- Verify credentials: `cat ~/.dsh/.credentials.yaml`

### Proxy not accessible
- Check if the plugin loaded: Settings → Plugins → dsh-proxy
- Check port is open: `ss -tlnp | grep 3080`
- Check firewall: `sudo ufw allow 3080/tcp`
- For remote access, add `--trusted-host yourdomain.com` to run.sh

### WebSocket not working
- The proxy must forward `Upgrade` and `Connection` headers
- If behind another proxy (nginx/Caddy), ensure WebSocket is enabled there too

### Settings page shows "unavailable in this browser"
- The loopback patch may not be applied
- Check the proxy plugin is enabled in Settings → Plugins
- Clear browser cache and reload

### Plugin not loading
- Check the plugin is in `bundles` array in `package.json`
- Check `cordis.patch.yml` syntax
- Check logs for errors: `journalctl -u dsh -f | grep -i error`

### Credentials not found
- Verify `~/.dsh/.credentials.yaml` exists and has correct format
- Check file permissions: `ls -la ~/.dsh/.credentials.yaml`
- Ensure the credential name matches what the plugin expects

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
- **Remote access** — [Pangolin](https://github.com/fosrl/pangolin) (self-hosted VPN + reverse proxy with WireGuard)
- **DSH** — [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) by DeepSeek AI

## License

MIT
