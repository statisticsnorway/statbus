#!/bin/bash
# Scenario: 3-postswap-between-migrations-kill  (C7 / Layer 2 kill — between migration N and N+1)
#
# Class:                 killed-by-system-between-migrations
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed AFTER migration N is fully applied + its
#   db.migration INSERT committed, but BEFORE migration N+1's
#   runPsqlFile begins, leaves the system with: NEW binary, flag
#   PostSwap, `db.migration` includes EVERY migration up to N but
#   NONE of N+1 onwards. The wedge is the cleanest possible mid-
#   migrate state — N's transaction is fully committed (effects +
#   tracking row both on disk), N+1's transaction never opened.
#
#   Recovery via the next install's recoverFromFlag → resumePostSwap
#   → applyPostSwap re-entry → migrate.Up: the unrecorded pending
#   set (N+1, N+2, ...) is applied cleanly. End state: `db.migration`
#   includes ALL pending migrations through HEAD, row state='completed'.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (v2026.05.2 — must be FAR ENOUGH
#      behind HEAD that at least TWO migrations are pending, so the
#      "between N and N+1" point exists. The harness asserts this
#      precondition before triggering the kill.)
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data + baseline db.migration max_version.
#   4. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-between-migrations.
#      inject.KillHere fires inside migrate.runUp's loop, AFTER the
#      db.migration INSERT for the first pending migration but
#      BEFORE the loop's next iteration begins. Install exits 137.
#   5. Verify RED state: flag file present; row='in_progress';
#      db.migration max_version BUMPED past baseline by exactly 1
#      (the first pending migration was recorded, no others were).
#   6. Run a SECOND install (no env vars) for recovery.
#   7. Assert convergence: state='completed', db.migration max_version
#      BUMPED to HEAD's expected max (every pending migration applied),
#      data intact.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; the recovery
#   path (recoverFromFlag → resumePostSwap → applyPostSwap → migrate.Up)
#   already exists and handles forward-recovery from a partial-but-
#   coherent migrate state.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-between-migrations-kill.sh \
#     statbus-recovery-3-postswap-between-migrations-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-between-migrations-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-between-migrations-kill  (C7 / Layer 2 kill — between N and N+1)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION (NO seed — establish a real ≥2 migration delta) ──"
# NO-SEED baseline: the published seed is dumped at HEAD's migration level, so a
# seeded baseline leaves BASELINE_MAX_VERSION at HEAD → PENDING_COUNT=0 → the
# "<2 pending" precondition below bails. Withholding the seed leaves the baseline at
# v2026.05.2's level (max 20260520141309), so HEAD's tree has the real pending set
# (11 migrations) → ≥2 → the "between N and N+1" kill has somewhere to land.
# (See install_statbus_in_vm.)
SB_INSTALL_SKIP_SEED=1 install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# Baseline db.migration max version BEFORE the trigger. After the kill,
# this should bump by exactly 1; after recovery, it should bump to
# HEAD's expected max.
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# Pre-trigger precondition: count pending migrations at HEAD vs baseline.
# Need ≥ 2 for the "between N and N+1" point to exist.
#
# Count LOCALLY on the harness machine — HEAD's full tree is checked out here.
# The VM holds only a shallow clone of $INSTALL_VERSION; git checkout $HEAD_SHA
# silently fails (HEAD_SHA not in the clone) and ls lists the INSTALL_VERSION
# tree, so all migrations are ≤ BASELINE_MAX_VERSION → PENDING_COUNT=0 on the VM.
PENDING_COUNT=$(ls "$HARNESS_ROOT/migrations/"*.up.sql "$HARNESS_ROOT/migrations/"*.up.psql 2>/dev/null \
    | awk -F'/' '{print $NF}' | awk -F'_' '{print $1}' \
    | awk -v b="$BASELINE_MAX_VERSION" '$1 > b' | wc -l | tr -d ' ')
echo "  pending migration count at HEAD vs baseline: $PENDING_COUNT (baseline=$BASELINE_MAX_VERSION)"
if [ "$PENDING_COUNT" -lt 2 ]; then
    echo "✗ HEAD has < 2 pending migrations past baseline ($BASELINE_MAX_VERSION) — cannot test 'between N and N+1'." >&2
    echo "  Check that INSTALL_VERSION ($INSTALL_VERSION) is ≥2 migrations behind HEAD." >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install at HEAD with C7 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C7 kill injection ──"
ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then
    git fetch --depth 1 origin $HEAD_LOCAL || { echo "FATAL" >&2; exit 1; }
fi
git checkout $HEAD_LOCAL
# Re-place sb after git checkout — git checkout into an existing working dir
# leaves ~/statbus/sb as the INSTALL_VERSION binary (gitignored; not touched
# by checkout).  /tmp/sb is the host-built HEAD binary from upload_sb_to_vm.
# Pattern D fix: matches 3-postswap-migration-timeout.
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-between-migrations \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c7.sh
upload_sb_to_vm "$VM_NAME"

# Seed a scheduled upgrade row so ./sb install detects StateScheduledUpgrade
# and routes to executeUpgradeInline (where the C7 kill site fires), rather
# than detecting nothing-scheduled and running the no-op step-table path.
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c7.sh"
FIRST_EXIT=$?
set -e
echo "  first install exited: $FIRST_EXIT (137 = injected SIGKILL semantics)"

if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ first install timed out — kill site did not fire" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — verify RED state
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying canonical C7 RED state ──"

VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"

# Load-bearing: db.migration max_version bumped by exactly 1 from
# baseline. If it didn't bump at all, the kill fired BEFORE the first
# migration's INSERT (which would put us at C6, not C7). If it bumped
# by more than 1, the kill fired AFTER multiple migrations completed
# — possible but unusual; the "between N and N+1" wedge is most
# informative at delta=1.
POST_KILL_MAX=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
KILL_DELTA=$((POST_KILL_MAX - BASELINE_MAX_VERSION))
echo "  db.migration max_version post-kill: $POST_KILL_MAX (delta=$KILL_DELTA)"

if [ "$KILL_DELTA" -lt 1 ]; then
    echo "✗ db.migration max_version did not advance — kill fired BEFORE the first migration's INSERT (C6 territory, not C7)" >&2
    exit 1
fi
echo "  ✓ at least one migration recorded before kill (delta=$KILL_DELTA, expected ≥ 1)"
echo "  ✓ RED confirmed: flag PostSwap, row in_progress, partial migrate state"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# C7 recovery is the clean forward-recovery case: remaining migrations
# apply on top of the partial-but-coherent state. Load-bearing:
# state='completed', db.migration max_version bumped to HEAD's full
# expected max (no migrations skipped).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

assert_upgrade_row_state "$VM_NAME" "completed"

POST_RECOVERY_MAX=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  post-recovery db.migration max_version: $POST_RECOVERY_MAX"

# Strict: post-recovery max MUST exceed post-kill max (proves the
# unrecorded pending set was applied).
if [ "$POST_RECOVERY_MAX" -le "$POST_KILL_MAX" ]; then
    echo "✗ db.migration max_version did NOT advance during recovery (post-kill=$POST_KILL_MAX post-recovery=$POST_RECOVERY_MAX)" >&2
    echo "  Recovery did not apply the remaining migrations." >&2
    exit 1
fi
echo "  ✓ db.migration max_version advanced through recovery ($POST_KILL_MAX → $POST_RECOVERY_MAX)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-between-migrations-kill (forward-recovery completed the remaining migrations from a clean mid-loop wedge)"
