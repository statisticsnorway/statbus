#!/bin/bash
# Arc: postswap-mid-tx-kill  (STATBUS-071 §9(5) 5d / doc-017 §2 — CAT-C)
#
# TERMINAL FLIPPED TO rolled_back (mechanic, 2026-07-08, STATBUS-145 slice 4).
# The pre-145 PROVEN PATH (run 28832014634, the STATBUS-105 measurement) no
# longer exists: it was proven via boot-migrate re-hitting the torn migration
# → the STATBUS-017 defer → snapshot restore-then-reapply → completed. Under
# 145, boot-migrate (both sites: service.go:1934 AND install_upgrade.go:290)
# is floor-only — V1/V2 are strictly above the floor, so boot-migrate is a
# no-op on EVERY pass in this arc; the delta only ever runs at applyPostSwap's
# single site (service.go:~5467). The mechanism-independent invariant already
# on the 071 map cell applies exactly as stated: any parent death in the
# migration window leaves the ledger unadvanced → Behind → rolled_back. This
# header derives WHERE that window sits and WHICH markers fire on the inline
# dispatch path (traced against shipped code, not asserted from the map cell
# alone).
#
# A migration is parked INSIDE its outer transaction (after BEGIN, before
# COMMIT) via MidTxPauseSQL (migrate.go:437,
# killed-by-system-during-migration-tx-before-commit — a KindStall whose
# pg_sleep(3600) splices into the tx). The harness SIGKILLs the WHOLE install
# process TREE (parent `./sb install` + the migrate CLIENT subprocess) +
# pg_terminate_backend's the parked psql backend → Postgres aborts the
# UNCOMMITTED tx → NO committed-but-unrecorded state — this RED-shape half is
# UNCHANGED by 145 (it is about the kill's immediate aftermath, not about
# which migrate call site is hit).
#
# MECHANICS VERIFIED AGAINST SHIPPED CODE UNDER THE 145 GEOMETRY (mechanic,
# 2026-07-08) — read this before touching the terminal assertion or either
# install invocation's expected exit code:
#
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
#      PhaseNewSbUpgrading ("Resuming" — service.go:1014) → THIS is a
#      DIFFERENT branch than the KillHere arcs' postSwapFailure: it is
#      recoverFromFlag's own pre-resume observed-state gate, checked BEFORE
#      ever calling resumePostSwap/applyPostSwap again (service.go:1037-1048).
#      db.migration max == baseline (V1's tx aborted, never recorded) <
#      on-disk max == V_VERSION_2 → ObservedCannotReachNew → THE ATOMICITY
#      FLIP: the pending migrations are NEVER re-attempted forward at all —
#      recoverFromFlag routes straight to d.recoveryRollback(...)
#      (service.go:2621), which — after the (inapplicable here; needs TWO
#      consecutive rollback-phase deaths) same-step-twice guard — calls the
#      SAME d.rollback() the KillHere arcs use (service.go:2734), which ALWAYS
#      terminates via os.Exit(75). So the RECOVERY install's own visible exit
#      code is 75, not the pre-145 story's 0 (a fresh, clean forward re-apply
#      never happens under 145 — the very first live observed-state read after
#      any parent death in the migration window is what decides, and it is
#      Behind by construction here).
#   3. recoverFromFlag's own marker for this branch (service.go:1046, NOT
#      postSwapFailure's — a genuinely different log line since this is a
#      FRESH-PROCESS resume, not an in-process failure): "Upgrade %d (%s) was
#      interrupted while finishing and the database is confirmed behind the
#      new version; restoring this upgrade's pre-upgrade snapshot (one
#      attempt, no retry). Data is restored to before the upgrade. (detail:
#      new-sb-upgrading, observed-state=cannot-reach-new: db.migration max
#      version <baseline> < on-disk max <V2> (migrations did not run))" — this
#      IS this arc's mechanism-true marker: it also proves the flag really was
#      in the Resuming phase (this branch only fires for
#      Phase=PhaseNewSbUpgrading), not merely that SOME rollback happened.
#   4. NEITHER install invocation ever starts the daemon unit:
#      arc_schedule_daemon_down stopped it before either dispatch; the first
#      (parked, killed) install never reaches its own success path;
#      restartUpgradeService (install_upgrade.go, reached only via
#      runInlineUpgradeScheduled's SUCCESS) is a codepath for the FIRST-TIME
#      StateScheduledUpgrade dispatch, not runCrashRecovery's — and the
#      recovery install's own os.Exit(75) fires before returning from
#      dispatchInstallState regardless. Nothing to assert about that unit.
#
# VM-PROVE (the manual tree-SIGKILL mechanism + the atomicity flip's first
# live exercise on this construction — the run is the oracle).
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

trap 'rc=$?; VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null" 2>/dev/null || true; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-mid-tx-kill  (cell b: MidTxPauseSQL → SIGKILL → clean tx-abort → STATBUS-145 rollback geometry)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${MIDTX_CLASS}  V=${V_VERSION}/${V_VERSION_2}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

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

# Baseline fingerprint (post-A + demo data) — this arc's terminal is now
# rolled_back, so the failing/ceiling-arc apparatus applies verbatim.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
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

# ── recovery: ./sb install (foreground, NO inject) → the Resuming-arm's own
# observed-state read finds it positively Behind → rollback → os.Exit(75) ──
echo ""
echo "── recovery: ./sb install (clean re-apply attempt, NO inject) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > /tmp/midtx-recovery.log 2>&1" || REC_RC=$?
VM_EXEC bash -c "cat /tmp/midtx-recovery.log" || true
echo "  recovery ./sb install exit: $REC_RC"
[ "$REC_RC" != "124" ] || { echo "✗ recovery ./sb install timed out (${INSTALL_BUDGET_S}s)" >&2; exit 1; }
[ "$REC_RC" = "75" ] || { echo "✗ recovery ./sb install exited $REC_RC, expected 75 — d.rollback() (reached via recoverFromFlag's Resuming-arm → recoveryRollback) always terminates via os.Exit(75)" >&2; exit 1; }
echo "  ✓ recovery install exited 75 — the Resuming-arm's rollback terminal, not a clean forward re-apply"
# Mechanism-true marker: recoverFromFlag's OWN Resuming-arm line (service.go:1046)
# — distinct from the KillHere arcs' postSwapFailure line, since this fires on a
# FRESH process's pre-resume observed-state gate, proving the flag really was
# Phase=PhaseNewSbUpgrading (Resuming), not merely that some rollback happened.
EXPECT_REASON_SUBSTR="db.migration max version ${BASELINE_MAX_VERSION} < on-disk max ${V_VERSION_2}"
VM_EXEC bash -c "grep -qF 'confirmed behind the new version' /tmp/midtx-recovery.log" || { echo "✗ recovery output missing recoverFromFlag's Resuming-arm rollback line" >&2; exit 1; }
VM_EXEC bash -c "grep -qF '$EXPECT_REASON_SUBSTR' /tmp/midtx-recovery.log" || { echo "✗ recovery output missing the expected observed-state gap ('$EXPECT_REASON_SUBSTR')" >&2; exit 1; }
echo "  ✓ path pinned: recoverFromFlag's Resuming-arm rollback line + the exact baseline/V2 gap ($EXPECT_REASON_SUBSTR)"

# ── GREEN: rolled_back + clean-slate restored (max unchanged from baseline) ──
echo ""
echo "── convergence checks (rollback restored the pre-upgrade clean slate) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    rolled_back) echo "  ✓ rollback terminal: rolled_back" ;;
    completed) echo "✗ state='completed' — impossible under the 145 atomicity flip (any parent death in the migration window reads Behind on the very next live pass, never a fresh forward re-apply)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max=$POST_MAX, want baseline=$BASELINE_MAX_VERSION — rollback did not restore the clean slate" >&2; exit 1; }
echo "  ✓ db.migration max == baseline ($POST_MAX) — neither migration ever recorded, rollback restored the clean slate"

assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: not meaningful here — see MECHANICS point 4. Neither install
# invocation ever starts the daemon unit; arc_schedule_daemon_down's stop is
# the only touch it gets in this arc.
# DURABILITY CONDITION: rests on rollback() EXITING (os.Exit(75)), not
# returning — a return-based refactor makes runCrashRecovery's deferred
# restart closure reachable on the failure path and RE-ARMS this check.

echo ""
echo "PASS: postswap-mid-tx-kill (cell b: parked mid-tx → tree-SIGKILL → tx aborted clean → the atomicity flip's Resuming-arm found the delta positively missing on the very next pass and rolled back autonomously to a byte-identical clean slate; data intact)"
