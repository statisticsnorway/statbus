#!/bin/bash
# Scenario 12: migration-timeout  (C12 / Race B regression net)
#
# Class:                 migration-slower-than-systemd-unit-timeout
# Forensics tag:         Race B (Layer 1)
# Source forensics:      tmp/install-state-machine-forensics.md
#                        + operator's dev journalctl (UNIT_RESULT=watchdog,
#                          NRestarts=111 — before the fix)
#
# Expected principled behavior:
#   A migration that takes longer than `WatchdogSec` (120 s in
#   ops/statbus-upgrade.service) MUST NOT trigger the systemd
#   watchdog. The upgrade-service's applyPostSwap migrate ticker
#   sends `sdNotify("WATCHDOG=1")` every 30 s from a goroutine
#   independent of the migrate subprocess; the watchdog deadline
#   resets continuously, the migration completes, the upgrade
#   reaches a terminal state, and `NRestarts` for the upgrade
#   unit stays at zero.
#
# Validates fix at commit `e6df084b7`:
#   - Pre-e6df084b7: ticker called `sdNotifyExtendTimeout(120s)` which
#     sends EXTEND_TIMEOUT_USEC. Per sd_notify(3), that extends start
#     / runtime / stop timeouts but NOT WatchdogSec. The watchdog
#     deadline ticked down past 120 s and systemd SIGKILLed the
#     upgrade-service — operator's dev: NRestarts=111. RED.
#   - Post-e6df084b7: ticker calls `sdNotify("WATCHDOG=1")`. The
#     watchdog deadline resets every 30 s. GREEN.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the upgrade actually runs migrate.up).
#   2. Populate via populate_with_demo_data (matches the operator-
#      shape of dev's wedge).
#   3. Set env: STATBUS_INJECT_AT=migration-slower-than-systemd-
#      unit-timeout, STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<file>.
#      Create the release file.
#   4. Run install_statbus_in_vm with no version — uses local HEAD,
#      which contains the C12 injection site in
#      cli/internal/migrate/migrate.go's runPsqlFile and the fixed
#      WATCHDOG=1 ticker in service.go's applyPostSwap.
#   5. The migrate subprocess (./sb migrate up under applyPostSwap)
#      hits the StallHere inside runPsqlFile and blocks. Parent's
#      WATCHDOG=1 ticker keeps the unit alive.
#   6. Harness waits STALL_HOLD_S (default 180 s — well past
#      WatchdogSec=120 s, guarantees the watchdog WOULD have fired
#      on pre-fix code). The Race B regression would manifest as
#      systemd killing the upgrade-service and incrementing NRestarts
#      during this window.
#   7. Harness removes the release file. The stall returns; the
#      migration proceeds and the install completes.
#   8. Assert: install reached a terminal state, data intact,
#      NRestarts ≤ 2 (load-bearing — the Race B regression net).
#
# Hetzner-runnability:
#   COMMITTED and ready to run. Unlike scenarios 10 (R5) and 13
#   (R1) which depend on architectural fixes pending a separate
#   arc, this scenario tests a fix that has already landed on the
#   branch (commit e6df084b7 deleted sdNotifyExtendTimeout and
#   wired WATCHDOG=1). Running this scenario today is the empirical
#   half of validating that fix; it should go GREEN on the current
#   branch tip.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/12-migration-timeout.sh \
#     statbus-recovery-12

set -euo pipefail

VM_NAME="${1:-statbus-recovery-12}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"      # > WatchdogSec=120; proves the watchdog ping fires
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"  # 15 min total — stall + migration + post-stall

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

# Cleanup trap: remove the release file even on failure so a stalled
# install doesn't keep the VM alive for the full INSTALL_BUDGET_S
# before cleanup_vm runs.
RELEASE_FILE="/tmp/stall-release-c12"
trap '
    rc=$?
    remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE" 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 12: migration-timeout  (C12 / Race B regression net)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Stall hold: ${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — bootstrap + initial install at older release
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — populate with demo data (operator-shape baseline)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"

DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2b — plant synthetic stall-target migration on VM
#
# The db-seed branch always tracks HEAD's migration level. So even though
# this scenario bootstraps at INSTALL_VERSION (an older release), the first
# install's seed-restore brings the DB to HEAD's migration level — leaving
# zero pending migrations when the second install runs ./sb migrate up.
# With len(pending)==0, runPsqlFile is never called and the C12 stall site
# in runPsqlFile is unreachable.
#
# Fix: write a harness-only no-op SQL file with timestamp 20991231235959
# (far beyond any real migration) so ./sb migrate up sees exactly one
# pending migration and the stall fires. Written only to the VM working
# copy — never committed to the repo.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── planting synthetic stall-target migration on VM ──"
SYNTHETIC_MIG="20991231235959_scenario_12_stall_target"
VM_EXEC bash -c "cat > ~/statbus/migrations/${SYNTHETIC_MIG}.up.sql << 'SQL'
-- Harness-only: scenario 12 (C12 / Race B regression net).
-- Written to the VM working copy only — NOT committed.
-- Ensures ./sb migrate up has at least one pending migration so
-- inject.StallHere in runPsqlFile is reachable regardless of whether the
-- HEAD seed already captured all production migrations (db-seed always
-- tracks HEAD, so a version-delta install path can't rely on a gap).
SELECT 1;
SQL"
echo "  synthetic migration written: migrations/${SYNTHETIC_MIG}.up.sql"

# Baseline NRestarts before triggering the upgrade. The systemd-restart-
# counter assertion at the end compares against this — any restart that
# happens during our stall window is the Race B regression.
NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — start install at HEAD with C12 stall env-vars
#
# The install_statbus_in_vm without an INSTALL_VERSION uses local HEAD,
# which contains both the inject.StallHere site in runPsqlFile and the
# fixed WATCHDOG=1 ticker in applyPostSwap. We script the env-vars
# explicitly via a custom install script (the standard helper doesn't
# expose an env-prefix hook).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── creating release file + starting install at HEAD with C12 injection ──"

VM_EXEC bash -c "touch '$RELEASE_FILE'"

# Start the install in a detached tmux session. We'll poll for the
# stall via wait_for_inject_stall_ready, then wait STALL_HOLD_S, then
# remove the release file.
ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then
    git fetch --depth 1 origin $HEAD_LOCAL || { echo "FATAL: HEAD not on origin" >&2; exit 1; }
fi
git checkout $HEAD_LOCAL
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout \
STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
scp "${SSH_OPTS[@]}" -q "$INSTALL_SCRIPT" root@"$ip":/tmp/install-c12.sh
rm -f "$INSTALL_SCRIPT"

ssh "${SSH_OPTS[@]}" root@"$ip" "
    rm -f /tmp/install-c12.exit /tmp/install-c12.log
    sudo -u statbus tmux new-session -d -s install-c12 'bash -lc \"( bash /tmp/install-c12.sh ) > /tmp/install-c12.log 2>&1; echo \\\$? > /tmp/install-c12.exit\"'
"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — wait for the stall + hold for STALL_HOLD_S
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for migration stall to be active ──"
MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE" 300 | tee /dev/stderr | tail -1)
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stall never activated within 5 min" >&2
    exit 1
fi
echo "  migrate subprocess PID=$MIGRATE_PID — holding for ${STALL_HOLD_S}s (> WatchdogSec=120s)"

# This is the load-bearing wait. While we hold, the parent upgrade-
# service's migrate ticker is firing WATCHDOG=1 every 30s. If the fix
# is regressed (e.g. someone reverts e6df084b7), the watchdog deadline
# expires at the 120s mark and systemd kills + restarts the unit.
# After STALL_HOLD_S we check NRestarts: if it grew, Race B regressed.
sleep "$STALL_HOLD_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — release the stall + wait for install to complete
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing release file; migration should proceed ──"
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

# Poll for the install tmux session to exit.
echo "  waiting for install to complete (budget remaining ~${INSTALL_BUDGET_S}s) ..."
elapsed=0
poll_s=10
max_iter=$(( (INSTALL_BUDGET_S - STALL_HOLD_S) / poll_s ))
INSTALL_EXIT=""
for ((i=0; i<max_iter; i++)); do
    if ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/install-c12.exit" 2>/dev/null; then
        INSTALL_EXIT=$(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c12.exit" 2>/dev/null | tr -d ' \n')
        break
    fi
    sleep "$poll_s"
    elapsed=$((elapsed + poll_s))
done

if [ -z "$INSTALL_EXIT" ]; then
    echo "  ✗ install did not complete within budget; tail of log:"
    ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c12.log" 2>/dev/null || true
    exit 1
fi
echo "  install exited: $INSTALL_EXIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Load-bearing: NRestarts MUST NOT have grown by more than 2 during
# the stall window. The "≤ 2" headroom tolerates legitimate restarts
# that aren't the regression we're testing (e.g. systemd unit being
# enabled mid-install). The regression we're catching is the
# "hundreds of restarts" pathology operator observed on dev (111).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── Race B regression check (load-bearing) ──"

NRESTARTS_AFTER=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_AFTER - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE after=$NRESTARTS_AFTER delta=$RESTART_DELTA"

if [ "$RESTART_DELTA" -gt 2 ]; then
    echo "  ✗ NRestarts grew by $RESTART_DELTA during stall — Race B REGRESSED"
    echo "    The applyPostSwap migrate ticker is not keeping the watchdog alive."
    echo "    Check whether the ticker still sends sdNotify(\"WATCHDOG=1\") (commit e6df084b7)."
    exit 1
fi
echo "  ✓ NRestarts within tolerance — Race B fix holds"

# Data integrity — the stall shouldn't have touched user data.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Install reached a terminal state — health check passes.
assert_health_passes "$VM_NAME"

# Coherence checks.
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: migration-timeout (WATCHDOG=1 ticker kept the unit alive across ${STALL_HOLD_S}s stall)"
