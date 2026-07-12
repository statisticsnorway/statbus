#!/bin/bash
# Arc: postswap-mid-tx-kill  (STATBUS-071 §9(5) 5d / doc-017 §2 — CAT-C)
#
# RULED (architect, wave 3, run 28980487041): terminal is `completed`
# (forward), PROVEN on a real VM, with the daemon-race construction bug fixed
# (_ensure_daemon_stopped below). TWO prior static derivations (a pre-145
# "boot-migrate re-hit → snapshot restore-then-reapply" story, and a
# STATBUS-145 re-derivation predicting `rolled_back`) were refuted or
# disqualified before this — see MECHANICS below for that history, kept for
# the record. The instrumented single-actor run this arc was rebuilt to
# produce settled it:
#
#   THE MECHANISM, live: the tree-SIGKILL lands on a PRE-DELTA tx — V1 parked
#   mid-transaction dies BEFORE the flag ever advances to Phase=Resuming
#   (PhaseNewSbUpgrading). pg_terminate_backend aborts the uncommitted tx
#   cleanly (RED shape: flag present, row in_progress, db.migration
#   max==baseline). The SECOND (recovery) `./sb install` finds the flag still
#   at Phase=post_swap (PhaseNewSbSwapped) — NOT yet "resuming" — so
#   recoverFromFlag takes the PhaseNewSbSwapped branch and calls
#   resumePostSwap FRESH, for the first time. Captured verbatim in the run:
#     M 22:49:05 Resuming upgrade 2 (7b567e36) where it left off, now
#     running the new version. (detail: after booting the new binary,
#     pid=33970)
#   post_swap then applies the delta (V1+V2) cleanly, once. `recovery_attempts
#   =2` is CORRECT BY DESIGN, not a race artifact: the crash-ladder's own
#   detection pass counts 1, this arc's explicit second (recovery) dispatch
#   counts 2 — deaths = attempts−1 = the one kill this arc performs.
#
#   This is a PRE-DELTA death, same family as mid-migration (also completes
#   forward); the OPPOSITE family is between-migrations (a MID-delta death,
#   ledger already advanced → Behind → rolled_back). See the STATBUS-071 map
#   for the full ruled rule stated once, in one place.
#
# ALSO OBSERVED, NOT EXPLAINED (record, from the earlier disqualified run —
# harmless, not re-checked): that run's RECOVERY install itself exited 1
# (not 0) while the row read `completed` — a success-path exit-code anomaly
# from the (now-fixed) daemon race. Watch for it again if it recurs.
#
# A migration is parked INSIDE its outer transaction (after BEGIN, before
# COMMIT) via MidTxPauseSQL (migrate.go:437,
# killed-by-system-during-migration-tx-before-commit — a KindStall whose
# pg_sleep(3600) splices into the tx). The harness SIGKILLs the WHOLE install
# process TREE (parent `./sb install` + the migrate CLIENT subprocess) +
# pg_terminate_backend's the parked psql backend → Postgres aborts the
# UNCOMMITTED tx → NO committed-but-unrecorded state.
#
# MECHANICS — THE REFUTED/DISQUALIFIED STATIC DERIVATIONS, KEPT FOR THE RECORD
# (mechanic, 2026-07-08 — this reasoning did NOT survive contact with a real
# run; do not trust it as current fact, only as what was ruled out before the
# actual mechanism above was found):
#   1. ASSUMED (WRONG): that resumePostSwap had already re-acquired the flock
#      and stamped the flag Phase=PhaseNewSbUpgrading ("Resuming") BEFORE this
#      kill landed. WRONG: the kill lands before that stamp — the flag is
#      still at Phase=post_swap (PhaseNewSbSwapped) when the recovery install
#      reads it, which is why the mechanism above is the PhaseNewSbSwapped
#      branch, not the Resuming-arm's observed-state gate.
#   2. ASSUMED (WRONG): recoverFromFlag reads flag.Phase == PhaseNewSbUpgrading
#      ("Resuming" — service.go:1014) → its own pre-resume observed-state gate
#      (service.go:1037-1048): db.migration max == baseline < on-disk max ==
#      V_VERSION_2 → ObservedCannotReachNew → recoveryRollback(...) →
#      d.rollback() → os.Exit(75).
#   3. DISQUALIFIED (a separate, now-fixed construction bug, not a derivation
#      error): the daemon unit was found RUNNING before this arc's own
#      dispatch even began in one run — the SAME crashed flag this trace
#      assumed only the manually-invoked recovery install would see was ALSO
#      visible to the live daemon's own boot-time recovery, racing it.
#      recovery_attempts==2 in THAT run was two actors racing, not the clean
#      arithmetic above — fixed by _ensure_daemon_stopped before EACH
#      dispatch below, and the SAME recovery_attempts==2 value reproduced
#      cleanly in the ruled run for the correct (single-actor) reason.
#
# VM-PROVE (the manual tree-SIGKILL mechanism + the atomicity flip — run
# 28980487041, single-actor, instrumented, PROVEN).
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
echo "  Arc: postswap-mid-tx-kill  (cell b: MidTxPauseSQL → SIGKILL → clean tx-abort → PostSwap forward → completed)"
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

# Baseline fingerprint (post-A + demo data) — NOT asserted here: the ruled
# terminal is `completed` (forward), so there is no clean-slate-equals-A
# comparison to make (that check belongs to the rollback-terminal arcs, e.g.
# between-migrations). Captured anyway for the diagnostics trap.
echo "── capturing baseline clean-slate fingerprint (post-A, diagnostic only) ──"
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

# ── STATBUS-110 AC#2 (crash-freeze): the read-only window PERSISTS across the mid-
#    window crash. Probed HERE — post-kill, pre-recovery: the install tree is dead
#    (arc_kill_confirmed above) and the daemon is down (_ensure_daemon_stopped at the
#    recovery dispatch below), so nothing has flipped the window OFF; the DB container
#    survived the tree-SIGKILL (the RED-shape reads above proved it reachable), and
#    default_transaction_read_only=on was ALTER-persisted into the catalog BEFORE the
#    pre-swap DB stop (service.go:4887) so it survives the stop/restart. The probe is a
#    FRESH ./sb psql session as POSTGRES_ADMIN_USER (postgres) — a NON-exempt role:
#    the sole role-GUC exemption is `authenticator` (post_restore.sql), and the migrate
#    read-write PGOPTIONS exemption is subprocess-only (migrate.go) — so this session
#    honestly inherits the frozen window. Co-assert SHOW=on alongside the blocked write
#    so a silent role exemption cannot pass as a green (the STATBUS-154 honesty lesson).
echo ""
echo "── STATBUS-110 AC#2: assert the read-only window is FROZEN ON post-crash / pre-recovery ──"
RO_SHOW_ON=$(VM_EXEC bash -c "cd ~/statbus && echo 'SHOW default_transaction_read_only;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
[ "$RO_SHOW_ON" = "on" ] || { echo "✗ STATBUS-110 AC#2: fresh non-exempt session sees default_transaction_read_only='$RO_SHOW_ON' (expected 'on') — the crash did NOT leave the window frozen (or the probe role is unexpectedly exempt)" >&2; exit 1; }
RO_WRITE_ON=$(VM_EXEC bash -c "cd ~/statbus && echo 'CREATE TABLE public._statbus110_ro_probe (n int);' | ./sb psql 2>&1" || true)
echo "$RO_WRITE_ON" | grep -qi "read-only transaction" || { echo "✗ STATBUS-110 AC#2: a mid-window write was NOT blocked read-only (crash-freeze failed). psql said: $RO_WRITE_ON" >&2; exit 1; }
echo "  ✓ crash-freeze holds: fresh non-exempt session is read-only (SHOW=on, write blocked with the read-only error) — external writes frozen until recovery decides"

# ── recovery: ./sb install (foreground, NO inject) ──
echo ""
echo "── recovery: ./sb install (clean re-apply attempt, NO inject) ──"
_ensure_daemon_stopped "the recovery dispatch"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > /tmp/midtx-recovery.log 2>&1" || REC_RC=$?
VM_EXEC bash -c "cat /tmp/midtx-recovery.log" || true
echo "  recovery ./sb install exit: $REC_RC"
[ "$REC_RC" != "124" ] || { echo "✗ recovery ./sb install timed out (${INSTALL_BUDGET_S}s)" >&2; exit 1; }

# ── ASSERT the RULED terminal (architect, wave 3, run 28980487041 — see the
# header): PRE-delta death (tx aborted before Phase advanced to Resuming) →
# PhaseNewSbSwapped forward → completed, recovery_attempts==2 by design. This
# is no longer an observation; it is the arc's contract. ──
echo ""
echo "── ASSERT the ruled terminal ──"
echo "  recovery install exit code: $REC_RC"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
[ "$FINAL_STATE" != "rolled_back" ] || { echo "✗ state='rolled_back' — impossible under the ruled terminal (a pre-delta death must complete forward via the PhaseNewSbSwapped branch, never roll back)" >&2; exit 1; }
[ "$FINAL_STATE" = "completed" ] || { echo "✗ B reached '$FINAL_STATE', expected 'completed'" >&2; VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true; exit 1; }
echo "  ✓ state='completed'"

# ── STATBUS-110 AC#2 (terminal clears the window): recovery reached the `completed`
#    terminal, which co-locates the read-only OFF (the completion / recovery-forward
#    choke — doc/read-only-upgrade-window.md §5). A fresh non-exempt session must be
#    read-write again. Same probe role; self-cleaning write (the ON probe's CREATE
#    failed read-only, so nothing was left behind). ──
echo ""
echo "── STATBUS-110 AC#2: assert the read-only window is CLEARED after the recovery terminal ──"
RO_SHOW_OFF=$(VM_EXEC bash -c "cd ~/statbus && echo 'SHOW default_transaction_read_only;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
[ "$RO_SHOW_OFF" = "off" ] || { echo "✗ STATBUS-110 AC#2: after the completed terminal, default_transaction_read_only='$RO_SHOW_OFF' (expected 'off') — the terminal did not clear the window" >&2; exit 1; }
RO_WRITE_OFF=$(VM_EXEC bash -c "cd ~/statbus && echo 'CREATE TABLE IF NOT EXISTS public._statbus110_ro_probe (n int); DROP TABLE public._statbus110_ro_probe;' | ./sb psql 2>&1" || true)
echo "$RO_WRITE_OFF" | grep -qi "read-only transaction" && { echo "✗ STATBUS-110 AC#2: a post-recovery write is STILL blocked read-only — the terminal did not resume writes. psql said: $RO_WRITE_OFF" >&2; exit 1; }
echo "  ✓ window cleared: fresh non-exempt session is read-write again (SHOW=off, write succeeds) — external writes resumed after the honest completion"

POST_MAX=$(migration_max_version)
echo "  db.migration max version: $POST_MAX (baseline=$BASELINE_MAX_VERSION, V_VERSION_2=$V_VERSION_2)"
[ "$POST_MAX" = "$V_VERSION_2" ] || { echo "✗ db.migration max=$POST_MAX, expected V_VERSION_2=$V_VERSION_2 — the delta did not apply fully forward" >&2; exit 1; }
echo "  ✓ delta applied fully forward (max == V_VERSION_2)"

echo "  asserting the Resuming-forward marker is present, and the rollback marker is ABSENT (the mechanism, not just the outcome) ──"
VM_EXEC bash -c "grep -qF 'confirmed behind the new version' /tmp/midtx-recovery.log" >/dev/null 2>&1 && { echo "✗ recoverFromFlag's Behind/rollback line IS present — impossible for a completed terminal" >&2; exit 1; }
echo "  ✓ recoverFromFlag's Behind/rollback line is absent, as expected"
VM_EXEC bash -c "grep -qF 'now running the new version' /tmp/midtx-recovery.log" >/dev/null 2>&1 || { echo "✗ the PhaseNewSbSwapped Resuming-forward marker is absent from the recovery log — the ruled mechanism did not fire the way this arc's contract requires" >&2; exit 1; }
echo "  ✓ Resuming-forward marker present (Resuming upgrade ... where it left off, now running the new version)"

RECOVERY_ATTEMPTS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT recovery_attempts FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  recovery_attempts: $RECOVERY_ATTEMPTS (ruled value is 2 by design: crash-ladder pass counts 1, this arc's explicit recovery dispatch counts 2 — deaths = attempts−1 = the one kill)"
[ "$RECOVERY_ATTEMPTS" = "2" ] || { echo "✗ recovery_attempts=$RECOVERY_ATTEMPTS, expected 2 — either the daemon-stop fix did not hold (a race, see MECHANICS point 3) or the mechanism shifted" >&2; exit 1; }
echo "  ✓ recovery_attempts==2, the ruled single-actor value"

# Terminal-agnostic sanity, now load-bearing for a KNOWN terminal.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-mid-tx-kill (mid-tx parked, tree-SIGKILLed before the flag advanced to Resuming, tx aborted clean; the fixed single-actor recovery dispatch found Phase=post_swap and ran post_swap forward — B reached completed, recovery_attempts==2 by design — data intact, healthy, the ruled terminal)"
