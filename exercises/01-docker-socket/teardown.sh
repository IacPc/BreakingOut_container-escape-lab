#!/usr/bin/env bash
# teardown.sh — return exercise 01 to the clean baseline.
set -uo pipefail

echo "==> Removing exercise 01 containers"
docker rm -f ex01-socket-client 2>/dev/null || true
# Remove any sibling/escape container a student spawned during the exercise.
docker ps -aq --filter "label=lab.exercise=01-docker-socket" \
  | xargs -r docker rm -f 2>/dev/null || true

echo "==> Removing the host flag"
sudo rm -f /root/flag.txt 2>/dev/null || true

echo "==> Removing the exercise image"
docker rmi -f lab/ex01-socket-client:pinned 2>/dev/null || true

echo "==> Exercise 01 clean."
