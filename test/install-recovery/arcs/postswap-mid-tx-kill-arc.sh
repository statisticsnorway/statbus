#!/bin/bash
# Arc: postswap-mid-tx-kill  (STATBUS-071 §9(5) 5d / doc-017 §2 — CAT-C, NEW mechanism)
#
# THE GREEN CONTROL for the migrate commit↔record boundary (cell b). A migration is
# parked INSIDE its outer transaction (after BEGIN, before COMMIT) via
# MidTxPauseSQL (migrate.go:437, killed-by-system-during-migration-tx-before-commit
# — a KindStall whose pg_sleep(3600) splices into the tx). The harness SIGKILLs the
# install tree + pg_terminate_backend's the parked psql backend → Postgres aborts
# the UNCOMMITTED tx → NO committed-but-unrecorded state. Recovery re-applies the
# now-cleanly-pending migrations → completed. Contrast cells c/e (after-COMMIT),
# where a committed-but-unrecorded migration conflicts on re-apply → rollback.
#
# NEW mechanism vs the KillHere arcs (doc-017 §2): MidTxPauseSQL needs a STALL
# release file (KindStall) AND a manual tree-SIGKILL — so ./sb install runs in the
# BACKGROUND (it parks; it can't run foreground like the one-shot kills), the arc
# detects the parked psql (wait_for_midtx_stall_ready), SIGKILLs the tree
# (kill_pid_in_vm) + pg_terminate_backend's the backend, then a recovery ./sb
# install re-applies cleanly. Uses the WORKING lineage's 2-migration fixture; the
# park hits the FIRST pending migration (V1) → RED max==baseline; GREEN max==V_VERSION_2.
#
# Arc shape (A → B, parked mid-tx, killed, recovered forward):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   park+kill      register B → stop daemon + schedule B → touch the release file →
#                  ./sb install (BACKGROUND, tmux) WITH STATBUS_INJECT_AT + the
#                  release file → V1's tx parks mid-tx → SIGKILL the install tree +
#                  the migrate PID + pg_terminate_backend → the tx aborts.
#   RED            flag present (PostSwap); row in_progress; db.migration max ==
#                  baseline (V1's tx rolled back — NO committed-unrecorded state).
#   recovery       ./sb install (foreground, NO inject) → recoverFromFlag PostSwap →
#                  resumePostSwap → applyPostSwap → migrate re-runs V1+V2 cleanly →
#                  completed.
#   GREEN          row completed; db.migration max == V_VERSION_2; both fixture
#                  tables present; data intact; flag absent; healthy.
#
# VM-PROVE (NEW manual tree-SIGKILL mechanism — the run is the oracle).
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
echo "  Arc: postswap-mid-tx-kill  (cell b GREEN control — MidTxPauseSQL → SIGKILL → clean re-apply → completed)"
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
# and run a graceful rollback — we want the OS-kill shape (flag pinned PostSwap,
# recovered by the next install), then pg_terminate_backend aborts the orphaned tx.
# STATBUS-021 / U1 fix: capture the install tree (parent + migrate) FRESH at kill time
# and CONFIRM both dead BEFORE touching the release file. arc_kill_confirmed aborts
# loudly on a miss (releasing after a miss lets the un-killed install finish → false
# terminal). The parked PG backend running pg_sleep survives the client kill — it is
# aborted next by _terminate_migrate_backend; only then is the release safe.
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

# ── recovery: ./sb install (foreground, NO inject) → clean re-apply → completed ──
echo ""
echo "── recovery: ./sb install (clean re-apply, NO inject) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "  recovery ./sb install exit: $REC_RC"
[ "$REC_RC" != "124" ] || { echo "✗ recovery ./sb install timed out (${INSTALL_BUDGET_S}s)" >&2; exit 1; }

# ── GREEN: completed + BOTH migrations applied (max==V_VERSION_2) ──
echo ""
echo "── convergence checks (clean re-apply → completed, both migrations applied) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    completed) echo "  ✓ clean re-apply terminal: completed" ;;
    rolled_back|failed) echo "✗ state='$FINAL_STATE' — a mid-tx kill (tx aborted, nothing committed) must re-apply cleanly to completed, not roll back (cell-b GREEN control)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$V_VERSION_2" ] || { echo "✗ db.migration max=$POST_MAX, want $V_VERSION_2 — recovery did not re-apply both migrations" >&2; exit 1; }
echo "  ✓ db.migration max == V_VERSION_2 ($POST_MAX) — both migrations re-applied cleanly"
FX1=$(fixture_row_count)
[ "$FX1" = "1" ] || { echo "✗ upgrade_arc_fixture count=$FX1 (want 1)" >&2; exit 1; }
FX2=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_fixture_2;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR")
[ "$FX2" = "1" ] || { echo "✗ upgrade_arc_fixture_2 count=$FX2 (want 1)" >&2; exit 1; }
echo "  ✓ both fixture tables present"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: postswap-mid-tx-kill (cell b: parked mid-tx → SIGKILL → tx aborted clean → recovery re-applied V1+V2 → completed; data intact)"
