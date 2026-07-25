#!/usr/bin/env bash
#
# provision-runtime.sh — runtime-target VM (Ubuntu 18.04)
# Installs the pinned-vulnerable Docker/runc stack used by exercises 01–03.
#
# CVE-2019-5736 boundary (verified): runc <= 1.0-rc6 is vulnerable; Docker
# < 18.09.2 ships it. We therefore pin Docker 18.09.1 (which bundles runc
# 1.0-rc6). Exercises 01 and 02 are version-independent and also run here.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Pinned versions ---------------------------------------------------------
# VERIFY the exact apt strings on your mirror with:
#     apt-cache madison docker-ce docker-ce-cli containerd.io
DOCKER_VERSION="5:18.09.1~3-0~ubuntu-bionic"
DOCKER_CLI_VERSION="5:18.09.1~3-0~ubuntu-bionic"
CONTAINERD_VERSION="1.2.2-3"         # compatible with Docker 18.09.1
COMPOSE_PLUGIN_VERSION="1.24.1"      # standalone v2 plugin binary
RUNC_VERSION="v1.0.0-rc5"            # vulnerable runc version

echo "[*] Installing prerequisites"
apt-get update -y
apt-get install -y --no-install-recommends \
  apt-transport-https ca-certificates curl gnupg-agent software-properties-common

echo "[*] Adding Docker's official apt repository (bionic)"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
apt-get update -y

echo "[*] Installing pinned vulnerable Docker stack (18.09.1 / runc 1.0-rc6)"
apt-get install -y --allow-downgrades \
  "docker-ce=${DOCKER_VERSION}" \
  "docker-ce-cli=${DOCKER_CLI_VERSION}" \
  "containerd.io=${CONTAINERD_VERSION}"

echo "[*] Installing Docker Compose v2 plugin (${COMPOSE_PLUGIN_VERSION})"
# The exercise compose files use the v2 (version-less) schema. The v2 plugin
# talks to the 18.09 daemon happily.

sudo curl -fsSL \
  "https://github.com/docker/compose/releases/download/${COMPOSE_PLUGIN_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
sudo mv /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo chmod +x /usr/bin/docker-compose     

sudo curl -fsSL \
  https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.amd64 \
  -o /tmp/runc
sudo cp /tmp/runc "$(which runc)"

# Prevent unattended upgrades from silently patching the vulnerable runtime.
sudo apt-mark hold docker-ce docker-ce-cli containerd.io
sudo systemctl disable --now unattended-upgrades 2>/dev/null || true


echo "[*] Enabling Docker and adding the vagrant user to the docker group"
sudo systemctl enable --now docker
sudo usermod -aG docker vagrant || true

echo "[*] Pre-pulling base images for air-gapped operation"
docker pull ubuntu:18.04 || true

# Marker so select-exercise.sh knows which VM it is on.
echo "runtime" > /etc/cel-target-role

echo "[*] runc version now present:"
runc --version || true

echo "[+] runtime-target provisioning complete."
echo "    Vulnerable stack: Docker 18.09.1 / runc 1.0-rc6 (held)."
