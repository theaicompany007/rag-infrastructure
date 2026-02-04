#!/usr/bin/env bash
#
# docker-prune-safe.sh — Safe Docker cleanup script.
# Removes unused containers, networks, images, and volumes.
# Does NOT stop or remove anything used by running containers
# (rag-infrastructure, vani, theaicompany-web, etc.).
#
# Usage: run as root or with sudo for full prune; logs to stdout/stderr.
# Cron: /etc/cron.daily/docker-prune-safe (see docs/disk_cleanup.md).
#

set -e

echo "=== Docker prune (safe) — $(date -Iseconds) ==="

# --- Safety: Docker must be running ---
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible. Exiting." >&2
  exit 1
fi

echo "Docker is running. Proceeding with prune steps."
echo ""

# --- Step 1: Show current usage ---
echo "--- Before: docker system df ---"
docker system df
echo ""

# --- Step 2: Prune unused containers, networks, dangling images ---
echo "--- Running: docker system prune -f (containers, networks, dangling images) ---"
docker system prune -f
echo ""

# --- Step 3: Prune all unused images and volumes (keeps in-use by running containers) ---
echo "--- Running: docker system prune -a --volumes -f (all unused images + volumes) ---"
docker system prune -a --volumes -f
echo ""

# --- Optional: Extra image prune (documented; does not touch images used by running containers) ---
# docker image prune -a -f removes all unused images. Running containers keep their image in use,
# so this is safe but may be redundant after "docker system prune -a". Uncomment if you want it:
# echo "--- Optional: docker image prune -a -f ---"
# docker image prune -a -f
# echo ""

# --- Step 4: Show usage after cleanup ---
echo "--- After: docker system df ---"
docker system df
echo ""

echo "=== Docker prune (safe) finished successfully. ==="
exit 0
