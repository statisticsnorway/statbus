#!/bin/bash
# Arc: postswap-mid-migration-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# ONE-SHOT KillHere → FORWARD-recovery → COMPLETED (distinct from the CAT-A kills,
# which roll back). The kill fires at the START of runPsqlFile (migrate.go:389,
# killed-by-system-during-individual-migration-execution) — BEFORE migration 1's
# psql runs, so nothing is committed. The recovery re-enters the SAME site with the
# one-shot marker CONSUMED → no re-kill → migrate.Up re-runs BOTH shared working
# migrations → completed. The PENDING migration defeats the STATBUS-067 self-heal
# (HasPending=true → resumePostSwap does NOT short-circuit → applyPostSwap re-runs).
#
# Rides the kill-arc driver (5a): daemon-DOWN + ./sb install inline-dispatch + the
# REAL inject. NEW vs 5a: the ONE-SHOT MARKER (arc_install_dispatch_with_inject's
# 3rd arg) — the kill fires EXACTLY ONCE; the 2nd (recovery) dispatch re-enters the
# site, finds the marker gone, and forward-recovers. Uses the WORKING lineage's
# 2-migration fixture (V1+V2); the load-bearing proof is db.migration max==V_VERSION_2
# after recovery (forward-recovery re-applied BOTH migrations, not just one).
#
# Arc shape (A → B, killed mid-migration, recovered forward):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   kill           register B (daemon up) → stop daemon + schedule B → touch the
#                  one-shot marker → ./sb install WITH STATBUS_INJECT_AT + the marker
#                  → KillHere fires ONCE (exit 137) at the start of runPsqlFile.
#   RED            flag present (PostSwap); db.migration max STILL == baseline (the
#                  kill fired before migration 1 committed); DB up.
#   recovery       ./sb install WITH the same inject env (marker GONE → no re-kill)
#                  → recoverFromFlag PostSwap → resumePostSwap → applyPostSwap →
#                  migrate.Up re-runs V1+V2 → completed.
#   GREEN          row completed; db.migration max == V_VERSION_2 (BOTH applied);
#                  both fixture tables present; data intact; flag absent; healthy.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-mid-migration-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-individual-migration-execution"
KILL_MARKER="/tmp/arc-killonce-mid-migration"

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
echo "  Arc: postswap-mid-migration-kill  (one-shot KillHere → forward-recovery → completed)"
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

# Arm the one-shot kill marker (consumed by the FIRST kill; absent for recovery).
echo "── arming one-shot kill marker ($KILL_MARKER) ──"
VM_EXEC bash -c "touch $KILL_MARKER && ls -la $KILL_MARKER"

# ── LEG 1: install-until-killed (U1 FAMILY-2 fix — assertion sequencing + double-window) ──
# The one-shot kill can land on THIS install's post-swap migrate OR on its re-exec'd
# crash-recovery BOOT-migrate ("the second install's boot-migrate" the U1 log showed).
# The old arc assumed the FIRST dispatch killed and asserted 'flag present' right
# after — but a dispatch that ran PAST the window completed the upgrade (flag gone),
# so the assertion failed at the wrong point. Fix: DISPATCH UNTIL the kill is
# CONFIRMED (exit 137 + marker consumed + flag left present), pin which pass it fired
# on, and only THEN assert the RED midpoint. A dispatch that completes the upgrade
# (flag absent) = the inject window was missed → fail loud.
_flag_present() { VM_EXEC bash -c "test -e ~/statbus/tmp/upgrade-in-progress.json && echo present || echo absent" 2>/dev/null | tr -d ' \r\n'; }
_marker_state() { VM_EXEC bash -c "test -e $KILL_MARKER && echo present || echo consumed" 2>/dev/null | tr -d ' \r\n'; }
KILL_PASS=""
for _pass in 1 2; do
    arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"
    _fl=$(_flag_present); _mk=$(_marker_state)
    if [ "$ARC_DISPATCH_RC" = "137" ] && [ "$_mk" = "consumed" ] && [ "$_fl" = "present" ]; then
        KILL_PASS="$_pass"; echo "  ✓ one-shot kill fired on dispatch pass ${_pass} (exit 137, marker consumed, flag present)"; break
    fi
    if [ "$_fl" = "absent" ]; then
        echo "✗ dispatch pass ${_pass} left NO flag (rc=$ARC_DISPATCH_RC, marker=$_mk) — the upgrade ran past the mid-migration inject window without the kill landing" >&2
        exit 1
    fi
    echo "  [pass ${_pass}] no kill yet (rc=$ARC_DISPATCH_RC, marker=$_mk, flag=$_fl) — re-dispatching (double-window: the kill may land on the recovery boot-migrate)"
done
[ -n "$KILL_PASS" ] || { echo "✗ one-shot kill never fired within 2 dispatch passes — the mid-migration inject site was not reached" >&2; exit 1; }

# ── LEG 2: RED midpoint (anti-vacuity) — flag present; NOTHING committed yet (max==baseline) ──
echo ""
echo "── verifying RED state (flag present; max still baseline; marker consumed) ──"
[ "$(_flag_present)" = "present" ] || { echo "✗ expected the flag file present after the confirmed kill" >&2; exit 1; }
# 027 remedy: the max read runs with the DB mid-recovery — retry + INFRA-skip on a
# transient psql failure; never read "ERR" as a wrong-state verdict.
RED_MAX="ERR"
for _try in 1 2 3 4 5; do RED_MAX=$(migration_max_version); { [ "$RED_MAX" != "ERR" ] && [ -n "$RED_MAX" ]; } && break; sleep 3; done
if [ "$RED_MAX" = "ERR" ] || [ -z "$RED_MAX" ]; then
    echo "  ⚠ could not read db.migration max at the RED midpoint (DB mid-recovery / transport) — INFRA, skipping the max-check (flag-present above pinned the window)" >&2
else
    [ "$RED_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max moved to $RED_MAX (baseline=$BASELINE_MAX_VERSION) — kill did not fire before migration 1 committed" >&2; exit 1; }
    echo "  ✓ RED: flag present + max==baseline ($RED_MAX) — killed before migration 1 applied"
fi

# ── LEG 3: recovery — ./sb install with the marker GONE → no re-kill → forward-recover ──
echo ""
echo "── recovery: ./sb install, inject env still set, marker consumed → forward-recovery ──"
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

# ── GREEN: completed + BOTH migrations applied (max==V_VERSION_2) ──
echo ""
echo "── convergence checks (forward-recovery → completed, both migrations applied) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    completed) echo "  ✓ forward-recovery terminal: completed" ;;
    rolled_back|failed) echo "✗ state='$FINAL_STATE' — a mid-migration kill (nothing committed) must FORWARD-recover to completed, not roll back" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
# GREEN attempts pin (U1 FAMILY-2): the one-shot marker fires exactly one KILL across
# the whole arc, so a clean forward-recovery is ONE pass → recovery_attempts==1.
# Transport-aware (027): retry + INFRA-skip on a transient psql failure.
RA="ERR"
for _try in 1 2 3 4 5; do
    RA=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT recovery_attempts FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR")
    { [ "$RA" != "ERR" ] && [ -n "$RA" ]; } && break; sleep 3
done
if [ "$RA" = "ERR" ] || [ -z "$RA" ]; then
    echo "  ⚠ could not read recovery_attempts (transport) — INFRA, skipping" >&2
else
    [ "$RA" = "1" ] || { echo "✗ recovery_attempts=$RA, want 1 (one clean forward-recovery after a single mid-migration kill)" >&2; exit 1; }
    echo "  ✓ recovery_attempts == 1 (one clean forward-recovery pass)"
fi
# LOAD-BEARING: db.migration max == V_VERSION_2 proves forward-recovery re-applied
# BOTH shared working migrations (not just migration 1).
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$V_VERSION_2" ] || { echo "✗ db.migration max=$POST_MAX, want $V_VERSION_2 — forward-recovery did not apply both migrations" >&2; exit 1; }
echo "  ✓ db.migration max == V_VERSION_2 ($POST_MAX) — both working migrations applied"
# Both fixture tables present (the observable effect of V1+V2).
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
echo "PASS: postswap-mid-migration-kill (one-shot kill before migration 1 → forward-recovery re-applied V1+V2 → completed; data intact)"
