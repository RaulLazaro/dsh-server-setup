#!/usr/bin/env bash
# DSH wrapper — starts DSH with the web profile (the reverse proxy runs as a plugin).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional local settings beside this script: DSH_PORT, DSH_HOME, DSH_TRUSTED_HOST.
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

# PATH: user-installed binaries (gh, …) and fnm's node.
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
if command -v fnm &>/dev/null; then
  eval "$(fnm env)"
fi

DSH_PORT="${DSH_PORT:-3079}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

mkdir -p "$DSH_HOME"

# DSH_TRUSTED_HOST lets the instance be opened by its public hostname without a
# token in the URL. Leave it empty to keep token-only access.
TRUSTED_HOST_ARGS=()
if [ -n "${DSH_TRUSTED_HOST:-}" ]; then
  TRUSTED_HOST_ARGS=(--trusted-host "$DSH_TRUSTED_HOST")
fi

echo "[dsh] Starting DSH on port ${DSH_PORT}${DSH_TRUSTED_HOST:+ (trusted host: ${DSH_TRUSTED_HOST})}..."
exec dsh web --port "$DSH_PORT" --no-open "${TRUSTED_HOST_ARGS[@]}"
