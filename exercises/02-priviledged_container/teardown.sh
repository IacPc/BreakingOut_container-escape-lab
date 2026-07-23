#!/usr/bin/env bash
#
# Exercise 02 — Privileged Container Escape
# teardown.sh — returns the VM to the clean baseline.
#
# Run from inside the lab VM:
#     ./teardown.sh
#
# Safe to run repeatedly; missing artefacts are ignored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

FLAG_PATH="/root/flag.txt"

# --- Resolve a working Docker Compose invocation -----------------------------
if sudo docker compose version >/dev/null 2>&1; then
  compose() { sudo docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() { sudo docker-compose "$@"; }
else
  echo "[!] Docker Compose not found; skipping container teardown." >&2
  compose() { return 0; }
fi

echo "[*] Stopping and removing the target container"
compose -f "${COMPOSE_FILE}" down --remove-orphans || true

echo "[*] Removing host flag"
sudo rm -f "${FLAG_PATH}"

# Defensive cleanup: if a solver mounted the host disk somewhere on the VM host
# itself (rather than inside the now-removed container), unmount it. The
# canonical solution mounts inside the container, so this is usually a no-op.
for mp in /mnt/host /mnt; do
  if mountpoint -q "${mp}" 2>/dev/null; then
    echo "[*] Unmounting leftover mount at ${mp}"
    sudo umount "${mp}" || true
  fi
done

echo "[+] Exercise 02 environment reset to clean baseline."
echo "    For a guaranteed-pristine state, restore the VM's clean-baseline snapshot."
