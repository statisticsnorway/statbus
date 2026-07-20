#!/usr/bin/env bash
# runner-health.sh — the niue self-hosted-runner health probe (STATBUS-069).
#
# ROLE: the hosted `runner-online` canary in notify-all-clouds.yaml SSHes to the box
# as the runner-probe user (RUNNER_HEALTH_SSH_KEY) and runs THIS script via its pinned
# sshdoers entry. It replaces the withdrawn runner-status PAT (the King challenged it;
# architect ruling replaced doc-026 delta 9): instead of asking GitHub's API whether
# the runner is registered-online, we ask the box directly, over the same SSH-key +
# sshdo authorization boundary everything else here uses.
#
# PROVENANCE (architect ruling, doc-026 delta 9 v4): ci-notify's safety was TWO legs —
# a pinned PATH and an UNPRIVILEGED executor. This probe's executor MUST be privileged
# (docker inspect needs the docker group), so the second leg is gone and is replaced by
# CONTENT PROVENANCE: this is a ROOT-PROVISIONED, SELF-CONTAINED artifact installed at a
# non-checkout path (/usr/local/sbin/statbus-runner-health) from THIS canonical copy —
# same trust class as sshdo/sshdoers. So NOT evolve-in-git like ci-notify.sh. SELF-
# CONTAINED is a HARD REQUIREMENT: depend on nothing but `docker` + POSIX/coreutils, no
# repo, no sourced files — so there is no checkout to keep current and no STATBUS-167
# gap by construction.
#
# CONTRACT: print a one-line verdict and exit 0 = HEALTHY, non-zero = UNHEALTHY (naming
# the failed layer). The canary surfaces the exit + stdout so a down runner reds the
# next push, naming why.
#
# TWO LAYERS (architect-ruled):
#   (a) the runner CONTAINER is running.
#   (b) a GitHub-SESSION-fresh signal from the LIVE runner — CALIBRATED from the
#       STATBUS-069 K1 trace (tmp/runner-health-trace-K1.out, 2026-07-20, both arms):
#         · The ONLY recurring idle write is the OAuth token-refresh pair —
#           RSAFileKeyManager "Loading RSA key parameters" + GitHubActionsService
#           "AAD Correlation ID for this token request" — metronomic every ~50m10s,
#           rock-steady over 12 cycles / 9+ hours.
#         · "Listening for Jobs" fires ONCE per session → the architect's do-not-pin
#           ruling, confirmed by observation.
#         · Part D (a deliberate 60s network drop) produced ZERO container-stdout lines
#           and ZERO in the reconnect window — there is NO positive offline signature at
#           this layer. So freshness keys on the STALENESS of the ~50m refresh cadence,
#           not on any offline line (the ruled fallback; no deviation).
#       Signal = (b1) the Runner.Listener process is alive AND (b2) a token-refresh
#       appeared within FRESH_WINDOW. b1 catches a crashed Listener that layer (a) misses
#       (the Listener is a CHILD of the container's PID 1 wrapper — trace pid 918 — so it
#       can die while the container stays up). b2 catches a wedged/dead-timer Listener.
#       Window = 65m: max observed gap 50m11s + ~15m margin for jitter/clock skew (the
#       Listener refreshes on cadence independent of any running job). Override via
#       RUNNER_HEALTH_FRESH_WINDOW for tuning without a re-provision.
# Residual (named in doc-026, unchanged): a locally-alive-but-GitHub-dead runner whose
# refresh TIMER still fires (logging the attempt before the network failure) can fake
# b2 — bounded by the notify legs themselves screaming on the next push (they queue/fail
# when the runner truly cannot take jobs). b1+b2 detect the primary failure mode (the
# Listener process crashed or its refresh loop wedged), which is what a canary must catch.
# NO pipes into grep -q in this script: under pipefail, grep -q's early exit
# SIGPIPEs the writer on a large buffer (rc 141) → the pipeline goes non-zero
# → a MATCH reads as a MISS (false STALE — caught by the K2 smoke test,
# 2026-07-20, right after a CI job ran). Herestrings (<<<) have no pipe.
set -uo pipefail

C=gha-runner   # container_name from ops/github-runner/docker-compose.yml
FRESH_WINDOW="${RUNNER_HEALTH_FRESH_WINDOW:-65m}"
TOKEN_MARK="AAD Correlation ID for this token request"

# ---- layer (a): container running -------------------------------------------------
running="$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null || echo missing)"
if [ "$running" != "true" ]; then
  echo "UNHEALTHY: runner container '$C' is not running (state=$running). [layer a]"
  exit 1
fi

# ---- layer (b1): the Runner.Listener process is alive -----------------------------
# HOST-side listing via `docker top` (the host's ps over the container's PIDs) — zero
# in-container dependencies, so a runner-image update that drops procps cannot false-red
# this sshdoers-trust-class script. docker top REQUIRES a pid column — keep `-eo pid,args`
# (empirically `-eo args` alone fails "Couldn't find PID field in ps output"; do NOT
# simplify). The bracket trick ([R]unner) keeps the grep from matching its own argv.
procs="$(docker top "$C" -eo pid,args 2>&1)" || {
  echo "UNHEALTHY: cannot list container processes (docker top error: ${procs}) — Listener liveness UNVERIFIABLE. [layer b1]"
  exit 2
}
if ! grep -q "[R]unner.Listener" <<<"$procs"; then
  echo "UNHEALTHY: container '$C' is up but the Runner.Listener process is not running — the runner is not connected to GitHub. [layer b1]"
  exit 2
fi

# ---- layer (b2): the GitHub session is FRESH (token refresh within the window) -----
logs="$(docker logs "$C" --since "$FRESH_WINDOW" 2>&1)" || {
  echo "UNHEALTHY: cannot read '$C' logs (docker error: ${logs}) — freshness UNVERIFIABLE. [layer b2]"
  exit 4
}
if ! grep -qF "$TOKEN_MARK" <<<"$logs"; then
  echo "UNHEALTHY: no OAuth token refresh in the last $FRESH_WINDOW — the runner's GitHub session is stale (its Listener stopped refreshing; expected cadence ~50m). [layer b2]"
  exit 3
fi

echo "HEALTHY: container running, Runner.Listener alive, GitHub session fresh (token refresh within $FRESH_WINDOW)."
exit 0
