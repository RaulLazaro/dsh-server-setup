#!/usr/bin/env bash
# DSH wrapper — starts DSH with all plugins (proxy included as plugin)
set -e

# PATH setup (fnm, local bins)
export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.local/share/fnm:$PATH"
if command -v fnm &>/dev/null; then
  eval "$(fnm env)"
fi

DSH_PORT="${DSH_PORT:-3079}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

mkdir -p "$DSH_HOME"

echo "[dsh] Starting DSH on port ${DSH_PORT}..."
exec dsh web --port "$DSH_PORT" --no-open
