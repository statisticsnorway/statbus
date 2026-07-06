#!/usr/bin/env bash
#
# upgrade-to-latest-gha-runner.sh — weekly refresh of the containerized GitHub
# Actions runner: pull the latest base image, rebuild, and RECREATE only when the
# image actually changed (`docker compose up -d` is a no-op for an unchanged
# image). The recreate doubles as the hygiene reset — registration survives in the
# runner-state volume, the workspace in runner-work. Design: doc-026 §4 / delta 2.
#
# Deploy to /usr/local/bin/upgrade-to-latest-gha-runner.sh. Runs as the
# github-runner user (docker group, no sudo), triggered by gha-runner-upgrade.timer.
# The trigger is box-local ON PURPOSE: a GitHub-hosted job cannot recreate the
# container it is running in.
set -euo pipefail
COMPOSE_DIR=/home/github-runner
cd "$COMPOSE_DIR"

echo "==> Rebuilding runner image (pulling latest base)"
docker compose build --pull runner

# A recreate mid-job would kill that job. The Sunday-night slot makes this
# unlikely, but skip outright if a job is executing right now — Runner.Worker
# exists only while a job runs; the timer retries next week.
if docker exec gha-runner pgrep -f Runner.Worker >/dev/null 2>&1; then
  echo "==> Runner is BUSY (a job is executing) — skipping this week's recreate."
  exit 0
fi

echo "==> Recreating if the image changed (no-op otherwise)"
docker compose up -d runner
docker image prune -f >/dev/null
docker compose ps runner
