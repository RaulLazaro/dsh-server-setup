#!/usr/bin/env bash
# DSH wrapper — starts DSH + dsh-proxy
set -e

# PATH setup (fnm, local bins)
export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.local/share/fnm:$PATH"
if command -v fnm &>/dev/null; then
  eval "$(fnm env)"
fi

DSH_PORT="${DSH_PORT:-3079}"
PROXY_PORT="${PROXY_PORT:-3080}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

mkdir -p "$DSH_HOME"

echo "[dsh] Starting DSH on 127.0.0.1:${DSH_PORT}..."
dsh web --port "$DSH_PORT" --no-open &
DSH_PID=$!

# Wait for DSH to be ready
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${DSH_PORT}/" >/dev/null 2>&1; then
    echo "[dsh] DSH ready (pid $DSH_PID)"
    break
  fi
  sleep 1
done

echo "[dsh] Starting dsh-proxy on 0.0.0.0:${PROXY_PORT} -> 127.0.0.1:${DSH_PORT}"
cd "$(dirname "$0")/dsh-proxy/node"
node index.js &
PROXY_PID=$!

# Cleanup on exit
cleanup() {
  echo "[dsh] Shutting down..."
  kill "$PROXY_PID" 2>/dev/null || true
  kill "$DSH_PID" 2>/dev/null || true
  wait "$PROXY_PID" 2>/dev/null || true
  wait "$DSH_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait for either process to exit
wait
