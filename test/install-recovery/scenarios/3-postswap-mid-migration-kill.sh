#!/bin/bash
# Scenario: 3-postswap-mid-migration-kill  (C6 / Layer 2 kill — atomic-tx retry)
#
# Class:                 killed-by-system-during-individual-migration-execution
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed ONCE at the TOP of runPsqlFile (the migration is
#   selected, applyPostSwap is in step 10, but the psql subprocess for
#   this migration has not yet been invoked) leaves no committed partial
#   state (the migration's outer transaction was never opened). With the
#   017 inline crash-recovery, this SAME install self-heals: post the
#   executeUpgrade syscall.Exec re-exec (env preserved) the install
#   detects StateCrashedUpgrade → runCrashRecovery → RecoverFromFlag →
#   forward-recovery migrate.Up. Because the kill is armed ONE-SHOT
#   (STATBUS_INJECT_KILL_AND_REMOVE_FILE, STATBUS-022), the recovery
#   migrate re-enters the kill site with the marker consumed → no-op →
#   the migration applies cleanly. End state IN THIS SINGLE INSTALL:
#   row='completed', db.migration max version BUMPED to the killed
#   migration (and any subsequent pending ones).
#
#   Differs from C5 (binary-swap-kill, scenario 2-preswap-binary-swap-kill) because here we
#   are past the binary swap AND inside step 10's migration phase.
#   Differs from the canonical C1/C2 (scenario 3-postswap-migrate-killed-after-commit) because here the
#   kill is BEFORE the migration's commit (not the canonical
#   ~ms-window AFTER commit + BEFORE db.migration INSERT).
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the upgrade actually has work to do).
#   2. Populate via populate_with_demo_data (operator-shape).
#   3. Snapshot data + baseline db.migration max_version.
#   4. ARM the one-shot kill (create the marker file), then run a SINGLE
#      install at HEAD with BOTH
#      STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution
#      and STATBUS_INJECT_KILL_AND_REMOVE_FILE=<marker>. inject.KillHere
#      fires ONCE inside migrate.runPsqlFile (consuming the marker), then
#      the inline recovery's migrate re-enters the site as a no-op and the
#      upgrade self-heals.
#   5. Assert the kill fired exactly once: the marker file is consumed
#      (absent) after the install.
#   6. Assert convergence: row state='completed'; db.migration
#      max_version BUMPED past baseline (proves the killed migration
#      was applied by the inline recovery); data intact.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; the recovery
#   path it exercises (recoverFromFlag's HEAD-matches branch →
#   migrate.Up forward-recovery from Fix 5b → applyPostSwap resume)
#   already exists on master + this branch.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-mid-migration-kill.sh \
#     statbus-recovery-3-postswap-mid-migration-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-mid-migration-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-mid-migration-kill  (C6 / Layer 2 atomic-tx retry)"
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
# Phase 3 — single self-healing install at HEAD with a ONE-SHOT C6 kill
#
# The kill is armed via STATBUS_INJECT_KILL_AND_REMOVE_FILE (STATBUS-022):
# KillHere fires EXACTLY ONCE — it removes the marker, then os.Exit(137). The
# 017 inline crash-recovery (runCrashRecovery boot-migrate → RecoverFromFlag →
# forward-recovery migrate.Up) re-enters the same kill site in THIS SAME
# install process (the env survives the executeUpgrade syscall.Exec re-exec),
# but the marker is already gone → no-op → the killed migration applies cleanly
# and the upgrade self-heals to 'completed'. This models a real one-time OS
# kill. A persistent inject (STATBUS_INJECT_AT alone) would re-kill the inline
# recovery migrate → rolled_back — the bug this scenario now guards against.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── single self-healing install at HEAD with one-shot C6 kill ──"
ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)

# Absolute path of the one-shot arming marker on the VM (statbus $HOME, OUTSIDE
# ~/statbus so `git checkout` never touches it). KillHere removes it on the
# single fire; we assert its absence afterwards as proof the kill engaged once.
ARM_FILE=$(VM_EXEC bash -c 'echo "$HOME/inject-kill-arm-c6"' 2>/dev/null | tr -d ' \r\n')
echo "  one-shot arm marker: $ARM_FILE"

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
STATBUS_INJECT_KILL_AND_REMOVE_FILE=$ARM_FILE \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c6.sh
upload_sb_to_vm "$VM_NAME"

# Seed a scheduled public.upgrade row at HEAD so the install state detector
# classifies as StateScheduledUpgrade (and dispatches executeUpgrade → migrate →
# the C6 kill site at runPsqlFile). Without this, the install sees nothing-scheduled
# (current==target: both derive from the running binary's ldflags version, which
# is HEAD after upload_sb_to_vm overwrote the v2026.05.2 binary) → idempotent
# step-table refresh → exits 0 → KillHere never fires. Pattern-A fix (harness
# regression run 26539222000).
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# Arm the one-shot kill: create the marker the install env points at.
VM_EXEC bash -c "touch '$ARM_FILE'"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c6.sh"
FIRST_EXIT=$?
set -e
echo "  install exited: $FIRST_EXIT (0 = self-healed past the one-time kill)"

if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ install timed out — kill site did not fire or recovery hung" >&2
    exit 1
fi
# The single install must exit 0 — that IS this scenario's claim (self-healed past
# the one-time kill to completed). A non-zero exit (notably 75 = rolled_back) is the
# regression the one-shot inject prevents; localize it here at the install boundary.
if [ "$FIRST_EXIT" != "0" ]; then
    echo "✗ single install exited $FIRST_EXIT (want 0; non-zero such as 75 = a rolled_back regression)" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — assert the one-shot kill fired EXACTLY ONCE
#
# KillHere os.Remove()s the marker before os.Exit(137). The marker's absence
# proves the injected kill engaged (the migrate subprocess reached the C6 site);
# its consumption is precisely what let the subsequent inline recovery migrate
# re-enter the site as a no-op and apply the migration cleanly.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying the one-shot kill fired exactly once ──"
if VM_EXEC bash -c "test -e '$ARM_FILE'" 2>/dev/null; then
    echo "✗ one-shot arm marker still present ($ARM_FILE) — the injected C6 kill never fired" >&2
    exit 1
fi
echo "  ✓ arm marker consumed — the C6 kill fired exactly once; inline recovery then re-entered the site as a no-op"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — convergence assertions
#
# The single install self-healed: the 017 inline recovery's migrate (kill
# no-op, marker already consumed) applied the killed migration's outer
# transaction cleanly. Terminal state MUST be 'completed'; db.migration
# max_version MUST have bumped past baseline; data MUST be intact.
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
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-mid-migration-kill (single install self-healed past a one-time kill; killed migration applied cleanly, data intact)"
