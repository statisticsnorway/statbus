#!/bin/bash
# Scenario: 3-postswap-between-migrations-kill  (C7 / Layer 2 kill — between migration N and N+1)
#
# Class:                 killed-by-system-between-migrations
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed ONCE AFTER migration N is fully applied + its
#   db.migration INSERT committed, but BEFORE migration N+1's
#   runPsqlFile begins, leaves the cleanest possible mid-migrate
#   state — N's transaction fully committed (effects + tracking row
#   both on disk), N+1's transaction never opened.
#
#   With the 017 inline crash-recovery this SAME install self-heals:
#   post the executeUpgrade syscall.Exec re-exec (env preserved) the
#   install detects StateCrashedUpgrade → runCrashRecovery →
#   RecoverFromFlag → forward-recovery migrate.Up. Because the kill is
#   armed ONE-SHOT (STATBUS_INJECT_KILL_AND_REMOVE_FILE, STATBUS-022),
#   the recovery migrate re-enters the kill site with the marker
#   consumed → no-op → the unrecorded pending set (N+1, N+2, ...) is
#   applied cleanly. End state IN THIS SINGLE INSTALL: `db.migration`
#   includes ALL pending migrations through HEAD, row state='completed'.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (v2026.05.2 — must be FAR ENOUGH
#      behind HEAD that at least TWO migrations are pending, so the
#      "between N and N+1" point exists. The harness asserts this
#      precondition before triggering the kill.)
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data + baseline db.migration max_version.
#   4. ARM the one-shot kill (create the marker file), then run a SINGLE
#      install at HEAD with BOTH
#      STATBUS_INJECT_AT=killed-by-system-between-migrations and
#      STATBUS_INJECT_KILL_AND_REMOVE_FILE=<marker>. inject.KillHere
#      fires ONCE inside migrate.runUp's loop (consuming the marker),
#      AFTER the first pending migration's INSERT; the inline recovery's
#      migrate then re-enters the site as a no-op and self-heals.
#   5. Assert the kill fired exactly once: the marker file is consumed
#      (absent) after the install.
#   6. Assert convergence: state='completed', db.migration max_version
#      BUMPED past baseline to HEAD's expected max (every pending
#      migration applied by the inline recovery), data intact.
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
# Phase 3 — single self-healing install at HEAD with a ONE-SHOT C7 kill
#
# Armed via STATBUS_INJECT_KILL_AND_REMOVE_FILE (STATBUS-022): KillHere fires
# EXACTLY ONCE (removes the marker, then os.Exit(137)) AFTER migration N's
# db.migration INSERT but BEFORE N+1. The 017 inline crash-recovery then
# re-enters the kill site in THIS SAME install process (the env survives the
# executeUpgrade syscall.Exec re-exec); the marker is already consumed → no-op
# → the remaining migrations apply and the upgrade self-heals to 'completed'.
# A persistent inject would re-kill the inline recovery migrate → rolled_back.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── single self-healing install at HEAD with one-shot C7 kill ──"
ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)

# Absolute path of the one-shot arming marker on the VM (statbus $HOME, OUTSIDE
# ~/statbus so `git checkout` never touches it). KillHere removes it on the
# single fire; we assert its absence afterwards as proof the kill engaged once.
ARM_FILE=$(VM_EXEC bash -c 'echo "$HOME/inject-kill-arm-c7"' 2>/dev/null | tr -d ' \r\n')
echo "  one-shot arm marker: $ARM_FILE"

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
STATBUS_INJECT_KILL_AND_REMOVE_FILE=$ARM_FILE \
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
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# Arm the one-shot kill: create the marker the install env points at.
VM_EXEC bash -c "touch '$ARM_FILE'"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c7.sh"
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
# proves the injected kill engaged (the migrate subprocess reached the C7
# between-migrations site, AFTER migration N's INSERT); its consumption is
# what let the inline recovery migrate re-enter the site as a no-op and apply
# the remaining migrations.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying the one-shot kill fired exactly once ──"
if VM_EXEC bash -c "test -e '$ARM_FILE'" 2>/dev/null; then
    echo "✗ one-shot arm marker still present ($ARM_FILE) — the injected C7 kill never fired" >&2
    exit 1
fi
echo "  ✓ arm marker consumed — the C7 kill fired exactly once; inline recovery then re-entered the site as a no-op"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — convergence assertions
#
# The single install self-healed: the 017 inline recovery applied the
# remaining (unrecorded) migrations on top of the partial-but-coherent
# state left by the one-time kill. Load-bearing: state='completed',
# db.migration max_version bumped to HEAD's full expected max past
# baseline (no migrations skipped).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

assert_upgrade_row_state "$VM_NAME" "completed"

POST_RECOVERY_MAX=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  post-recovery db.migration max_version: $POST_RECOVERY_MAX"

# Strict: post-recovery max MUST exceed baseline (proves the killed +
# subsequent pending migrations were all applied by the inline recovery).
if [ "$POST_RECOVERY_MAX" -le "$BASELINE_MAX_VERSION" ]; then
    echo "✗ db.migration max_version did NOT advance (baseline=$BASELINE_MAX_VERSION post=$POST_RECOVERY_MAX)" >&2
    echo "  The inline recovery did not apply the pending migrations." >&2
    exit 1
fi
echo "  ✓ db.migration max_version advanced through recovery ($BASELINE_MAX_VERSION → $POST_RECOVERY_MAX)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-between-migrations-kill (single install self-healed past a one-time mid-loop kill; remaining migrations applied, data intact)"
