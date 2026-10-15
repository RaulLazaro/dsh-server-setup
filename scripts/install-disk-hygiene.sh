#!/usr/bin/env bash
# Installs the disk hygiene rules on a DSH host:
#   - scripts/dsh-disk-report  -> ~/.local/bin
#   - scripts/dsh-disk-guard   -> ~/.local/bin
#   - systemd/dsh-disk-guard.{service,timer} -> /etc/systemd/system (enabled)
#   - systemd/logrotate/dsh-disk-hygiene     -> /etc/logrotate.d
#   - /etc/systemd/journald.conf.d/dsh-limits.conf (bounded journal)
#
# Idempotent: safe to re-run after editing the units.
#
# Usage: sudo ./scripts/install-disk-hygiene.sh [--user <name>]
set -euo pipefail

TARGET_USER="${SUDO_USER:-$(id -un)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) TARGET_USER="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run me with sudo (it writes to /etc)" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
BIN_DIR="$HOME_DIR/.local/bin"
STATE_DIR="$HOME_DIR/.local/state/dsh"

echo "==> user: $TARGET_USER  home: $HOME_DIR"

echo "==> installing helper scripts into $BIN_DIR"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$BIN_DIR" "$STATE_DIR"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 \
  "$REPO_DIR/scripts/dsh-disk-report" "$BIN_DIR/dsh-disk-report"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 \
  "$REPO_DIR/scripts/dsh-disk-guard" "$BIN_DIR/dsh-disk-guard"

echo "==> installing systemd units"
sed -e "s/YOUR_USER/$TARGET_USER/g" -e "s#/home/YOUR_USER#$HOME_DIR#g" \
  "$REPO_DIR/systemd/dsh-disk-guard.service" >/etc/systemd/system/dsh-disk-guard.service
sed -e "s/YOUR_USER/$TARGET_USER/g" -e "s#/home/YOUR_USER#$HOME_DIR#g" \
  "$REPO_DIR/systemd/dsh-disk-guard.timer" >/etc/systemd/system/dsh-disk-guard.timer

echo "==> installing logrotate rule"
sed -e "s/YOUR_USER/$TARGET_USER/g" -e "s#/home/YOUR_USER#$HOME_DIR#g" \
  "$REPO_DIR/systemd/logrotate/dsh-disk-hygiene" >/etc/logrotate.d/dsh-disk-hygiene

echo "==> bounding the systemd journal (200M / 1 month)"
install -d /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/dsh-limits.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=1month
EOF

systemctl daemon-reload
systemctl restart systemd-journald
systemctl enable --now dsh-disk-guard.timer

echo "==> validating logrotate config"
logrotate -d /etc/logrotate.d/dsh-disk-hygiene >/dev/null

echo "==> running the guard once"
systemctl start dsh-disk-guard.service

echo
echo "done. next run:"
systemctl list-timers dsh-disk-guard.timer --no-pager | head -3
echo
echo "report now with: sudo -u $TARGET_USER $BIN_DIR/dsh-disk-report"
