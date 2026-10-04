#!/usr/bin/env bash
# Re-applies two idempotent workarounds over the installed
# @deepseek-ai/dsh-client-connection before DSH starts (systemd ExecStartPre).
#
# PATCH 1 - inject "webServer"
# Context: dsh-client-connection declares `inject = ["credentials"]` but its
# register path calls `owner.webServer.register(route)`. A plugin that calls
# `connection.rpc.handle()` (e.g. @smanx/dsh-proxy before upstream commit
# cda3f24, 2026-09-29) then fails with:
#   Error: cannot get property "webServer" without inject
# which leaves the plugin unmounted and port 3080 silent. Adding "webServer" to
# the declared inject list fixes it. Verified to be needed on 0.1.7-rc.2 as
# well (same error at dsh-client-connection/lib/index.js:656). If you update
# @smanx/dsh-proxy past cda3f24 the plugin no longer trips over this, but the
# patch is harmless and keeps older pinned commits working.
#
# PATCH 2 - SameSite=Strict -> SameSite=Lax (installed PWAs)
# The session cookie is emitted `HttpOnly; SameSite=Strict`, and Android marks
# an installed-PWA launch as `Sec-Fetch-Site: cross-site`, so the browser drops
# the cookie on that first request: DSH answers 401 and the PWA loops asking
# for the token, while a normal tab (same-site) works with the same cookie.
# Captured on the port-3080 flow:
#   PWA      GET /  Sec-Fetch-Site: cross-site  no Cookie header
#   browser  GET /  Sec-Fetch-Site: same-site   cookie dsh-auth-*
# With Lax the cookie IS sent on top-level cross-site navigations (exactly the
# PWA launch) and is still withheld on cross-site fetch/XHR, which is where
# Strict added protection. HttpOnly and the HMAC signature stay intact.
#
# Both patches are idempotent and independent: if one already applies, skip to
# the next. If neither pattern matches, warn and exit 0 without touching
# anything (upstream may have shipped the fix, or the layout changed).
set -euo pipefail

# Read the version with python3, NOT node: in ExecStartPre there is no fnm PATH.
PKG="$(find "$HOME/.local/share/fnm/node-versions" -path '*/node_modules/@deepseek-ai/dsh/package.json' -print -quit 2>/dev/null || true)"
VER="unknown"
if [ -n "$PKG" ] && [ -f "$PKG" ]; then
  VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PKG" 2>/dev/null || echo unknown)"
fi
echo "dsh-patch: DSH $VER (workarounds apply to 0.1.x and 0.2.x)."

BASE="$HOME/.local/share/fnm/node-versions"
if [ ! -d "$BASE" ]; then
  echo "dsh-patch: fnm node-versions not found; nothing to do."
  exit 0
fi

# One lookup serves both layouts: hoisted (node_modules/@deepseek-ai/...) and
# nested under the dsh package (node_modules/@deepseek-ai/dsh/node_modules/...).
TARGET="$(find "$BASE" -path '*/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js' -print -quit 2>/dev/null || true)"

if [ -z "$TARGET" ]; then
  echo "dsh-patch: dsh-client-connection not found (layout changed). No changes."
  exit 0
fi

# ----------------------------------------------------------------- patch 1
if grep -q 'const inject = \["credentials", "webServer"\];' "$TARGET"; then
  echo "dsh-patch: inject webServer -> already applied."
elif grep -q 'const inject = \["credentials"\];' "$TARGET"; then
  python3 - "$TARGET" <<'PY'
import sys
p = sys.argv[1]
old = 'const inject = ["credentials"];'
new = 'const inject = ["credentials", "webServer"];'
s = open(p).read()
assert s.count(old) == 1, f"unexpected occurrence count: {s.count(old)}"
open(p, "w").write(s.replace(old, new))
PY
  echo "dsh-patch: inject webServer -> applied."
else
  echo "dsh-patch: inject pattern not found; leaving as is."
fi

# ----------------------------------------------------------------- patch 2
if grep -q 'HttpOnly; SameSite=Lax' "$TARGET"; then
  echo "dsh-patch: SameSite=Lax -> already applied."
elif grep -q 'HttpOnly; SameSite=Strict' "$TARGET"; then
  python3 - "$TARGET" <<'PY'
import sys
p = sys.argv[1]
old = 'HttpOnly; SameSite=Strict'
new = 'HttpOnly; SameSite=Lax'
s = open(p).read()
assert s.count(old) == 1, f"unexpected occurrence count: {s.count(old)}"
open(p, "w").write(s.replace(old, new))
PY
  echo "dsh-patch: SameSite=Lax -> applied."
else
  echo "dsh-patch: SameSite pattern not found; leaving as is."
fi

echo "dsh-patch: done with $TARGET"
