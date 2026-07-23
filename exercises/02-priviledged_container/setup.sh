#!/usr/bin/env bash
#
# Exercise 02 — Privileged Container Escape
# setup.sh — provisions the vulnerable target inside the Vagrant VM.
#
# Run from inside the lab VM:
#     ./setup.sh
#
# Idempotent: re-running re-plants the flag and re-creates the container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

FLAG_PATH="/root/flag.txt"
FLAG_VALUE="FLAG{privileged_equals_host_devices}"

# --- Resolve a working Docker Compose invocation -----------------------------
if sudo docker compose version >/dev/null 2>&1; then
  compose() { sudo docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() { sudo docker-compose "$@"; }
else
  echo "[!] Neither 'docker compose' (v2) nor 'docker-compose' (v1) is available." >&2
  echo "    Provision the base VM template first (see repository README)." >&2
  exit 1
fi

# --- Sanity check: Docker daemon reachable -----------------------------------
if ! sudo docker info >/dev/null 2>&1; then
  echo "[!] Docker daemon is not reachable. Is Docker installed and running?" >&2
  exit 1
fi

echo "[*] Planting host flag at ${FLAG_PATH}"
echo "${FLAG_VALUE}" | sudo tee "${FLAG_PATH}" >/dev/null
sudo chmod 600 "${FLAG_PATH}"

echo "[*] Bringing up the privileged target container"
compose -f "${COMPOSE_FILE}" up -d

echo "[*] Target status:"
compose -f "${COMPOSE_FILE}" ps

cat <<'EOF'

[+] Exercise 02 is ready.

    A container named 'ex02-privileged-target' is running with --privileged.
    Enter it with:

        sudo docker exec -it ex02-privileged-target bash

    Objective:
        Escape to the VM host and read /root/flag.txt
        (the host flag, NOT a file inside the container).

    When finished, reset the environment with:

        ./teardown.sh

EOF
