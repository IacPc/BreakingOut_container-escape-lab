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
# CVE-2026-31431 (Ex 05) ADDITIONALLY requires:
#   * a Docker Engine BEFORE v29.4.3. The capstone target runs under the engine's
#     DEFAULT seccomp and AppArmor profiles — nothing in its compose file is set
#     to unconfined — because the whole argument of the exercise is that the
#     escape needs nothing from the container's configuration. v29.4.3 responded
#     to this CVE by adding a socket(AF_ALG, ...) deny rule to the default
#     seccomp profile and a `deny network alg,` rule to the default AppArmor
#     profile, so on a current engine the defect is unreachable through those
#     defaults. The engine is therefore pinned below, exactly as the kernel is:
#     the PRE-DISCLOSURE default is the configuration under study.
#     Note this differs from the runtime VM, where Docker is pinned because the
#     RUNTIME carries the defect; here Docker is pinned because its default
#     PROFILES do.
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
TARGET_KERNEL="${VULN_KERNEL_ABI}-generic"
RUNNING_KERNEL="$(uname -r)"          # never remove what's booted

# --- 1. remove malformed duplicate initrds (e.g. *.img.img cruft) -----------
# These aren't dpkg-tracked and aren't referenced by grub.
# i pulled the image and they were there( don't know why), they eat a lot of storage
# so i delete them
find /boot -maxdepth 1 -name 'initrd.img-*.img' -print -delete 2>/dev/null || true


# --- 2. purge every installed kernel image except the two protected ones ----
purge_list=""
while read -r pkg; do
    # extract the version-flavour, e.g. linux-image-5.4.0-42-generic -> 5.4.0-42-generic
    ver="${pkg#linux-image-}"
    ver="${ver#unsigned-}"
    [ "$ver" = "$RUNNING_KERNEL" ] && continue
    [ "$ver" = "$TARGET_KERNEL" ]  && continue
    purge_list="$purge_list $pkg"
done < <(dpkg --list | awk '/^ii +linux-image-[0-9]/ {print $2}')

# The generic meta-packages depend on whichever specific kernel the box shipped
# with; purging that kernel while leaving the meta-package installed leaves an
# unmet dependency and aborts the purge. Drop the meta-packages in the same
# transaction — the pinned kernel is (re-)selected explicitly below anyway.
# They may already be on hold from a prior run (dpkg shows "hi" not "ii"), and
# apt refuses to purge a held package, so unhold before matching/purging.
apt-mark unhold linux-generic linux-image-generic linux-headers-generic 2>/dev/null || true
for meta in linux-generic linux-image-generic linux-headers-generic; do
    dpkg --list | grep -q "^.i  $meta " && purge_list="$purge_list $meta"
done

if [ -n "$purge_list" ]; then
    echo "Purging:$purge_list"
    sudo apt-get -y purge $purge_list
    sudo apt-get -y autoremove --purge
else
    echo "No removable kernels found."
fi

# --- 3. rebuild grub so menu entries match what's left ----------------------
sudo update-grub

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

# --- Docker Engine, pinned below the CVE-2026-31431 mitigation ---------------
# On the kernel VM the KERNEL carries the defect. Docker is pinned all the same,
# because from v29.4.3 its DEFAULT profiles deny the entry point (see header):
# an unpinned engine would leave Exercise 05 unreachable through the defaults
# its compose file relies on, and Exercise 04 unaffected either way.
#
# 29.4.2 would be the last release before the fix, but as of provisioning time
# the docker-ce apt repo only carries up to 28.1.1 — 29.x has not shipped yet,
# so the CVE-2026-31431 fix (and the AF_ALG deny rule it would add) doesn't
# exist on any real mirror either. 28.1.1 is therefore pinned as the newest
# AVAILABLE release; it satisfies "before the fix" the same way 29.4.2 would,
# since every real release predates the (still hypothetical) 29.4.3 fix.
#
# VERIFY the exact apt string on your mirror before rebuilding, and bump this
# pin once 29.4.3 actually ships:
#     apt-cache madison docker-ce
DOCKER_VERSION="5:28.1.1-1~ubuntu.20.04~focal"
DOCKER_CLI_VERSION="5:28.1.1-1~ubuntu.20.04~focal"
DOCKER_FIXED_IN="29.4.3"

echo "[*] Installing pinned Docker (${DOCKER_VERSION}) + compose plugin"
apt-get install -y --no-install-recommends \
  apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y --allow-downgrades \
  "docker-ce=${DOCKER_VERSION}" \
  "docker-ce-cli=${DOCKER_CLI_VERSION}" \
  containerd.io docker-compose-plugin || {
    echo "[!] Pinned Docker version unavailable on this mirror." >&2
    echo "    List candidates with:  apt-cache madison docker-ce" >&2
    echo "    Pick any release BELOW ${DOCKER_FIXED_IN} and update DOCKER_VERSION." >&2
    exit 1
  }

# Keep the pre-mitigation engine from being upgraded out from under the exercise.
apt-mark hold docker-ce docker-ce-cli containerd.io

systemctl enable --now docker
usermod -aG docker vagrant || true

# --- Verify the engine really predates the mitigation ------------------------
# A silently-upgraded engine turns Exercise 05 into a confusing null result
# rather than a lesson, so fail loudly here instead of at exercise time.
DOCKER_RUNNING="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 0)"
echo "[*] Docker Engine now running: ${DOCKER_RUNNING}"
if dpkg --compare-versions "${DOCKER_RUNNING}" ge "${DOCKER_FIXED_IN}"; then
  echo "[!] This engine is >= ${DOCKER_FIXED_IN} and therefore DENIES socket(AF_ALG)" >&2
  echo "    in its default seccomp profile. Exercise 05 will not be reachable." >&2
  echo "    Install a release below ${DOCKER_FIXED_IN} and re-provision." >&2
  exit 1
fi

# --- Python 3.10 (matches the Exercise 05 foothold image's interpreter) ------
# exercises/05-.../shared/exp.py and payload.py are written against 3.10 and
# are also run directly on this VM (outside the container) during the
# capstone; build the same 3.10.14 from source, via altinstall so it never
# shadows the system python3, exactly as the Dockerfile does for the foothold
# image.
PYTHON_VERSION="3.10.14"
echo "[*] Building Python ${PYTHON_VERSION} from source"
apt-get install -y --no-install-recommends \
  curl ca-certificates build-essential \
  zlib1g-dev libssl-dev libffi-dev libbz2-dev libreadline-dev \
  libsqlite3-dev liblzma-dev
curl -fsSL -o /tmp/Python.tgz \
  "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
tar -xzf /tmp/Python.tgz -C /tmp
(
  cd "/tmp/Python-${PYTHON_VERSION}"
  ./configure --prefix=/usr/local >/dev/null
  make -j"$(nproc)" >/dev/null
  make altinstall >/dev/null
)
rm -rf /tmp/Python.tgz "/tmp/Python-${PYTHON_VERSION}"
echo "[*] Python installed as: $(/usr/local/bin/python3.10 --version)"

# --- Pre-pull base images for air-gapped operation ---------------------------
# ubuntu:20.04 backs the Exercise 05 foothold image; 22.04 backs Exercise 04.
docker pull ubuntu:22.04 || true
docker pull ubuntu:20.04 || true

echo "kernel" > /etc/cel-target-role

echo "[+] kernel-target provisioning complete."
echo "    Pinned and held: kernel ${VULN_KERNEL_ABI}-generic, Docker ${DOCKER_RUNNING} (< ${DOCKER_FIXED_IN})."
echo "    A REBOOT is required to boot ${VULN_KERNEL} with cgroup v1."
echo "    After reboot, verify:  uname -r  (expect ${VULN_KERNEL_ABI}-generic)"
echo "                           stat -fc %T /sys/fs/cgroup  (expect: tmpfs / cgroupfs, i.e. v1)"
echo "                           docker version --format '{{.Server.Version}}'  (expect < ${DOCKER_FIXED_IN})"
