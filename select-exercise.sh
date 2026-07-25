#!/usr/bin/env bash
#
# select-exercise.sh — seamless per-exercise setup inside a target VM.
#
# Usage (inside a lab VM):
#     ./select-exercise.sh <NN>       e.g. ./select-exercise.sh 03
#
# It (1) confirms you are on the correct VM for that exercise, (2) validates or
# pins the version preconditions, and (3) points you at the exercise directory.
# The heavy version separation is done by the two VMs; this handles the
# per-exercise details WITHIN a VM and keeps the workflow to a single command.

set -euo pipefail

EX="${1:-}"
ROLE="$(cat /etc/cel-target-role 2>/dev/null || echo unknown)"
EX_DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/exercises"

if [[ -z "${EX}" ]]; then
  echo "Usage: $0 <exercise-number>   (01, 02, 03, 04, 05)"
  exit 1
fi
EX="$(printf '%02d' "$((10#${EX}))")"   # normalise 3 -> 03

# --- Exercise → VM map -------------------------------------------------------
declare -A EX_VM=(
  [01]="runtime" [02]="runtime" [03]="runtime"
  [04]="kernel"  [05]="kernel"
)
# Exercise → required runtime pin on the runtime VM (empty = version-independent)
declare -A EX_DOCKER=(
  [01]="" [02]=""
  [03]="5:18.09.1~3-0~ubuntu-bionic"      # runc 1.0-rc6
)
declare -A EX_FOLDER=(
  [01]="01-docker-socket"
  [02]="02-privileged_container"
  [03]="03-runc-cve-2019-5736"
  [04]="04-cgroups-cve-2022-0492"
  [05]="05-capstone-cve-2026-31431"
)

WANT_VM="${EX_VM[$EX]:-}"
FOLDER="${EX_FOLDER[$EX]:-}"

if [[ -z "${WANT_VM}" ]]; then
  echo "[!] Unknown exercise '${EX}'. Valid: 01 02 03 04 05." >&2
  exit 1
fi

# --- 1. Correct VM? ----------------------------------------------------------
if [[ "${ROLE}" != "${WANT_VM}" ]]; then
  echo "[!] Exercise ${EX} runs on the '${WANT_VM}' VM, but this is '${ROLE}'." >&2
  echo "    Switch with:  vagrant ssh ${WANT_VM}" >&2
  exit 1
fi

# --- 2. Validate / pin preconditions ----------------------------------------
if [[ "${ROLE}" == "runtime" ]]; then
  WANT_DOCKER="${EX_DOCKER[$EX]:-}"
  if [[ -n "${WANT_DOCKER}" ]]; then
    CUR="$(dpkg-query -W -f='${Version}' docker-ce 2>/dev/null || echo none)"
    if [[ "${CUR}" != "${WANT_DOCKER}" ]]; then
      echo "[*] Exercise ${EX} needs docker-ce=${WANT_DOCKER} (have ${CUR}); pinning…"
      sudo apt-get install -y --allow-downgrades \
        "docker-ce=${WANT_DOCKER}" "docker-ce-cli=${WANT_DOCKER}"
      sudo apt-mark hold docker-ce docker-ce-cli
      sudo systemctl restart docker
    fi
    echo "[*] Active runc: $(runc --version 2>/dev/null | head -n1)"
  else
    echo "[*] Exercise ${EX} is version-independent (misconfiguration)."
  fi

elif [[ "${ROLE}" == "kernel" ]]; then
  echo "[*] Kernel: $(uname -r)"
  CG="$(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo '?')"
  echo "[*] cgroup fs type at /sys/fs/cgroup: ${CG}  (expect cgroup v1, not cgroup2fs)"
  if [[ "${CG}" == "cgroup2fs" ]]; then
    echo "[!] cgroup v2 detected — Exercise 04 requires cgroup v1." >&2
    echo "    Re-provision / confirm systemd.unified_cgroup_hierarchy=0 and reboot." >&2
  fi
  USERNS="$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo '?')"
  echo "[*] unprivileged_userns_clone = ${USERNS}  (expect 1)"
fi

# --- 3. Point at the exercise ------------------------------------------------
TARGET="${EX_DIR_BASE}/${FOLDER}"
if [[ ! -d "${TARGET}" ]]; then
  echo "[!] Exercise directory not found: ${TARGET}" >&2
  exit 1
fi

cat <<EOF

[+] Ready for exercise ${EX} (${FOLDER}) on the '${ROLE}' VM.

    cd ${TARGET}
    ./setup.sh        # arm the exercise
    ./teardown.sh     # reset when finished

EOF
