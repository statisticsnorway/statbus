#!/bin/bash
# Arc: postswap-between-migrations-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# ONE-SHOT KillHere → FORWARD-recovery → COMPLETED, killed BETWEEN two migrations.
# The kill fires inside runUp's loop AFTER migration 1's db.migration INSERT
# succeeds and BEFORE migration 2's runPsqlFile (migrate.go:912,
# killed-by-system-between-migrations). So migration 1 is RECORDED and migration 2
# is PENDING at kill time — this is WHY the shared working-V is TWO migrations
# (doc-017 §5 option a): a real "N recorded, N+1 pending" gap. The pending migration 2
# defeats the STATBUS-067 self-heal (HasPending=true).
#
# NO EXPOSED RED MIDPOINT (architect ruling, from the U1 logs). On the inline path the
# migrate delta runs in the re-exec'd pass's BOOT-migrate, and the KillHere site is in
# the migrate SUBPROCESS. A dead subprocess is a STEP failure the SINGLE ./sb install
# SURVIVES — it logs 'deferring to RecoverFromFlag (STATBUS-017): ... exit status 137'
# and resumes FORWARD in the SAME invocation to completed. So the dispatch-dies-mid-
# migration cell is STRUCTURALLY UNREACHABLE from this inject site (the r12 class — the
# window closed because the product got better); the old RED-midpoint + separate-
# recovery model is void, and we assert IN-DISPATCH forward recovery instead. The
# whole-process-death-mid-migration variant IS covered — by the after-commit pair (a
# daemon-mainpid kill of the migrate step, proven green).
#
# Rides the kill-arc driver (5a) + the ONE-SHOT MARKER (sibling of
# postswap-mid-migration-kill). Load-bearing GREEN proof: db.migration max ==
# V_VERSION_2 after recovery (both migrations end applied).
#
# Arc shape (A → B, killed between migrations, recovered forward IN-DISPATCH):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   dispatch       register B → stop daemon + schedule B → touch the one-shot marker
#                  → ./sb install WITH STATBUS_INJECT_AT + the marker → KillHere fires
#                  ONCE in the migrate subprocess between migration 1 and migration 2.
#   in-dispatch    the dispatch SURVIVES the subprocess death (rc=0), defers to
#   recovery       RecoverFromFlag (STATBUS-017), applies the pending migration 2, and
#                  completes — all within the same ./sb install.
#   GREEN          kill landed (marker consumed) + rc=0 + the STATBUS-017 defer line;
#                  row completed; recovery_attempts==1; db.migration max == V_VERSION_2;
#                  both fixture tables present; data intact; flag absent; healthy.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-between-migrations-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-between-migrations"
KILL_MARKER="/tmp/arc-killonce-between-migrations"

# ── STATBUS-145 GATE [PENDING-145-REDERIVE] ──────────────────────────────────
# This arc's terminal contract is NOT yet re-derived under the minimal-boot-migrate
# geometry: the delta moved from the re-exec'd boot-migrate to the applyPostSwap
# step, voiding this arc's pre-145 "in-dispatch forward recovery → completed"
# premise. Its true terminal under 145 is determined by the slice-4 ORACLE VM run,
# not static analysis (the run is the only oracle on the upgrade system). Until
# then this arc loudly DECLINES to assert rather than assert an underived terminal.
# Exits BEFORE any VM is provisioned (zero cost). A surviving marker after slice 4
# is itself a red flag (STATBUS-145 PIN 3). Un-gated by slice 4 once the run proves
# the true terminal.
echo "SKIP [PENDING-145-REDERIVE]: terminal contract awaiting the slice-4 oracle run (STATBUS-145)"
exit 0

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

# ── SINGLE dispatch — the product recovers IN-PROCESS; there is NO exposed RED midpoint ──
# CONFIRMED MECHANISM (architect, from the U1 logs): on the inline path the migrate
# delta only ever runs in the re-exec'd pass's BOOT-migrate, and the KillHere site is
# in the migrate SUBPROCESS. A dead subprocess is a STEP failure the dispatch SURVIVES
# — the output shows 'deferring to RecoverFromFlag (STATBUS-017): ... exit status 137'
# — then resumes FORWARD in the SAME ./sb install invocation to completed (rc=0, flag
# cleared, attempts==1). So the dispatch-dies-mid-migration cell is STRUCTURALLY
# UNREACHABLE from this inject site (the r12 class — the window closed because the
# product got better); there is no torn midpoint to assert (the old RED-midpoint +
# separate-recovery model is void). The whole-process-death-mid-migration variant IS
# covered — by the after-commit pair (daemon-mainpid kill of the migrate step, green
# tonight). We therefore assert IN-DISPATCH forward recovery.
_marker_state() { VM_EXEC bash -c "test -e $KILL_MARKER && echo present || echo consumed" 2>/dev/null | tr -d ' \r\n'; }
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

echo ""
echo "── verifying IN-DISPATCH forward recovery (kill landed; dispatch survived + deferred to RecoverFromFlag) ──"
# The kill LANDED but did NOT kill the dispatch: the consumed marker proves KillHere
# fired; rc=0 proves the dispatch deferred + recovered in-process rather than dying.
[ "$(_marker_state)" = "consumed" ] || { echo "✗ one-shot marker still present — KillHere never fired (the between-migrations inject site was not reached)" >&2; exit 1; }
echo "  ✓ one-shot kill landed (marker consumed)"
[ "$ARC_DISPATCH_RC" = "0" ] || { echo "✗ dispatch exited $ARC_DISPATCH_RC — the killed migrate subprocess should be DEFERRED to RecoverFromFlag and the upgrade completed in-process (rc=0)" >&2; exit 1; }
echo "  ✓ dispatch survived the subprocess kill (rc=0) — in-process forward recovery, not a dead dispatch"
[ "$(arc_dispatch_log_has 'deferring to RecoverFromFlag (STATBUS-017)')" = "yes" ] || { echo "✗ dispatch output missing 'deferring to RecoverFromFlag (STATBUS-017)' — the in-process-recovery path is not pinned" >&2; exit 1; }
echo "  ✓ path pinned: dispatch output shows the STATBUS-017 defer line (recovered via RecoverFromFlag)"

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
    [ "$RA" = "1" ] || { echo "✗ recovery_attempts=$RA, want 1 (one clean forward-recovery after a single between-migrations kill)" >&2; exit 1; }
    echo "  ✓ recovery_attempts == 1 (one clean forward-recovery pass)"
fi
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
