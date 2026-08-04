#!/usr/bin/env bash
#
# snapshot-baseline.sh — clean-baseline snapshot lifecycle.
#
# *** RUN THIS ON THE HOST, from the directory containing the Vagrantfile. ***
# The `vagrant` CLI does not exist inside the guest, so snapshot operations
# cannot be performed by an exercise's teardown.sh. This script is the missing
# half of that workflow.
#
# Usage:
#     ./snapshot-baseline.sh create  <runtime|kernel>   # take the baseline
#     ./snapshot-baseline.sh restore <runtime|kernel>   # roll back to it
#     ./snapshot-baseline.sh status  <runtime|kernel>   # what exists / current state
#     ./snapshot-baseline.sh list    <runtime|kernel>
#     ./snapshot-baseline.sh delete  <runtime|kernel>
#
# Correct order of operations (important):
#     vagrant up kernel                     # provision + reboot into pinned kernel
#     ./snapshot-baseline.sh create kernel  # THEN snapshot — never before
#     vagrant ssh kernel                    # ... run exercises ...
#     ./snapshot-baseline.sh restore kernel # after a successful escape

set -euo pipefail

SNAP_NAME="clean-baseline"
MARKER="/var/lib/cel-baseline-taken"      # written in-guest so setup.sh can check

# Kernel ABI the kernel VM is expected to be running when snapshotted.
# Must match VULN_KERNEL_ABI in provision-kernel.sh.
EXPECTED_KERNEL_ABI="5.4.0-90"

CMD="${1:-}"
VM="${2:-}"

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

[[ -z "${CMD}" || -z "${VM}" ]] && usage
case "${VM}" in
  runtime|kernel) ;;
  *) echo "[!] VM must be 'runtime' or 'kernel' (got '${VM}')." >&2; exit 1 ;;
esac

# --- Host-side sanity checks -------------------------------------------------
if ! command -v vagrant >/dev/null 2>&1; then
  echo "[!] 'vagrant' not found. Run this script on the HOST, not inside a VM." >&2
  exit 1
fi
if [[ ! -f "Vagrantfile" ]]; then
  echo "[!] No Vagrantfile in $(pwd)." >&2
  echo "    cd to the repository root (where the Vagrantfile lives) and retry." >&2
  exit 1
fi

vm_is_running() {
  vagrant status "${VM}" 2>/dev/null | grep -qE "^${VM}[[:space:]]+running"
}

snapshot_exists() {
  vagrant snapshot list "${VM}" 2>/dev/null | grep -qx "${SNAP_NAME}"
}

# =============================================================================
case "${CMD}" in

  create)
    echo "[*] Preparing to snapshot '${VM}' as '${SNAP_NAME}'"

    if ! vm_is_running; then
      echo "[!] VM '${VM}' is not running. Bring it up first:  vagrant up ${VM}" >&2
      exit 1
    fi

    # The baseline must be taken AFTER provisioning has completed, otherwise the
    # snapshot captures a half-built target. For the kernel VM this specifically
    # means after the reboot into the pinned vulnerable kernel.
    if [[ "${VM}" == "kernel" ]]; then
      RUNNING_KERNEL="$(vagrant ssh "${VM}" -c "uname -r" 2>/dev/null | tr -d '\r' | tail -n1)"
      echo "[*] Guest is running kernel: ${RUNNING_KERNEL}"
      if [[ "${RUNNING_KERNEL}" != *"${EXPECTED_KERNEL_ABI}"* ]]; then
        echo "[!] Expected the pinned kernel ${EXPECTED_KERNEL_ABI}-generic." >&2
        echo "    The VM has not rebooted into the vulnerable kernel yet." >&2
        echo "    Run:  vagrant reload ${VM}   then retry." >&2
        echo "    Snapshotting now would capture the WRONG baseline." >&2
        exit 1
      fi
      CG_TYPE="$(vagrant ssh "${VM}" -c "stat -fc %T /sys/fs/cgroup" 2>/dev/null | tr -d '\r' | tail -n1)"
      echo "[*] Guest cgroup fs at /sys/fs/cgroup: ${CG_TYPE}"
      if [[ "${CG_TYPE}" == "cgroup2fs" ]]; then
        echo "[!] cgroup v2 is active; exercise 04 requires cgroup v1." >&2
        echo "    Confirm systemd.unified_cgroup_hierarchy=0 then reload the VM." >&2
        exit 1
      fi
    fi

    if snapshot_exists; then
      echo "[!] A '${SNAP_NAME}' snapshot already exists for '${VM}'."
      echo "    Delete it first if you intend to re-baseline:"
      echo "        ./snapshot-baseline.sh delete ${VM}"
      exit 1
    fi

    # Drop an in-guest marker so each exercise's setup.sh can verify that a
    # baseline exists before arming a destructive exercise.
    echo "[*] Writing in-guest baseline marker"
    vagrant ssh "${VM}" -c "sudo mkdir -p \$(dirname ${MARKER}) && \
      printf 'snapshot=%s\ntaken=%s\n' '${SNAP_NAME}' \"\$(date -Is)\" | sudo tee ${MARKER} >/dev/null" >/dev/null

    echo "[*] Taking snapshot"
    vagrant snapshot save "${VM}" "${SNAP_NAME}"

    echo "[+] Baseline created for '${VM}'."
    echo "    Restore at any time with:  ./snapshot-baseline.sh restore ${VM}"
    ;;

  restore)
    if ! snapshot_exists; then
      echo "[!] No '${SNAP_NAME}' snapshot exists for '${VM}'." >&2
      echo "    Nothing to restore. A baseline must be created BEFORE running" >&2
      echo "    exercises:  ./snapshot-baseline.sh create ${VM}" >&2
      echo "    To rebuild from scratch instead:  vagrant destroy -f ${VM} && vagrant up ${VM}" >&2
      exit 1
    fi
    echo "[*] Restoring '${VM}' to '${SNAP_NAME}' (this discards all changes since the baseline)"
    # --no-provision: the baseline is already provisioned; re-running provisioners
    # would reinstall packages and could alter the pinned state.
    vagrant snapshot restore "${VM}" "${SNAP_NAME}" --no-provision
    echo "[+] '${VM}' restored to the clean baseline."
    ;;

  status)
    echo "VM:                ${VM}"
    printf "Running:           "
    if vm_is_running; then echo "yes"; else echo "no"; fi
    printf "Baseline snapshot: "
    if snapshot_exists; then echo "present ('${SNAP_NAME}')"; else echo "ABSENT — create it before running exercises"; fi
    if vm_is_running; then
      echo "Guest kernel:      $(vagrant ssh "${VM}" -c 'uname -r' 2>/dev/null | tr -d '\r' | tail -n1)"
      if [[ "${VM}" == "kernel" ]]; then
        echo "Guest cgroup fs:   $(vagrant ssh "${VM}" -c 'stat -fc %T /sys/fs/cgroup' 2>/dev/null | tr -d '\r' | tail -n1)"
      fi
    fi
    ;;

  list)
    vagrant snapshot list "${VM}"
    ;;

  delete)
    if ! snapshot_exists; then
      echo "[*] No '${SNAP_NAME}' snapshot to delete for '${VM}'."
      exit 0
    fi
    vagrant snapshot delete "${VM}" "${SNAP_NAME}"
    vagrant ssh "${VM}" -c "sudo rm -f ${MARKER}" >/dev/null 2>&1 || true
    echo "[+] Deleted '${SNAP_NAME}' for '${VM}'."
    ;;

  *)
    usage
    ;;
esac