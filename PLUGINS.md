# Installed Plugins

My DSH web profile plugin stack. All plugins run on a remote VPS (Ubuntu 24.04 ARM64) with the reverse proxy setup described in the [README](README.md).

Installed with `dsh plugin --profile web add <package>`, which keeps `dsh.profile.bundles` in sync; this list mirrors that array plus the two in-box bundles.

## Core

| Plugin | Description |
|--------|-------------|
| `@deepseek-ai/dsh-base` | DSH core bundle (bundled) |
| `@deepseek-ai/dsh-web-app` | DSH web UI shell (bundled) |

## Models & Providers

| Plugin | Description |
|--------|-------------|
| `dsh-llm-opencode-go` | OpenCode Go provider — owns the `opencode-go` route and sends the per-conversation `x-opencode-session` header (cache affinity), plus a live model catalog and a Settings → Plugins card. See [README § OpenCode Go](README.md#opencode-go-session-header) |

## Network & Access

| Plugin | Description |
|--------|-------------|
| `@smanx/dsh-proxy` | Reverse proxy — HTTP + WebSocket with Basic Auth, `crypto.randomUUID` polyfill, and loopback trust patch. Configurable from Settings → LAN Proxy |

## UI & Navigation

| Plugin | Description |
|--------|-------------|
| `dsh-omni-router` | Multi-workspace routing and navigation |
| `@deepseek-ai/dsh-client-ui-attachment` | Attachment UI components |

## Memory & Context

| Plugin | Description |
|--------|-------------|
| `dsh-mnemon` | Cross-agent persistent memory with recall, documents, and knowledge graph |
| `@guillaumemeyer/dsh-plan-approval` | Plan review and approval workflow before execution |

## Skills & Tools

| Plugin | Description |
|--------|-------------|
| `dsh-skill-hub` | Skill management UI — browse, enable/disable, create, sync from market |
| `dsh-skill-manager` | Local skill file management |
| `dsh-run2skill` | Convert agent conversations into reusable skills |

## Development

| Plugin | Description |
|--------|-------------|
| `dsh-task-worktree` | Git worktree isolation for tasks — keeps main clean |
| `dsh-mcp-sync` | MCP server synchronization across sessions |

## Search & Browser

| Plugin | Description |
|--------|-------------|
| `dsh-free-search` | Free web search (DuckDuckGo, Bing, SearXNG) with auto-failover — no API key needed |
| `@liustack/modsearch` | ModSearch bridge — structured web search with citations |

## Preview (custom)

| Plugin | Description |
|--------|-------------|
| `dsh-preview-plugin` | **Mine** — Live iframe preview tab with transparent SPA proxy. Embed any dev server at `/preview/:port/*` |

## PWA (custom)

| Plugin | Description |
|--------|-------------|
| `dsh-pwa-plugin` | **Mine** — Service worker + manifest for offline support and install-as-app |

## Agents & Subagents

| Plugin | Description |
|--------|-------------|
| `@aiwayds/dsh-subagent-registry` | Multi-agent orchestration and subagent management |

## Marketplace & Config

| Plugin | Description |
|--------|-------------|
| `dshmarket` | In-app plugin marketplace — browse, search, one-click install from 2900+ community plugins |
| `dsh-config-manager` | Backup/restore/migrate DSH config with encryption support |

## Not Working with DSH 0.1.5

| Plugin | Reason |
|--------|--------|
| `dsh-cron` (@goodandready) | Host-side doesn't start — no logs generated |
| `dsh-telegram` (v0.2.0) | Host-side `apply()` never executes |
| `dsh-telegram-bridge` | Depends on `apiProxy` which doesn't exist in DSH 0.1.5 |
| `dsh-upload-button` | Now built-in in DSH 0.1.5 |
| `dsh-file-viewer` | Now built-in in DSH 0.1.5 sidebar |
| `dsh-webhook` | Removed — cron notifications use dsh-telegram-bridge |

## My Custom Plugins

These are plugins I developed:

### [dsh-preview-plugin](https://github.com/RaulLazaro/dsh-preview-plugin)
Live preview tab for DSH. Embed any dev server in an iframe with transparent SPA proxying.

- Path-based proxy: `/preview/:port/*` rewrites all routes
- `<base>` + fetch/XHR interception for full SPA support
- Per-session or global port management via API
- Auto-sync from agent-set port

### [dsh-pwa-plugin](https://github.com/RaulLazaro/dsh-pwa-plugin)
PWA support for DSH. Adds offline caching and install-as-app capability.

- Service worker with smart caching (network-first HTML, cache-first static)
- PWA manifest with custom icons
- Silent auto-activate on updates
- Offline fallback page

## Stats

- **Total plugins:** 20 (including core)
- **Custom plugins:** 2 (dsh-preview-plugin, dsh-pwa-plugin)
- **Server:** Oracle Cloud ARM64, Ubuntu 24.04
- **Node.js:** v24 (via fnm)
- **Access:** dsh-proxy plugin on port 3080
- **DSH Version:** 0.1.5-rc.1

## OpenCode Go Session Header

OpenCode Go rejects requests without `x-opencode-session` (`400 MissingSessionID`). The
`dsh-llm-opencode-go` plugin owns the `opencode-go` route and sends the harness session id on
every request, so **no** `llm-pi-ai` provider entry is needed in `settings.yaml` — and a static
one must not be added, because two adapters cannot share one route and the loser fails with
`DUPLICATE_ADAPTER`. Install and verification steps:
[README § OpenCode Go Session Header](README.md#opencode-go-session-header).
