#!/usr/bin/env bash
# setup.sh — provision exercise 01 (Docker socket escape, CTF form).
#
# Plants a root-only flag on the HOST, then starts an unprivileged-looking
# container with the host Docker socket bind-mounted. The student's objective is
# to escape that container to host root and read the flag.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="lab/ex01-socket-client:pinned"
NAME="ex01-socket-client"
FLAG_PATH="/root/flag.txt"

echo "==> Planting the flag on the host at ${FLAG_PATH} (root-only, mode 600)"
# Random per-run token so it can't be guessed — it must actually be retrieved.
FLAG="flag{docker-socket-is-root-equivalent-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
echo "$FLAG" > "$FLAG_PATH"
chown root:root "$FLAG_PATH"
chmod 600 "$FLAG_PATH"    # only host root can read it — that's the whole point

echo "==> Building the socket-client image"
docker build -t "$IMAGE" .

echo "==> Starting a container WITH the host daemon socket bind-mounted"
docker run -d --name "$NAME" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --label lab.exercise=01-docker-socket \
  "$IMAGE" sleep infinity

cat <<'MSG'

Provisioned.

  OBJECTIVE
  ---------
  From inside the container below, obtain a root shell on the HOST and read the
  flag at /root/flag.txt. The file is owned by root and mode 600 — an
  unprivileged read will fail, so a real escape to host root is required.

  Get your foothold:

      docker exec -it ex01-socket-client sh

  Confirm you cannot read the flag the easy way (you have no host root yet):

      cat /root/flag.txt            # this is the CONTAINER's /root, not the host's

  Now work the objective. README.md has the full walk-through if you get stuck,
  followed by the mitigations that make this impossible.

  Clean up with: sudo ./teardown.sh
MSG
