#!/usr/bin/env bash
# reset-lab.sh — return the VM to the clean post-provision baseline.
#
# Runs every exercise's teardown.sh, then prunes any stragglers. This is the
# "soft reset": it does NOT touch the pinned toolchain, only the artefacts the
# exercises create. For a hard reset, destroy and recreate the VM.
set -uo pipefail

LAB_ROOT="${LAB_ROOT:-/vagrant}"
EX_DIR="${LAB_ROOT}/exercises"

echo "==> Soft-resetting lab from ${EX_DIR}"
for ex in "${EX_DIR}"/*/; do
  td="${ex}teardown.sh"
  if [[ -x "$td" ]]; then
    echo "    -- teardown: $(basename "$ex")"
    ( cd "$ex" && ./teardown.sh ) || echo "       (teardown reported an issue; continuing)"
  fi
done

echo "==> Pruning any remaining lab artefacts"
docker container prune -f  >/dev/null 2>&1 || true
docker image prune -f      >/dev/null 2>&1 || true
docker network prune -f    >/dev/null 2>&1 || true
rm -rf /tmp/runc-bundle 2>/dev/null || true

echo "==> Baseline restored. Running containers:"
docker ps
