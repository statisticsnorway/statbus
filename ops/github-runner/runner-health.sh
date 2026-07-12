#!/usr/bin/env bash
# runner-health.sh — the niue self-hosted-runner health probe (STATBUS-069).
#
# ⚠️  DRAFT: layer (b) is NOT yet calibrated — it is stubbed to FAIL CLOSED until the
#     empirical trace (runner-health-trace.sh) is run and its signal chosen. Do NOT
#     wire this into notify-all-clouds.yaml's canary until layer (b) is filled in and
#     this header banner is removed. Wiring it now would red every push.
#
# ROLE: the hosted `runner-online` canary in notify-all-clouds.yaml SSHes to the box
# as the runner-probe user (RUNNER_HEALTH_SSH_KEY) and runs THIS script via its pinned
# sshdoers entry. It replaces the withdrawn runner-status PAT (the King challenged it;
# architect ruling replaced doc-026 delta 9): instead of asking GitHub's API whether
# the runner is registered-online, we ask the box directly, over the same SSH-key +
# sshdo authorization boundary everything else here uses. sshdo pins only this PATH —
# the logic below evolves in git, like ci-notify.sh.
#
# CONTRACT: print a one-line verdict and exit 0 = HEALTHY, non-zero = UNHEALTHY. The
# canary surfaces the exit + stdout so a down runner reds the next push, naming why.
#
# TWO LAYERS (architect-ruled):
#   (a) the runner CONTAINER is running                          — done below
#   (b) a GitHub-SESSION-fresh signal from the LIVE runner       — STUB, see below
# Residual (named in doc-026): a locally-green but GitHub-dead runner that still fakes
# the fresh signal is bounded by the notify legs themselves screaming on the next push
# (they queue/fail when the runner truly cannot take jobs).
set -uo pipefail

C=gha-runner   # container_name from ops/github-runner/docker-compose.yml

# ---- layer (a): container running -------------------------------------------------
running="$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null || echo missing)"
if [ "$running" != "true" ]; then
  echo "UNHEALTHY: runner container '$C' is not running (state=$running)."
  exit 1
fi

# ---- layer (b): GitHub-session-fresh signal ---------------------------------------
# TODO(STATBUS-069): calibrate from runner-health-trace.sh output. Do NOT pin
# "Listening for Jobs" (one-shot per session → false OFFLINE when idle; and _diag
# keeps writing during disconnect-retry → false HEALTHY). The trace will reveal the
# real idle cadence and the disconnect signature; pin the signal + a window derived
# from OBSERVED behavior here. Until then this fails closed so the probe is never
# silently incomplete.
echo "UNHEALTHY: layer (b) GitHub-session-fresh signal not yet calibrated (STATBUS-069 DRAFT — run runner-health-trace.sh)."
exit 2

# When calibrated, the tail of this script becomes, roughly:
#   if <observed fresh-session signal within <observed window>>; then
#     echo "HEALTHY: container running and runner session fresh."
#     exit 0
#   fi
#   echo "UNHEALTHY: runner container up but no fresh GitHub session (offline/retrying)."
#   exit 3
