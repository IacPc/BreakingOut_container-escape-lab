#!/usr/bin/env bash
#
# provision-kernel.sh — kernel-target VM (Ubuntu 20.04)
# Pins a pre-fix kernel and enables the preconditions for exercises 04 and 05.
#
# CVE-2022-0492 (Ex 04) requires:
#   * a kernel BEFORE the fix (5.4.177 / 5.10.97 / 5.15.20 / 5.16.6 / 5.17-rc3),
#   * cgroup v1 (cgroup v2 removed release_agent and is NOT affected),
#   * unprivileged user namespaces enabled on the host.
# CVE-2026-31431 (Ex 05, capstone) has been latent since 2017, so the same old
# kernel is vulnerable to it as well — one kernel serves both exercises.
#
# NOTE: changing the boot kernel + GRUB cmdline requires a reboot. The
# Vagrantfile requests `reboot: true` after this provisioner.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Pinned kernel -----------------------------------------------------------
# 5.4.0-90 (Oct 2021) is comfortably before the Feb 2022 CVE-2022-0492 fix.
# Confirm availability with:  apt-cache search linux-image-5.4.0-.*-generic
VULN_KERNEL_ABI="5.4.0-90"
VULN_KERNEL="linux-image-${VULN_KERNEL_ABI}-generic"

echo "[*] Installing pinned vulnerable kernel: ${VULN_KERNEL}"
apt-get update -y
apt-get install -y --no-install-recommends \
  "linux-image-${VULN_KERNEL_ABI}-generic" \
  "linux-modules-${VULN_KERNEL_ABI}-generic" \
  "linux-modules-extra-${VULN_KERNEL_ABI}-generic" || {
    echo "[!] Exact kernel ABI unavailable on this mirror." >&2
    echo "    Pick an available 5.4.0-<XX below 100>-generic and update VULN_KERNEL_ABI." >&2
    exit 1
  }

# Keep the vulnerable kernel from being replaced/patched.
apt-mark hold "linux-image-${VULN_KERNEL_ABI}-generic" \
              "linux-modules-${VULN_KERNEL_ABI}-generic" \
              "linux-modules-extra-${VULN_KERNEL_ABI}-generic"
systemctl disable --now unattended-upgrades 2>/dev/null || true
# Also hold the meta-packages so `apt upgrade` cannot pull a fixed kernel.
apt-mark hold linux-generic linux-image-generic linux-headers-generic 2>/dev/null || true

echo "[*] Forcing boot into the pinned kernel and enabling cgroup v1"
# Boot the specific kernel via the GRUB submenu entry, and switch the unified
# cgroup hierarchy OFF so cgroup v1 (with release_agent) is active.
sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${VULN_KERNEL_ABI}-generic\"|" /etc/default/grub
if grep -q "systemd.unified_cgroup_hierarchy" /etc/default/grub; then
  sed -i "s|systemd.unified_cgroup_hierarchy=[01]|systemd.unified_cgroup_hierarchy=0|" /etc/default/grub
else
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 systemd.unified_cgroup_hierarchy=0\"|" /etc/default/grub
fi
update-grub

echo "[*] Enabling unprivileged user namespaces"
cat >/etc/sysctl.d/99-cel-userns.conf <<'EOF'
kernel.unprivileged_userns_clone=1
user.max_user_namespaces=15000
EOF
sysctl --system || true

# --- A working (current) Docker for running the target containers ------------
# On the kernel VM, Docker is NOT the vulnerable component; the kernel is.
echo "[*] Installing a current Docker + compose plugin"
apt-get install -y --no-install-recommends \
  apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
usermod -aG docker vagrant || true
docker pull ubuntu:22.04 || true

echo "kernel" > /etc/cel-target-role

echo "[+] kernel-target provisioning complete."
echo "    A REBOOT is required to boot ${VULN_KERNEL} with cgroup v1."
echo "    After reboot, verify:  uname -r  (expect ${VULN_KERNEL_ABI}-generic)"
echo "                           stat -fc %T /sys/fs/cgroup  (expect: tmpfs / cgroupfs, i.e. v1)"
