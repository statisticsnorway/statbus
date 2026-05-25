#!/bin/bash
# Scenario 26: archivebackup-watchdog  (Bug 1 — active-phase watchdog beyond ticker scope)
#
# Class:                 archive-backup-stall-active-phase-watchdog
# Class kind:            Stall
# Source forensics:      tmp/no-deploy-hang-summary-2026-05-25.md
#
# Expected principled behavior:
#   applyPostSwap runs in the unit's ACTIVE phase (READY=1 was sent at
#   service.go:1547 inside Service.Run setup, before the main loop
#   dispatches executeUpgrade). systemd enforces WatchdogSec=120 s in
#   that phase; only WATCHDOG=1 resets the deadline.
#
#   Commit d416a50a0 introduced a WATCHDOG=1 ticker scoped only to the
#   migrate-up subprocess (service.go:3664-3686): extendCtx, extendCancel,
#   goroutine with 30 s tick, cancelled right after runCommandToLog
#   returns. The ticker DOES NOT cover the steps that follow:
#
#     - Step 11  docker compose up -d --no-build app worker rest
#     - Step 12  health check (5 polls × 5 s)
#     - Step 13  archiveBackup (tar of multi-GB backup; minutes on rune)
#     - terminal UPDATE state='completed'
#
#   archiveBackup is the worst offender: on rune.statbus.org's 35 GB
#   backup the tar takes several minutes. The main goroutine is parked
#   in runCommand("tar", ...). Without a heartbeat, WatchdogSec fires
#   around the 120 s mark; systemd SIGABRTs the unit; restart loop
#   forever (the next start re-enters applyPostSwap, hits the same
#   archiveBackup-without-ticker, gets killed again).
#
#   With the fix (active-phase ticker scope widened to cover ALL
#   post-reconnect work in applyPostSwap, including archiveBackup),
#   the ticker keeps firing WATCHDOG=1 every 30 s from a goroutine
#   independent of the main loop. The unit stays active across the
#   stall; NRestarts stays at baseline.
#
# Trigger logic (full systemd-unit dispatch — same shape as scenario 19):
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so applyPostSwap reaches archiveBackup).
#   2. Populate via populate_with_demo_data (gives data-intact
#      assertions something to check).
#   3. Snapshot data counts.
#   4. Stage HEAD on the VM (git checkout + sb binary copy) so the
#      supervised unit's executeUpgrade has HEAD's code (with the
#      inject site + the fix when it lands).
#   5. fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL" —
#      the supervised unit's discover machinery doesn't surface
#      untagged HEAD, so we INSERT directly.
#   6. Stop the upgrade-service unit. Install systemd drop-in
#      override with the C-class env vars + release file. Touch
#      the release file (so the stall holds). Restart the unit.
#   7. Wait for the upgrade row to reach 'in_progress' — proof the
#      unit picked up the scheduled row.
#   8. Hold STALL_HOLD_S=180 s (> WatchdogSec=120 s). With the fix:
#      NRestarts stays at baseline. Without the fix: NRestarts
#      climbs as systemd SIGABRTs at the 120 s mark.
#   9. Remove release file → tar proceeds → applyPostSwap finishes
#      → upgrade reaches a terminal state.
#  10. Assert NRestarts delta ≤ 1 (load-bearing — ticker keeps the
#      unit alive across the 180 s stall; 0 is the steady case,
#      1 is headroom for systemd transient quirks).
#
# Hetzner-runnability:
#   READY. Inject site lands with this commit (RED-only). The fix
#   that widens the ticker scope lands in the immediate follow-up
#   commit; before that commit, this scenario goes RED.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/26-archivebackup-watchdog.sh \
#     statbus-recovery-26

set -euo pipefail

VM_NAME="${1:-statbus-recovery-26}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120; load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"    # 15 min — covers stall + archive + completion

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release-archivebackup"
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@test.service.d"
DROPIN_FILE="$DROPIN_DIR/archivebackup-inject.conf"

trap '
    rc=$?
    VM_EXEC bash -c "
        rm -f $RELEASE_FILE 2>/dev/null || true
        rm -f $DROPIN_FILE 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user restart statbus-upgrade@test.service 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 26: archivebackup-watchdog  (Bug 1 — active-phase ticker scope)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Stall hold: ${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo ""
echo "  Tests the widened WATCHDOG=1 ticker that must cover archiveBackup"
echo "  (rune-class 35 GB tar takes minutes; without coverage WatchdogSec"
echo "  fires and the unit restart-loops forever)."
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

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage HEAD on the VM
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")
upload_sb_to_vm "$VM_NAME"

scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/scenario_26_stage_head.sh" \
    root@"$VM_IP":/tmp/scenario_26_stage_head.sh
VM_EXEC bash /tmp/scenario_26_stage_head.sh "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — fabricate scheduled upgrade row (HEAD untagged → no natural discover)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

ROW_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$ROW_STATE" != "scheduled" ]; then
    echo "✗ row for HEAD did not reach 'scheduled' state (got '$ROW_STATE')" >&2
    exit 1
fi
echo "  ✓ public.upgrade row at HEAD is state='scheduled'"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — install drop-in + release file, restart unit
# ─────────────────────────────────────────────────────────────────────────
NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

echo ""
echo "── installing archivebackup-watchdog drop-in + release file ──"
VM_EXEC bash -c "
    systemctl --user stop statbus-upgrade@test.service 2>/dev/null || true
    mkdir -p $DROPIN_DIR
    cat > $DROPIN_FILE << 'EOF'
[Service]
Environment=STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
EOF
    touch $RELEASE_FILE
    systemctl --user daemon-reload
    systemctl --user start statbus-upgrade@test.service
"

sleep 5
UNIT_STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@test.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE" != "active" ]; then
    echo "✗ unit did not reach active after restart with drop-in (state=$UNIT_STATE)" >&2
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@test.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ unit active with inject env vars in place"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — wait for the unit to reach archiveBackup (i.e., pass health check)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for upgrade row to transition to 'in_progress' ──"
START_TS=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge 180 ]; then
        echo "✗ unit did not transition row to in_progress within 180s" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, started_at FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$STATE" = "in_progress" ]; then
        echo "  ✓ upgrade row in_progress (t+${elapsed}s) — unit is inside executeUpgrade"
        break
    fi
    sleep 5
done

# At this point we wait until the executeUpgrade flow PROGRESSES to the
# archiveBackup step. There's no precise database signal — archiveBackup
# happens AFTER setMaintenance(false) but BEFORE the terminal UPDATE. We
# poll for the maintenance flag to disappear (proxy resumes serving) +
# state still 'in_progress' (row not yet terminal). That window IS the
# archiveBackup-then-stall.
echo ""
echo "── waiting for archiveBackup to be reached (maintenance off + still in_progress) ──"
START_TS=$(date +%s)
ARCHIVE_REACHED=0
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge 300 ]; then
        echo "✗ archiveBackup window not reached within 300s" >&2
        exit 1
    fi
    MAINT_PRESENT=$(VM_EXEC bash -c "[ -f ~/maintenance ] && echo 1 || echo 0" 2>/dev/null | tr -d ' \r\n' || echo "?")
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$MAINT_PRESENT" = "0" ] && [ "$STATE" = "in_progress" ]; then
        ARCHIVE_REACHED=1
        echo "  ✓ archiveBackup window reached (t+${elapsed}s): maintenance off + state=in_progress"
        break
    fi
    sleep 3
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — hold the stall for > WatchdogSec
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the archive-backup stall for ${STALL_HOLD_S}s (> WatchdogSec=120s) ──"
sleep "$STALL_HOLD_S"

NRESTARTS_DURING=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  NRestarts at stall-hold-end: $NRESTARTS_DURING (baseline=$NRESTARTS_BASELINE)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — release the stall + wait for the upgrade to complete
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing release file; tar proceeds and upgrade completes ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"

START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge $((UPGRADE_BUDGET_S - STALL_HOLD_S)) ]; then
        echo "✗ upgrade did not reach terminal state within budget" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade reached state='$STATE' (t+${elapsed}s after release)"
            break
            ;;
    esac
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 9 — assertions
#
# Load-bearing: NRestarts MUST stay bounded across the 180s stall. The
# post-fix expectation is delta ≤ 1 (0 in the steady case; 1 of headroom
# for systemd transient quirks). Anything higher means the WATCHDOG=1
# ticker is not firing across archiveBackup and the watchdog tripped.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── Bug 1 regression check (LOAD-BEARING) ──"

NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"

if [ "$RESTART_DELTA" -gt 1 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA during the archive-backup stall — Bug 1 fix not in effect"
    echo "  The WATCHDOG=1 ticker is not covering archiveBackup."
    echo "  Check that applyPostSwap's active-phase ticker scope reaches archiveBackup"
    echo "  (the d416a50a0 ticker was scoped to migrate-up only — needs widening)."
    exit 1
fi
echo "  ✓ NRestarts within tolerance — Bug 1 fix holds"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

if [ "$FINAL_STATE" = "completed" ]; then
    assert_health_passes "$VM_NAME"
fi

echo ""
echo "PASS: archivebackup-watchdog (WATCHDOG=1 ticker covered the ${STALL_HOLD_S}s stall across archiveBackup)"
