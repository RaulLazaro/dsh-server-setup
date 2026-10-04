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

# DSH — pin the exact version your plugin stack is verified against.
# `@latest` moves fast (0.2.0-rc.2 at the time of writing), and DSH enforces
# plugin peer ranges at boot: a plugin pinned to an older runtime is *skipped*
# (whole bundle) or *disabled* (its config rows) instead of loading, which is
# how a blind upgrade silently loses the proxy or the agent presets.
npm install -g @deepseek-ai/dsh@0.1.7-rc.2
```

### 2. Create the web profile and add plugins

`dsh plugin` forwards to pnpm inside the profile and keeps `dsh.profile.bundles` in sync: a
package that declares `dsh.bundle` — every plugin below does — is appended to the layer stack
automatically, so the bundles array is never edited by hand. The first call also creates
`~/.dsh/profiles/web/` from the shipped `web` template: `package.json`, `cordis.patch.yml`,
`pnpm-workspace.yaml`, and the `cordis.yml` loader root (which DSH rewrites on every boot —
never edit it):

```bash
# Reverse proxy
dsh plugin --profile web add github:smanx/dsh-proxy

# Other recommended plugins
dsh plugin --profile web add dshmarket dsh-mnemon dsh-free-search dsh-config-manager dsh-mcp-sync
```

A package that declares no `dsh.bundle` (client-only plugins, plain libraries) still installs as
a dependency, and DSH warns that it is not a profile layer.

### 3. Configure the profile

Each package's bundle patch already mounts its own row, so
`~/.dsh/profiles/web/cordis.patch.yml` only carries overrides. A row is addressed by its `id` and
the patch replaces that row's whole config, so restate every key you own:

```yaml
# dsh-proxy: reverse proxy for LAN/remote access
- id: dsh-proxy
  name: "@smanx/dsh-proxy"
  config:
    listenPort: 3080
    # username: admin       # Uncomment to enable Basic Auth
    # password: changeme    # Uncomment to enable Basic Auth
```

Check what actually mounts — one composed row per plugin — with:

```bash
dsh --profile web --dump-config
```

### 4. Configure credentials

Create `~/.dsh/.credentials.yaml`:

```yaml
version: 1
refs:
  OPENCODE_GO_API_KEY: sk-your-api-key-here
records: {}
```

### 5. Install the systemd service

Edit `User`, `Group`, `WorkingDirectory` and `ExecStart` in `systemd/dsh.service` first — the
checked-in unit is a template with placeholders:

```bash
$EDITOR systemd/dsh.service
sudo cp systemd/dsh.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dsh
```

Per-instance settings (`DSH_PORT`, `DSH_HOME`, `DSH_TRUSTED_HOST`) belong in `.env` beside
`run.sh` — copy `.env.example` and edit it; `run.sh` sources that file, and the unit's own
`Environment=` lines win over it. `DSH_TRUSTED_HOST` is what lets the instance be opened by its
public hostname without a token in the URL.

### 6. Verify

```bash
# Check DSH is running (loopback answers without a token)
curl -s http://127.0.0.1:3079/ | head -5

# Check the proxy is accessible (asks for Basic Auth if you enabled it)
curl -s http://YOUR_SERVER_IP:3080/ | head -5

# Check the service and its logs
systemctl status dsh
journalctl -u dsh -f
```

### Local patches (ExecStartPre)

Two upstream issues bite this stack; both are fixed by a small idempotent script that
[scripts/patch-dsh-connection.sh](scripts/patch-dsh-connection.sh) applies to the installed
`@deepseek-ai/dsh-client-connection` **before every boot** (npm rewrites the global tree on
each install, so the patch must run from `ExecStartPre`, not once by hand):

1. **`cannot get property "webServer" without inject`** — a plugin calling
   `connection.rpc.handle()` (notably `@smanx/dsh-proxy` before
   [upstream commit `cda3f24`](https://github.com/smanx/dsh-proxy/commit/cda3f24fb44383aa48d65f56989bb3f5f3f532b9),
   2026-09-29) crashes while mounting, so port 3080 never binds. Adding `"webServer"` to the
   declared `inject` list fixes it. Updating `@smanx/dsh-proxy` to that commit or newer fixes
   it upstream — the patch stays as a safety net for older pinned commits.
2. **`SameSite=Strict` session cookie** — the cookie is emitted `Strict`, which Android
   ignores when an *installed PWA* is launched (its first request is `Sec-Fetch-Site:
   cross-site`), so the PWA loops on 401 while the normal browser tab works. `Lax` still
   blocks cross-site `fetch`/`XHR`, where `Strict` actually mattered.

Wire it up:

```ini
# /etc/systemd/system/dsh.service
ExecStart=/path/to/dsh-server-setup/run.sh
ExecStartPre=/path/to/dsh-server-setup/scripts/patch-dsh-connection.sh
```

Both patches are idempotent and exit 0 without touching anything when the pattern no longer
matches (i.e. once upstream ships the fix), so keeping the hook costs nothing.

## Updating DSH

```bash
npm install -g @deepseek-ai/dsh@<new-version>
sudo systemctl restart dsh
```

Bump the pin deliberately, and if an updater script or cron re-installs a pinned version for
you, change that pin **in the same change** — otherwise the next run silently reverts the
upgrade while the profile already targets the new runtime.

`Restart=always` brings the service back on its own; confirm with `dsh --version` and
`journalctl -u dsh -f`. An upgrade replaces the global package tree, so **re-apply any local
patch you keep inside the installed `node_modules`** afterwards — npm does not preserve it
(this is why [scripts/patch-dsh-connection.sh](scripts/patch-dsh-connection.sh) is wired as
`ExecStartPre`, see [Local patches](#local-patches-execstartpre)).
Restarting also stops any dev server a session launched as a child of DSH; start those with
`setsid nohup CMD > log 2>&1 < /dev/null &` if they must outlive the service.

### Verify the plugin stack after an upgrade

DSH checks every plugin's `peerDependencies` against the runtime at boot. After restarting,
read the first journal lines for:

- `skipping profile bundle "<name>"` — a whole plugin was dropped (e.g. a worktree or proxy
  bundle whose peers still pin the previous minor).
- `disabling profile plugin row "<name>"` — the package loaded but its config rows were
  refused (typical for preset packages pinned to an exact registry version).

Either update the plugin, wait for a compatible release, or — only if you accept the crash
risk — grant an explicit single-package exemption:

```bash
dsh plugin --profile web allow-version <package>@<version>
```

Also re-check the proxy is listening (`ss -tlnp | grep 3080`) and that a login still
completes end to end. If you keep sessions you care about, snapshot `~/.dsh/sessions` before
upgrading: config backups do not include it by default.

## Configuration

### Proxy Settings (via UI)

Go to **Settings → LAN Proxy** in the DSH web GUI to:

- Start/stop the proxy
- Change the listen port
- Set username and password for Basic Auth
- View connection status

### Proxy Settings (via cordis.patch.yml)

The plugin's bundle patch mounts the row; this entry in the profile's `cordis.patch.yml`
overrides its config. A row patch replaces the whole config, so restate every key you own:

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

[Pangolin](https://github.com/fosrl/pangolin) is a self-hosted identity-aware tunnel that gives you
HTTPS + authentication in front of DSH without exposing the port. It runs as Docker containers
(`pangolin`, `gerbil`, `traefik`) on the same VPS; the installer is the supported path — the old
`git clone … && bash install.sh` flow no longer exists.

Prerequisites: a domain pointing at the server, and ports 80/TCP, 443/TCP, 51820/UDP and
21820/UDP open.

**1. Run the installer:**

```bash
mkdir -p ~/pangolin && cd ~/pangolin
curl -fsSL https://static.pangolin.net/get-installer.sh | bash
sudo ./installer
```

It prompts for the edition (Community/Enterprise), the base domain, the dashboard domain
(`pangolin.example.com` by default), a Let's Encrypt email, and whether to install Gerbil for
tunnelled connections, then pulls and starts the containers (2-3 minutes).

**2. Create the first admin account** at the URL the installer prints,
`https://<dashboard-domain>/auth/initial-setup`, using the setup token from
`sudo docker compose logs pangolin`. Create an organisation when prompted.

**3. Publish DSH as a resource:** in the dashboard add a resource whose target is
`http://127.0.0.1:3080` — the `dsh-proxy` port — and attach a target (Newt/Gerbil client) for
this server. If Traefik runs in Docker (as it does with the bundled compose file), the
resource target is resolved *inside the container*, where `127.0.0.1` is the container itself:
use the host's Docker bridge address instead (e.g. `http://172.18.0.1:3080`, check with
`ip -4 addr show docker0` or your compose network). Exact field names and client installation
live in the [Pangolin docs](https://docs.pangolin.net/) — treat them as the source of truth,
the dashboard changes between releases.

**4. Access DSH** at the resource's public URL.

**Advantages over exposing the proxy directly:**
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
`/manifest.webmanifest` and `/favicon.svg` are served without auth so browsers can fetch PWA
metadata without credentials.

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

The fix is a provider plugin that owns the `opencode-go` route and stamps the harness session
id on every request — one id per conversation, under both `x-opencode-session` and the
`x-deepseek-harness-session-id` OpenCode also recognizes. Two work:

```bash
# Current pick (npm, ships a Settings card + live model catalog):
dsh plugin --profile web add dsh-opencode-go

# Alternative (GitHub, route owner before the npm package existed):
dsh plugin --profile web add github:scavanger2221/dsh-llm-opencode-go#v0.1.2
```

Install **one route owner, not both**: `llm.registerAdapter` is all-or-nothing and refuses a
duplicate route with `DUPLICATE_ADAPTER`, and the winner depends on load order. Keeping the
loser installed as a safety net is fine as long as its row is disabled explicitly in the
profile's `cordis.patch.yml` (that is what this server does with `dsh-llm-opencode-go`).
Verify exactly one row serves the route:

```bash
dsh --profile web --dump-config | grep -B2 -A5 'opencode'
# llm-opencode-go row must carry `disabled: true` if the other owner is active
```

For the GitHub alternative, use **v0.1.2 or later**: it declares `@earendil-works/pi-ai` as a
peer dependency, which the harness already provides. v0.1.0 depended on it and pulled pi-ai's
whole transitive closure, which can abort the install on a fresh `$DSH_HOME`.

Either package registers its own row through its bundle patch, so listing it in
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
- Check the journal for `cannot get property "webServer" without inject` — the
  `dsh-proxy` RPC channel failed to mount; see
  [Local patches](#local-patches-execstartpre) or update `@smanx/dsh-proxy` to a
  commit newer than `cda3f24`
- Check firewall: `sudo ufw allow 3080/tcp`
- For remote access by hostname, set `DSH_TRUSTED_HOST` in `.env` (run.sh passes it as
  `--trusted-host`)

### WebSocket not working
- The proxy must forward `Upgrade` and `Connection` headers
- If behind another proxy (nginx/Caddy), ensure WebSocket is enabled there too

### Settings page shows "unavailable in this browser"
- The loopback patch may not be applied
- Check the proxy plugin is enabled in Settings → Plugins
- Clear browser cache and reload

### Plugin not loading
- Check the composed tree: `dsh --profile web --dump-config` (one row per plugin)
- Check the package is listed in `dsh.profile.bundles` in the profile's `package.json`;
  `dsh plugin --profile web add <package>` maintains that list
- After an upgrade, grep the journal for `skipping profile bundle` / `disabling profile
  plugin row` — DSH refuses plugins whose peer ranges exclude the running runtime (see
  [Updating DSH](#updating-dsh))
- Check `cordis.patch.yml` syntax
- Check logs for errors: `journalctl -u dsh -f | grep -i error`

### Installed PWA loops asking for the token
- The session cookie is emitted `SameSite=Strict` and Android drops it on the PWA's
  cross-site launch request, while the same URL works in a normal browser tab — see
  [Local patches](#local-patches-execstartpre)

### Credentials not found
- Verify `~/.dsh/.credentials.yaml` exists and has correct format
- Check file permissions: `ls -la ~/.dsh/.credentials.yaml`
- Ensure the credential name matches what the plugin expects

## Files

```
dsh-server-setup/
├── README.md                    # This file
├── PLUGINS.md                   # Plugin stack list
├── run.sh                       # DSH wrapper script (sources .env if present)
├── .env.example                 # DSH_PORT / DSH_HOME / DSH_TRUSTED_HOST
├── scripts/
│   └── patch-dsh-connection.sh  # Idempotent node_modules patches, run via ExecStartPre
├── systemd/
│   └── dsh.service              # Systemd unit template (edit the placeholders)
└── dsh-proxy/                   # Legacy standalone proxy, kept for reference
    └── node/
        ├── index.js
        ├── proxy-core.js
        └── package.json
```

The supported reverse proxy is the `@smanx/dsh-proxy` plugin; the `dsh-proxy/node/` copy is the
pre-plugin standalone process and is no longer wired into `run.sh`.

## Plugins

See [PLUGINS.md](PLUGINS.md) for a full list of installed plugins with descriptions.

## Credits

- **Reverse proxy** — [smanx/dsh-proxy](https://github.com/smanx/dsh-proxy) (MIT license). Also provides [Go builds](https://github.com/smanx/dsh-proxy/releases) for standalone deployments.
- **Remote access** — [Pangolin](https://github.com/fosrl/pangolin) (self-hosted VPN + reverse proxy with WireGuard)
- **DSH** — [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) by DeepSeek AI

## License

MIT
