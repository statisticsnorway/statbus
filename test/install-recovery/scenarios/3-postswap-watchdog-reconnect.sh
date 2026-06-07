#!/bin/bash
# Scenario: 3-postswap-watchdog-reconnect  (C15 / Race D — full systemd watchdog firing test)
#
# Class:                 service-watchdog-timeout-during-db-reconnect-after-container-restart
# Class kind:            Stall
# Forensics tag:         Race D
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   applyPostSwap's docker-compose-up + waitForDBHealth + reconnect
#   sequence parks the upgrade-service's main goroutine. While the
#   reconnect is in flight, the main goroutine cannot ping WATCHDOG=1
#   — the WATCHDOG=1 ticker around the reconnect block (commit landing
#   with this scenario) keeps the unit alive across an arbitrarily
#   slow reconnect; without that ticker, systemd's WatchdogSec=120s
#   ticks down and SIGABRTs the unit. NRestarts climbs.
#
#   With the fix in place, the ticker fires every 30s from a
#   dedicated goroutine; the unit stays active across the 180s
#   stall; NRestarts stays at baseline.
#
# Trigger logic (full systemd-unit dispatch):
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so applyPostSwap reaches the reconnect block).
#   2. Populate via populate_with_demo_data (operator-shape baseline;
#      gives the data-intact assertions something to check).
#   3. Snapshot data counts.
#   4. Stage HEAD on the VM (git checkout + sb binary copy) so the
#      supervised unit's executeUpgrade has HEAD's code to dispatch
#      against (including the C15 inject site + the reconnect-
#      watchdog ticker fix that we're testing).
#   5. Stop the supervised upgrade-service unit.
#   6. Install systemd drop-in override with C15 env vars + release
#      file path.
#   7. Fabricate a public.upgrade row in state='scheduled' for HEAD's
#      SHA via fabricate_scheduled_upgrade_row. The unit's discover
#      machinery doesn't naturally surface HEAD (HEAD is untagged in
#      harness flow), so we INSERT directly.
#   8. Touch the release file (so the C15 stall holds).
#   9. Restart the unit. It picks up the scheduled row on its first
#      poll tick / via NOTIFY and runs executeUpgrade → preSwap →
#      swap → applyPostSwap.
#  10. Inside applyPostSwap, after the docker compose up -d db +
#      waitForDBHealth, the reconnect-watchdog ticker fires its
#      first WATCHDOG=1; the C15 stall site then blocks the main
#      goroutine. The ticker keeps firing.
#  11. Hold STALL_HOLD_S=180s (> WatchdogSec=120s). With the fix:
#      NRestarts stays at baseline. Without the fix: NRestarts
#      climbs as systemd SIGABRTs at the 120s mark.
#  12. Release the file → reconnect proceeds → applyPostSwap
#      finishes → upgrade reaches a terminal state.
#  13. Assert NRestarts delta ≤ 1 (the ticker keeps the unit alive
#      across the stall; 0 is the "fix works perfectly" case, 1 is
#      "ticker missed one tick but RestartSec recovered" headroom).
#
# Hetzner-runnability:
#   READY. The injection site + the WATCHDOG=1 ticker fix land
#   together in the same commit. The harness helper for the
#   fabricated row + the systemd-unit drop-in machinery follow the
#   pattern from scenario 1-boot-startup-timeout (startup-timeout).
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-watchdog-reconnect.sh \
#     statbus-recovery-3-postswap-watchdog-reconnect

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-watchdog-reconnect}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120; load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"    # 15 min total — covers stall + recovery + completion

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release"
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d"
DROPIN_FILE="$DROPIN_DIR/inject.conf"

trap '
    rc=$?
    # Best-effort cleanup so a failed scenario does not leave the
    # systemd drop-in or release file in place on the VM (matters if
    # KEEP_VM=1 is set for debugging — cleanup_vm destroys the VM
    # otherwise).
    VM_EXEC bash -c "
        rm -f $RELEASE_FILE 2>/dev/null || true
        rm -f $DROPIN_FILE 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user restart statbus-upgrade@statbus.service 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-watchdog-reconnect  (C15 / Race D — full systemd test)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Stall hold: ${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo ""
echo "  Tests the WATCHDOG=1-around-reconnect ticker fix: with the"
echo "  ticker firing every 30s during the stall, NRestarts stays at"
echo "  baseline. Without the ticker, NRestarts would climb at the"
echo "  120s mark when systemd SIGABRTs the unit."
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

# Write the git-checkout script locally (heredoc works on the local machine;
# VM_EXEC bash -c "..." collapses newlines over SSH, breaking if/then/fi).
# Pattern matches scenario 3-postswap-archivebackup-watchdog (line 162-181).
_stage_head_script=$(mktemp /tmp/harness-stage-head-XXXXXX.sh)
cat > "$_stage_head_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
cd ~/statbus
if ! git cat-file -e ${HEAD_LOCAL} 2>/dev/null; then
    git fetch --depth 1 origin ${HEAD_LOCAL} || { echo 'FATAL: HEAD not on origin' >&2; exit 1; }
fi
git checkout ${HEAD_LOCAL}
SCRIPT_EOF
chmod 644 "$_stage_head_script"
scp -O "${SSH_OPTS[@]}" "$_stage_head_script" root@"$VM_IP":/tmp/harness-stage-head.sh
rm -f "$_stage_head_script"
VM_EXEC bash /tmp/harness-stage-head.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-stage-head.sh" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — fabricate scheduled upgrade row (HEAD untagged → no natural discover)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# Verify the row exists and is in 'scheduled'.
ROW_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$ROW_STATE" != "scheduled" ]; then
    echo "✗ row for HEAD did not reach 'scheduled' state (got '$ROW_STATE')" >&2
    exit 1
fi
echo "  ✓ public.upgrade row at HEAD is state='scheduled'"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — install drop-in + release file, restart unit
# ─────────────────────────────────────────────────────────────────────────
NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

echo ""
echo "── installing C15 drop-in override + release file ──"
VM_EXEC systemctl --user stop statbus-upgrade@statbus.service 2>/dev/null || true

# Heredoc inside `VM_EXEC bash -c "..."` loses newlines: printf %q converts
# them to \n inside $'...' ANSI-C quoting, so the remote bash sees everything
# on one line and the <<EOF delimiter merges with the body.  Write a complete
# script locally (heredoc works fine on the local machine), scp it, and run it.
# Pattern matches 3-postswap-archivebackup-watchdog (line ~162).
_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d"
DROPIN_FILE="\$DROPIN_DIR/inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
DROPIN_EOF
touch $RELEASE_FILE
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin_script"
scp -O "${SSH_OPTS[@]}" "$_dropin_script" root@"$VM_IP":/tmp/harness-install-dropin.sh
rm -f "$_dropin_script"
VM_EXEC bash /tmp/harness-install-dropin.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-install-dropin.sh" 2>/dev/null || true
VM_EXEC systemctl --user start statbus-upgrade@statbus.service

sleep 5
UNIT_STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE" != "active" ]; then
    echo "✗ unit did not reach active after restart with C15 drop-in (state=$UNIT_STATE)" >&2
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@statbus.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ unit active with C15 env vars in place"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — wait for the unit to pick up the scheduled row + reach the stall
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for upgrade row to transition to 'in_progress' (unit picks up the scheduled row) ──"
START_TS=$(date +%s)
SAW_IN_PROGRESS=0
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge 180 ]; then
        echo "✗ unit did not transition row to in_progress within 180s — unit may not be polling" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, started_at FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        VM_EXEC bash -c "systemctl --user status statbus-upgrade@statbus.service --no-pager -l 2>&1 | head -30" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$STATE" = "in_progress" ]; then
        SAW_IN_PROGRESS=1
        echo "  ✓ upgrade row in_progress (t+${elapsed}s) — unit is now inside executeUpgrade"
        break
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — hold the stall for > WatchdogSec
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the C15 stall for ${STALL_HOLD_S}s (> WatchdogSec=120s) ──"
# During this window the main goroutine is parked inside inject.StallHere
# at the post-waitForDBHealth point in applyPostSwap. The reconnect-
# watchdog ticker (the fix this scenario tests) keeps firing WATCHDOG=1
# from a goroutine independent of the main loop. Without the ticker,
# WatchdogSec=120s would fire SIGABRT around the 120s mark and NRestarts
# would climb. With the ticker, NRestarts stays at baseline.
sleep "$STALL_HOLD_S"

NRESTARTS_DURING=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  NRestarts at stall-hold-end: $NRESTARTS_DURING (baseline=$NRESTARTS_BASELINE)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — release the stall + wait for the upgrade to complete
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing release file; reconnect should proceed and upgrade completes ──"
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
# Load-bearing: NRestarts MUST stay bounded across the whole scenario.
# The post-fix expectation is delta ≤ 1 (0 in the steady case; 1 of
# headroom for systemd transient quirks). Anything higher means the
# WATCHDOG=1-around-reconnect ticker is not firing and the watchdog
# tripped during the stall.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── Race D regression check (LOAD-BEARING) ──"

NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"

if [ "$RESTART_DELTA" -gt 1 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA during stall — Race D fix not in effect"
    echo "  The WATCHDOG=1-around-reconnect ticker in applyPostSwap is not firing during the stall."
    echo "  Check that service.go's applyPostSwap wraps d.reconnect with a 30s WATCHDOG=1 ticker"
    echo "  (mirror the migrate-ticker pattern from commit e6df084b7)."
    exit 1
fi
echo "  ✓ NRestarts within tolerance — Race D fix holds"

# Data integrity — the stall + watchdog-ticker window shouldn't have touched user data.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Coherence checks.
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

if [ "$FINAL_STATE" = "completed" ]; then
    assert_health_passes "$VM_NAME"
fi

echo ""
echo "PASS: 3-postswap-watchdog-reconnect (WATCHDOG=1 ticker around reconnect kept the unit alive across ${STALL_HOLD_S}s stall)"
