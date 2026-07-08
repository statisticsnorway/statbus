#!/bin/bash
# Arc: postswap-mid-tx-kill  (STATBUS-071 §9(5) 5d / doc-017 §2 — CAT-C)
#
# RE-GATED [PENDING-145-REDERIVE] (mechanic, 2026-07-09). TWO static
# derivations of this arc's terminal have now been REFUTED (or disqualified)
# by real runs — no third armchair guess. (1) The pre-145 PROVEN PATH (run
# 28832014634, the STATBUS-105 measurement — boot-migrate re-hitting the torn
# migration → the STATBUS-017 defer → snapshot restore-then-reapply →
# completed) no longer exists under 145's floor-only boot-migrate. (2) The
# mechanic's STATBUS-145 re-derivation (below, kept for the record — NOT
# current fact: any parent death in the migration window → the Resuming-arm
# reads positively Behind → recoveryRollback → os.Exit(75)) was ALSO refuted:
# the wave-2 run's row reached `completed`. WORSE, that SAME run was
# DISQUALIFIED as evidence outright: the daemon unit (`statbus-upgrade@
# statbus.service`) was found RUNNING pre-dispatch, so TWO recovery actors
# (the daemon's own boot-time recovery AND this arc's manually-dispatched
# recovery install) raced over the SAME crashed flag —
# `recovery_attempts=2` is the fingerprint of that race, not a clean
# single-actor trace. The terminal is UNDETERMINED by analysis, and this
# run's 'completed' result cannot even be trusted as a data point. FIXED
# BELOW (construction, not a design change): the daemon unit is now
# explicitly re-confirmed stopped immediately before EACH dispatch, not just
# once via arc_schedule_daemon_down earlier — belt-and-suspenders against
# whatever left it running. The next run, single-actor and instrumented
# (STATBUS-148-style progress-log + journal capture wired in below), is what
# actually settles the terminal.
#
# ALSO OBSERVED, NOT EXPLAINED (record for the next run's observation list):
# in the disqualified run, the RECOVERY install itself exited 1 (not 0, not
# the derivation's predicted 75) while the row read `completed` — a
# success-path exit-code anomaly. Do not assume this is the race's doing or
# assert anything about it; just watch for it again on the clean re-run.
#
# A migration is parked INSIDE its outer transaction (after BEGIN, before
# COMMIT) via MidTxPauseSQL (migrate.go:437,
# killed-by-system-during-migration-tx-before-commit — a KindStall whose
# pg_sleep(3600) splices into the tx). The harness SIGKILLs the WHOLE install
# process TREE (parent `./sb install` + the migrate CLIENT subprocess) +
# pg_terminate_backend's the parked psql backend → Postgres aborts the
# UNCOMMITTED tx → NO committed-but-unrecorded state — this RED-shape half is
# UNCHANGED by 145 and UNCHANGED by this re-gating (it is about the kill's
# immediate aftermath, not about which migrate call site is hit, and it is
# NOT what was disqualified).
#
# MECHANICS — THE REFUTED/DISQUALIFIED STATIC DERIVATION, KEPT FOR THE RECORD
# (mechanic, 2026-07-08 — this reasoning did NOT survive contact with a real
# run; do not trust it as current fact, only as what was ruled out):
#   1. Unlike the KillHere arcs (between-migrations, mid-migration), THIS kill
#      takes down the ENTIRE `./sb install` process tree (arc_kill_confirmed
#      install-tree) — not just the migrate client. The FIRST `./sb install`
#      (background, tmux) genuinely DIES mid-applyPostSwap: before dying,
#      resumePostSwap had already re-acquired the flock and stamped the flag
#      Phase=PhaseNewSbUpgrading ("Resuming") on entry — that stamp survives
#      the kill on disk. Postgres itself is untouched by the tree-kill; only
#      the specific stalled backend is separately pg_terminate_backend'd,
#      aborting its open transaction (V1's tx rolls back cleanly — the RED
#      shape: flag present, row in_progress, db.migration max == baseline).
#   2. The SECOND (recovery) `./sb install` — a FRESH process, no inject —
#      finds StateCrashedUpgrade (flag on disk, dead PID) → runCrashRecovery
#      → its own boot-migrate (--to DaemonSchemaFloor) is a no-op (V1/V2 above
#      floor) → svc.RecoverFromFlag → recoverFromFlag reads flag.Phase ==
#      PhaseNewSbUpgrading ("Resuming" — service.go:1014) → recoverFromFlag's
#      own pre-resume observed-state gate (service.go:1037-1048): db.migration
#      max == baseline < on-disk max == V_VERSION_2 → ObservedCannotReachNew →
#      recoveryRollback(...) → d.rollback() → os.Exit(75).
#   3. DISQUALIFIED: the daemon unit was found RUNNING before this arc's own
#      dispatch even began — the SAME crashed flag this trace assumes only
#      the manually-invoked recovery install would see was ALSO visible to
#      the live daemon's own boot-time recovery, racing it. recovery_attempts
#      == 2 confirms two actors both counted a pass. The 'completed' terminal
#      observed in that run cannot be attributed to this (or any) single-actor
#      derivation.
#
# STATUS: OBSERVATIONAL, not a proven terminal contract. This arc now RUNS
# (the exit-0 skip is gone; the daemon-race construction bug above is fixed
# via _ensure_daemon_stopped before EACH dispatch) and captures the evidence
# an instrumented single-actor run needs, but a green PASS here does NOT
# certify which terminal is correct — it only means the box ended clean and
# healthy, recovery_attempts was checked, and the OBSERVE lines below were
# logged. The STATBUS-071 map cell for this arc STAYS [PENDING-145-REDERIVE]
# until the architect reads this run's captured evidence (OBSERVE lines +
# _dump_mid_tx_failure_diagnostics on any non-zero exit) and rules on the
# actual terminal.
#
# VM-PROVE (the manual tree-SIGKILL mechanism + the atomicity flip — the run
# is the oracle, but a single-actor, instrumented run, not the disqualified one).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-mid-tx-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-300}"
MIDTX_CLASS="killed-by-system-during-migration-tx-before-commit"
RELEASE_FILE="/tmp/arc-stall-release-midtx"
UPGRADE_UNIT="statbus-upgrade@statbus.service"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"
: "${V_VERSION_2:?V_VERSION_2 required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

# _dump_mid_tx_failure_diagnostics — STATBUS-148-style rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal +
# both installs' captured logs to STDERR before cleanup_vm reaps the VM, so
# the NEXT run (which determines this arc's true terminal) is self-sufficient
# without needing a kept VM. Best-effort throughout — a diagnostics failure
# must never mask the real assertion error that triggered this trap.
_dump_mid_tx_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log, daemon journal, both install logs) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── first (parked/killed) install log (/tmp/midtx.log) ──" >&2
    VM_EXEC bash -c "cat /tmp/midtx.log 2>/dev/null" >&2 || echo "  (could not read /tmp/midtx.log)" >&2
    echo "── recovery install log (/tmp/midtx-recovery.log) ──" >&2
    VM_EXEC bash -c "cat /tmp/midtx-recovery.log 2>/dev/null" >&2 || echo "  (could not read /tmp/midtx-recovery.log)" >&2
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── daemon unit is-active NOW (single-actor sanity — must have been inactive throughout) ──" >&2
    VM_EXEC systemctl --user is-active "$UPGRADE_UNIT" 2>/dev/null >&2 || true
    echo "── flag file + row state at exit ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_mid_tx_failure_diagnostics; fi; VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null" 2>/dev/null || true; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-mid-tx-kill  (cell b: MidTxPauseSQL → SIGKILL → clean tx-abort → terminal UNDETERMINED, instrumented observation)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${MIDTX_CLASS}  V=${V_VERSION}/${V_VERSION_2}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# _ensure_daemon_stopped — STATBUS-145 wave-2 construction fix: the daemon
# unit was found RUNNING pre-dispatch in the disqualified run, racing this
# arc's own manually-driven recovery. Re-confirm (stop + assert inactive)
# IMMEDIATELY before EACH dispatch below — not just once, earlier, via
# arc_schedule_daemon_down — so a single-actor trace is actually guaranteed
# regardless of whatever left it running before.
_ensure_daemon_stopped() {
    local label="$1"
    VM_EXEC systemctl --user stop "$UPGRADE_UNIT" 2>/dev/null || true
    local s
    s=$(VM_EXEC systemctl --user is-active "$UPGRADE_UNIT" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$s" != "active" ] || { echo "✗ daemon unit still active immediately before $label — it would race the recovery (the exact wave-2 disqualifying finding)" >&2; exit 1; }
    echo "  ✓ daemon unit confirmed stopped immediately before $label ($s)"
}

# Start ./sb install in a DETACHED tmux session — it PARKS on the mid-tx pause, so
# it cannot run foreground (arc_install_dispatch_with_inject blocks). env_prefix is
# inlined so STATBUS_INJECT_AT inherits across executeUpgrade's syscall.Exec re-exec
# into the migrate subprocess. (Mirrors scenario 3-postswap-mid-tx-kill _start_install_bg.)
_start_install_bg() {
    local session="$1" env_prefix="$2"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "
        rm -f /tmp/$session.exit /tmp/$session.log
        sudo -u statbus tmux new-session -d -s $session 'bash -lc \"cd ~/statbus && $env_prefix STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf > /tmp/$session.log 2>&1; echo \\\$? > /tmp/$session.exit\"'
    "
}

# pg_terminate_backend the parked migrate backend (application_name
# 'statbus-migrate-sql%') server-side → the open uncommitted tx rolls back,
# regardless of host-psql vs docker-exec'd in-container client.
_terminate_migrate_backend() {
    local sql; sql=$(mktemp)
    cat > "$sql" <<'SQL'
SELECT pg_terminate_backend(pid), application_name, state
  FROM pg_stat_activity
 WHERE application_name LIKE 'statbus-migrate-sql%'
   AND pid <> pg_backend_pid();
SQL
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" < "$sql" 2>/dev/null || true
    rm -f "$sql"
}

# ── A: install + prepare; register; schedule daemon-down ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
BASELINE_MAX_VERSION=$(migration_max_version)
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# Baseline fingerprint (post-A + demo data) — captured for the NEXT
# reviewer's comparison; NOT asserted against this round (the terminal is
# undetermined, so there is nothing known-correct to compare it to yet).
echo "── capturing baseline clean-slate fingerprint (post-A, observational) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# ── park V1 mid-tx via a BACKGROUND ./sb install, then SIGKILL the tree ──
echo ""
echo "── dispatch ./sb install in the background with mid-tx pause (parks V1's tx) ──"
_ensure_daemon_stopped "the first (parked) dispatch"
VM_EXEC bash -c "touch '$RELEASE_FILE'"
_start_install_bg "midtx" "STATBUS_INJECT_AT=$MIDTX_CLASS STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE"

echo "── waiting for the migration to park mid-tx (poll pg_stat_activity) ──"
# Fence with || true: under set -euo pipefail a timeout's non-zero rc would
# propagate through the pipe and abort before the emptiness check reports it.
MIGRATE_PID=$(wait_for_midtx_stall_ready "$VM_NAME" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1) || true
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ mid-tx park never activated" >&2
    VM_EXEC bash -c "cat /tmp/midtx.log 2>/dev/null" >&2 || true
    exit 1
fi
echo "  migrate subprocess parked (PID=$MIGRATE_PID)"

# RED while parked: V1's tx is OPEN + uncommitted → db.migration max NOT bumped.
RED_MAX=$(migration_max_version)
[ "$RED_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max moved to $RED_MAX (baseline=$BASELINE_MAX_VERSION) while parked — V1 should be uncommitted mid-tx" >&2; exit 1; }
echo "  ✓ parked RED: max==baseline ($RED_MAX) — V1's tx open + uncommitted"

# SIGKILL the install tree FIRST (parent + migrate) so it cannot catch the failure
# and run a graceful rollback — we want the OS-kill shape (flag pinned PostSwap/
# Resuming, recovered by the next install), then pg_terminate_backend aborts the
# orphaned tx. STATBUS-021 / U1 fix: capture the install tree (parent + migrate)
# FRESH at kill time and CONFIRM both dead BEFORE touching the release file.
# arc_kill_confirmed aborts loudly on a miss (releasing after a miss lets the
# un-killed install finish → false terminal). The parked PG backend running
# pg_sleep survives the client kill — it is aborted next by
# _terminate_migrate_backend; only then is the release safe.
arc_kill_confirmed "$VM_NAME" install-tree || exit 1
echo "── aborting the parked migrate backend (pg_terminate_backend) ──"
_terminate_migrate_backend
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

# ── RED shape: flag present, in_progress, NO committed-unrecorded (max==baseline) ──
echo ""
echo "── verifying clean mid-tx RED shape ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after kill" >&2; exit 1; }
assert_upgrade_row_state "$VM_NAME" "in_progress"
# STATBUS-027 remedy (transport-aware probe): this read runs immediately after the
# SIGKILL + pg_terminate_backend, with the DB mid-recovery — a transient psql/SSH
# failure returns "ERR" and must be RETRIED, then INFRA-skipped, NEVER read as a
# wrong-state "tx did not roll back" verdict (the exact 027/016 class). The RED shape
# is already pinned by the transport-aware assert_upgrade_row_state above, so an
# unreadable max here is safe to skip.
POST_KILL_MAX="ERR"
for _try in 1 2 3 4 5; do
    POST_KILL_MAX=$(migration_max_version)
    { [ "$POST_KILL_MAX" != "ERR" ] && [ -n "$POST_KILL_MAX" ]; } && break
    sleep 3
done
if [ "$POST_KILL_MAX" = "ERR" ] || [ -z "$POST_KILL_MAX" ]; then
    echo "  ⚠ could not read db.migration max after the kill (DB mid-recovery / transport) — INFRA, skipping the max-check (assert_upgrade_row_state above already pinned the RED shape)" >&2
else
    [ "$POST_KILL_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max=$POST_KILL_MAX (baseline=$BASELINE_MAX_VERSION) — tx did NOT roll back (committed-unrecorded? wrong cell)" >&2; exit 1; }
    echo "  ✓ RED: flag present, row in_progress, max==baseline — tx rolled back cleanly (no committed-unrecorded)"
fi

# ── recovery: ./sb install (foreground, NO inject) ──
echo ""
echo "── recovery: ./sb install (clean re-apply attempt, NO inject) ──"
_ensure_daemon_stopped "the recovery dispatch"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > /tmp/midtx-recovery.log 2>&1" || REC_RC=$?
VM_EXEC bash -c "cat /tmp/midtx-recovery.log" || true
echo "  recovery ./sb install exit: $REC_RC"
[ "$REC_RC" != "124" ] || { echo "✗ recovery ./sb install timed out (${INSTALL_BUDGET_S}s)" >&2; exit 1; }

# ── OBSERVE, DO NOT ASSERT, the terminal (STATBUS-145 wave-2 ruling — see the
# header): the derivation predicting rolled_back/exit-75 was refuted, and the
# run that refuted it was itself disqualified by the daemon race (now fixed
# above). Log everything the next reviewer needs; enforce nothing about
# which terminal is "right" until a genuinely single-actor, instrumented run
# settles it. ──
echo ""
echo "── OBSERVE (not asserted) ──"
echo "  [OBSERVE] recovery install exit code: $REC_RC"
FINAL_STATE=$(upgrade_state)
echo "  [OBSERVE] final upgrade row state: $FINAL_STATE"
POST_MAX=$(migration_max_version)
echo "  [OBSERVE] db.migration max version: $POST_MAX (baseline=$BASELINE_MAX_VERSION, V_VERSION_2=$V_VERSION_2)"
VM_EXEC bash -c "grep -qF 'confirmed behind the new version' /tmp/midtx-recovery.log" >/dev/null 2>&1 && echo "  [OBSERVE] recoverFromFlag's Resuming-arm rollback line: present" || echo "  [OBSERVE] recoverFromFlag's Resuming-arm rollback line: ABSENT"
RECOVERY_ATTEMPTS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT recovery_attempts FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] recovery_attempts: $RECOVERY_ATTEMPTS (the disqualified run showed 2 here — a single actor should show 1; >1 again means the daemon-stop fix above did not hold)"

# Terminal-agnostic sanity: whichever terminal actually occurred, a genuinely
# single-actor, well-behaved run should still end with a clean, healthy box.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS (OBSERVATIONAL ONLY — this reports observations, not a proven terminal; the STATBUS-071 map cell stays [PENDING-145-REDERIVE] until the architect reads the OBSERVE lines above and rules): postswap-mid-tx-kill (mid-tx parked, tree-SIGKILLed, tx aborted clean, single-actor recovery dispatched; the box reached a clean, healthy terminal — WHICH one, and whether recovery_attempts==1, is logged above for the next reviewer, not enforced here)"
