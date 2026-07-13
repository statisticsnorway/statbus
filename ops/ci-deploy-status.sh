#!/usr/bin/env bash
#
# ci-deploy-status.sh <40-hex-commit-sha>
#
# STATBUS-170 phase 1 — the single-shot read the deploy workflow polls to learn
# whether a deploy CONVERGED (green means the box reached `completed`, not merely
# that a poke was delivered).
#
# Runs ON the target box (a niue slot user's ~/statbus, or a standalone box). Reads
# the commit-addressed public.upgrade row via `./sb psql` and reports that row's
# deploy verdict. This is READ-ONLY (a single SELECT). It performs ONE read and
# returns; the polling loop, interval and time budget live in the workflow (phase 2).
#
# STDOUT (always exactly one machine-readable line):
#     <state>|<parked>|<reason-first-line>
#   state   — the upgrade_state (or `absent` if no row yet, `unknown` on read failure)
#   parked  — true|false (recovery_parked_at set — a deploy terminal even though the
#             row state is still in_progress)
#   reason  — first line of recovery_parked_reason (parked) or error (failed/rolled_back);
#             empty otherwise. Any literal '|' in the text is rewritten to '/' so the
#             three fields always parse.
#
# EXIT CODE (the verdict the workflow branches on):
#     0   CONVERGED  state=completed                                  → deploy GREEN, stop
#    10   FAILED     failed | rolled_back | superseded | skipped |    → deploy RED, stop
#               dismissed, or parked (in_progress + recovery_parked_at)
#    20   PENDING    available | scheduled | in_progress(not parked)  → keep polling
#               or the row is absent (not discovered yet)
#    30   TRANSIENT  read failed (DB down, ssh hiccup, ./sb missing)  → tolerated tick,
#               never a verdict — keep polling; the budget decides
#    64   USAGE      missing / malformed 40-hex argument              → misconfiguration
#
# Note on the two-phase rollout (STATBUS-167 discipline): a slot that has not yet
# upgraded past the release introducing this script has no such entrypoint; ssh/sshdo
# reports 127 for the missing command. That 127 is emitted by the transport, not by
# this script — this script never exits 127. The workflow treats 127 as "slot does
# not carry the status entrypoint yet" and keeps green poke-only for that slot.

set -euo pipefail

# --- exit-code names (documented above) ---------------------------------------
readonly EX_CONVERGED=0
readonly EX_FAILED=10
readonly EX_PENDING=20
readonly EX_TRANSIENT=30
readonly EX_USAGE=64

emit() {
  # emit <state> <parked> <reason> <exit-code>
  # reason is normalised to a single '|'-safe line.
  local state="$1" parked="$2" reason="$3" code="$4"
  reason="${reason//|//}"      # keep the 3-field parse intact
  reason="${reason%%$'\n'*}"   # first line only (defensive; SQL already trims)
  printf '%s|%s|%s\n' "$state" "$parked" "$reason"
  exit "$code"
}

# --- argument validation ------------------------------------------------------
if [ "$#" -ne 1 ]; then
  echo "usage: ci-deploy-status.sh <40-hex-commit-sha>" >&2
  emit "unknown" "false" "usage: exactly one 40-hex commit sha required" "$EX_USAGE"
fi
SHA="$1"
if ! printf '%s' "$SHA" | grep -qE '^[a-f0-9]{40}$'; then
  echo "error: argument is not a 40-hex commit sha: $SHA" >&2
  emit "unknown" "false" "argument is not a 40-hex commit sha" "$EX_USAGE"
fi

# --- locate the repo root so ./sb resolves regardless of caller cwd -----------
cd "$(dirname "$0")/.." || emit "unknown" "false" "cannot cd to repo root" "$EX_TRANSIENT"
if [ ! -x ./sb ]; then
  echo "error: ./sb not found or not executable in $(pwd)" >&2
  emit "unknown" "false" "sb binary absent" "$EX_TRANSIENT"
fi

# --- read the commit-addressed row (single SELECT; SHA is regex-validated) ----
# stderr is discarded so ./sb's stale-binary WARN banner never pollutes the value.
SQL="SELECT state::text
          || '|' || (recovery_parked_at IS NOT NULL)::text
          || '|' || COALESCE(split_part(COALESCE(recovery_parked_reason, error), chr(10), 1), '')
       FROM public.upgrade
      WHERE commit_sha = '${SHA}';"

if ! ROW="$(./sb psql -t -A -c "$SQL" 2>/dev/null)"; then
  echo "warn: read of public.upgrade failed (DB unreachable?) — tolerated tick" >&2
  emit "unknown" "false" "upgrade row read failed" "$EX_TRANSIENT"
fi

ROW="$(printf '%s' "$ROW" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [ -z "$ROW" ]; then
  # No row for this commit yet — the daemon has not discovered/scheduled it. Early
  # in a deploy this is expected; keep polling.
  emit "absent" "false" "" "$EX_PENDING"
fi

# --- parse the three fields ---------------------------------------------------
STATE="${ROW%%|*}"
REST="${ROW#*|}"
PARKED="${REST%%|*}"
REASON="${REST#*|}"

# A parked row (in_progress + recovery_parked_at) is a DEPLOY terminal, so classify
# it before the plain state switch.
if [ "$PARKED" = "true" ]; then
  emit "$STATE" "true" "${REASON:-parked (recovery_parked_at set)}" "$EX_FAILED"
fi

case "$STATE" in
  completed)
    emit "$STATE" "$PARKED" "$REASON" "$EX_CONVERGED"
    ;;
  failed|rolled_back|superseded|skipped|dismissed)
    emit "$STATE" "$PARKED" "$REASON" "$EX_FAILED"
    ;;
  available|scheduled|in_progress)
    emit "$STATE" "$PARKED" "$REASON" "$EX_PENDING"
    ;;
  *)
    # Unknown/future state — do not assert a verdict; keep polling.
    echo "warn: unrecognised upgrade state '$STATE' — treating as pending" >&2
    emit "$STATE" "$PARKED" "$REASON" "$EX_PENDING"
    ;;
esac
