#!/bin/bash
# Arc: postswap-between-migrations-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# ONE-SHOT KillHere → FORWARD-recovery → COMPLETED, killed BETWEEN two migrations.
# The kill fires inside runUp's loop AFTER migration 1's db.migration INSERT
# succeeds and BEFORE migration 2's runPsqlFile (migrate.go:912,
# killed-by-system-between-migrations). So migration 1 is RECORDED and migration 2
# is PENDING at kill time — this is WHY the shared working-V is TWO migrations
# (doc-017 §5 option a): a real "N recorded, N+1 pending" gap. Recovery re-enters
# with the one-shot marker consumed → no re-kill → migrate.Up re-runs ONLY the
# pending migration 2 (migration 1 already recorded) → completed. The pending
# migration 2 defeats the STATBUS-067 self-heal (HasPending=true).
#
# Rides the kill-arc driver (5a) + the ONE-SHOT MARKER (sibling of
# postswap-mid-migration-kill). Load-bearing GREEN proof: db.migration max ==
# V_VERSION_2 after recovery (both migrations end applied).
#
# Arc shape (A → B, killed between migrations, recovered forward):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   kill           register B → stop daemon + schedule B → touch the one-shot marker
#                  → ./sb install WITH STATBUS_INJECT_AT + the marker → KillHere
#                  fires ONCE (exit 137) between migration 1 and migration 2.
#   RED            flag present (PostSwap); db.migration max == V_VERSION (migration 1
#                  RECORDED, migration 2 pending); DB up.
#   recovery       ./sb install WITH the same inject env (marker GONE → no re-kill)
#                  → recoverFromFlag PostSwap → resumePostSwap → applyPostSwap →
#                  migrate.Up applies the pending migration 2 → completed.
#   GREEN          row completed; db.migration max == V_VERSION_2; both fixture
#                  tables present; data intact; flag absent; healthy.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-between-migrations-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-between-migrations"
KILL_MARKER="/tmp/arc-killonce-between-migrations"

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

trap 'rc=$?; VM_EXEC bash -c "rm -f $KILL_MARKER 2>/dev/null" 2>/dev/null || true; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-between-migrations-kill  (one-shot KillHere between V1/V2 → forward-recovery → completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}  V=${V_VERSION}/${V_VERSION_2}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register; schedule daemon-down; dispatch with the kill ──
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

echo "── arming one-shot kill marker ($KILL_MARKER) ──"
VM_EXEC bash -c "touch $KILL_MARKER && ls -la $KILL_MARKER"

# FIRST dispatch — the kill fires ONCE between migration 1 and migration 2 (exit 137).
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

# ── RED: flag PostSwap; migration 1 RECORDED, migration 2 pending (max==V_VERSION) ──
echo ""
echo "── verifying RED state (flag present; max==V_VERSION = migration 1 recorded; marker consumed) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
RED_MAX=$(migration_max_version)
[ "$RED_MAX" = "$V_VERSION" ] || { echo "✗ db.migration max=$RED_MAX, want $V_VERSION — kill did not fire BETWEEN migration 1 (recorded) and migration 2 (pending)" >&2; exit 1; }
echo "  ✓ RED: flag present + max==V_VERSION ($RED_MAX) — migration 1 recorded, migration 2 pending"
if VM_EXEC bash -c "test -e $KILL_MARKER"; then
    echo "✗ one-shot marker still present — KillHere did not consume it (one-shot broken)" >&2; exit 1
fi
echo "  ✓ one-shot marker consumed (KillHere fired exactly once)"

# ── recovery: ./sb install WITH the inject env (marker GONE → no re-kill) → forward ──
echo ""
echo "── recovery: ./sb install, inject env still set, marker consumed → forward-recovery ──"
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

# ── GREEN: completed + BOTH migrations applied (max==V_VERSION_2) ──
echo ""
echo "── convergence checks (forward-recovery → completed, migration 2 applied) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    completed) echo "  ✓ forward-recovery terminal: completed" ;;
    rolled_back|failed) echo "✗ state='$FINAL_STATE' — a between-migrations kill (migration 1 cleanly recorded) must FORWARD-recover to completed, not roll back" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$V_VERSION_2" ] || { echo "✗ db.migration max=$POST_MAX, want $V_VERSION_2 — forward-recovery did not apply the pending migration 2" >&2; exit 1; }
echo "  ✓ db.migration max == V_VERSION_2 ($POST_MAX) — pending migration 2 applied"
FX1=$(fixture_row_count)
[ "$FX1" = "1" ] || { echo "✗ upgrade_arc_fixture count=$FX1 (want 1) — migration 1's effect missing" >&2; exit 1; }
FX2=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_fixture_2;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR")
[ "$FX2" = "1" ] || { echo "✗ upgrade_arc_fixture_2 count=$FX2 (want 1) — migration 2's effect missing" >&2; exit 1; }
echo "  ✓ both fixture tables present (upgrade_arc_fixture + upgrade_arc_fixture_2)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: postswap-between-migrations-kill (one-shot kill between V1/V2 → forward-recovery applied the pending migration 2 → completed; data intact)"
