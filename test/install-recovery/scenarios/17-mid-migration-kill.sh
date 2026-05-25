#!/bin/bash
# Scenario 17: mid-migration-kill  (C6 / Layer 2 kill — atomic-tx retry)
#
# Class:                 killed-by-system-during-individual-migration-execution
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed at the TOP of runPsqlFile (i.e. the migration is
#   selected, applyPostSwap is in step 10, but the psql subprocess for
#   this migration has not yet been invoked) leaves the system with:
#   new binary, flag PostSwap, db.migration max version UNCHANGED for
#   the killed migration (no commit ever happened). Recovery via the
#   next install's recoverFromFlag → resumePostSwap → applyPostSwap
#   re-entry retries migrate.Up cleanly — the migration's outer
#   transaction was never opened, so there is no partial state to
#   reconcile. End state: row='completed', db.migration max version
#   BUMPED to the killed migration (and any subsequent pending ones).
#
#   Differs from C5 (binary-swap-kill, scenario 16) because here we
#   are past the binary swap AND inside step 10's migration phase.
#   Differs from the canonical C1/C2 (scenario 08) because here the
#   kill is BEFORE the migration's commit (not the canonical
#   ~ms-window AFTER commit + BEFORE db.migration INSERT).
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the upgrade actually has work to do).
#   2. Populate via populate_with_demo_data (operator-shape).
#   3. Snapshot data + baseline db.migration max_version.
#   4. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution.
#      inject.KillHere fires inside migrate.runPsqlFile, BEFORE psql
#      runs the first pending migration. The install process exits
#      137 with the flag file pinned at PostSwap, db.migration NOT
#      yet bumped.
#   5. Verify RED: flag file present; public.upgrade row state
#      ='in_progress'; db.migration max_version UNCHANGED from
#      baseline.
#   6. Run a SECOND install (no env vars) for recovery.
#   7. Assert convergence: row state='completed'; db.migration
#      max_version BUMPED past baseline (proves the killed migration
#      was retried + applied); data intact.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; the recovery
#   path it exercises (recoverFromFlag's HEAD-matches branch →
#   migrate.Up forward-recovery from Fix 5b → applyPostSwap resume)
#   already exists on master + this branch.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/17-mid-migration-kill.sh \
#     statbus-recovery-17

set -euo pipefail

VM_NAME="${1:-statbus-recovery-17}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 17: mid-migration-kill  (C6 / Layer 2 atomic-tx retry)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# Baseline db.migration max version BEFORE the trigger. Load-bearing —
# the C6 RED assertion is that this DOES NOT bump after the kill, and
# the GREEN convergence assertion is that recovery DOES bump it.
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install at HEAD with C6 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C6 kill injection ──"
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
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c6.sh
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c6.sh"
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
echo "── verifying canonical C6 RED state ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
echo "  ✓ RED confirmed: flag present, row in_progress, db.migration unbumped (kill fired BEFORE psql ran)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# C6's recovery path is the clean case: the migration's outer
# transaction was never opened, so forward-recovery applies the
# migration without any "already exists" friction. Terminal state
# MUST be 'completed'; db.migration max_version MUST have bumped
# past baseline; data MUST be intact.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

assert_upgrade_row_state "$VM_NAME" "completed"

POST_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  post-recovery db.migration max_version: $POST_MAX_VERSION"
if [ "$POST_MAX_VERSION" -le "$BASELINE_MAX_VERSION" ]; then
    echo "✗ db.migration max_version did NOT advance (baseline=$BASELINE_MAX_VERSION post=$POST_MAX_VERSION) — recovery did not apply the killed migration" >&2
    exit 1
fi
echo "  ✓ db.migration max_version advanced ($BASELINE_MAX_VERSION → $POST_MAX_VERSION)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: mid-migration-kill (forward-recovery applied the killed migration cleanly, data intact)"
