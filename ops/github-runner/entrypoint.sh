#!/bin/bash
# statbus-gha-runner entrypoint — the proven prior-art shape (doc-026 §1).
#
# On FIRST boot the runner registers with a short-lived (1-hour) registration
# token (RUNNER_TOKEN, read from .env once) and PERSISTS its registration into the
# /runner-state volume. Every later boot — including the weekly image refresh that
# RECREATES the container — restores that registration and skips re-registering,
# so no durable admin secret ever lives on the box (doc-026 delta 1). The runner
# binaries live in the image (/home/runner); only registration state and the work
# dir are volumes.
#
# If the state volume is ever lost, recovery is one token mint (see the FATAL
# message below) — not a crisis.
set -euo pipefail
cd /home/runner
STATE=/runner-state

: "${RUNNER_URL:=https://github.com/statisticsnorway/statbus}"
: "${RUNNER_NAME:=niue}"
: "${RUNNER_LABELS:=niue}"   # `self-hosted` is auto-added to every self-hosted runner

if [ -f "$STATE/.runner" ]; then
  # Normal path: restore the persisted registration.
  cp "$STATE/.runner" .
  cp "$STATE"/.credentials* . 2>/dev/null || true
elif [ -f .runner ]; then
  # Configured on an earlier boot of this same container but never persisted
  # (e.g. the state volume wasn't writable then) — persist it now, don't reconfigure.
  cp .runner "$STATE/"
  cp .credentials* "$STATE/" 2>/dev/null || true
elif [ -n "${RUNNER_TOKEN:-}" ]; then
  # First-ever boot: register REPO-scoped (never org-scoped — doc-026 §2) and persist.
  ./config.sh --unattended --replace \
    --url "$RUNNER_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --work _work
  cp .runner "$STATE/"
  cp .credentials* "$STATE/" 2>/dev/null || true
else
  echo "FATAL: no persisted registration in $STATE and no RUNNER_TOKEN to register with." >&2
  echo "Mint a fresh 1-hour registration token and put it in .env as RUNNER_TOKEN:" >&2
  echo "  gh api -X POST repos/statisticsnorway/statbus/actions/runners/registration-token --jq .token" >&2
  exit 1
fi

exec ./run.sh
