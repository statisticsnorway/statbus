#!/bin/bash
# Scenario 19: watchdog-reconnect  (C15 / Race D — inject-site reachability diagnostic)
#
# Class:                 service-watchdog-timeout-during-db-reconnect-after-container-restart
# Class kind:            Stall
# Forensics tag:         Race D
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   applyPostSwap's docker-compose-up + waitForDBHealth + reconnect
#   sequence parks the upgrade-service's main goroutine. While the
#   reconnect is in flight, NOTHING in this process is pinging
#   WATCHDOG=1 — the migrate ticker (commit e6df084b7) covers only
#   the migrate phase that comes LATER in applyPostSwap. Under the
#   supervised upgrade-service systemd unit, if the reconnect takes
#   longer than WatchdogSec (=120 s in ops/statbus-upgrade.service),
#   systemd SIGABRTs the unit and NRestarts increments.
#
# Scope of this scenario (load-bearing — DIAGNOSTIC ONLY):
#   This scenario exercises the C15 INJECT SITE — i.e. it proves the
#   stall in applyPostSwap is reachable, holds the upgrade pipeline at
#   the post-waitForDBHealth / pre-reconnect point, and releases
#   cleanly when the harness removes the file. It does NOT actually
#   fire the systemd watchdog: dispatching via the supervised unit
#   requires a row in public.upgrade for HEAD's SHA, which the unit's
#   git-tag discovery does not populate (HEAD is typically untagged
#   in the harness's flow). Routing around discovery via manual row
#   inserts is out of scope for this commit.
#
#   The watchdog-firing test surface is therefore deferred — when the
#   fix lands (a WATCHDOG=1 ticker wrapping the reconnect block,
#   mirroring e6df084b7's migrate-ticker pattern), a follow-up
#   scenario MAY be added that exercises the unit dispatch path
#   (insert public.upgrade row → `./sb upgrade apply` → unit handles).
#   This scenario surfaces the gap empirically and locks in the
#   inject site so the future regression net has a hook to use.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so applyPostSwap actually runs).
#   2. Populate via populate_with_demo_data (operator-shape baseline).
#   3. Snapshot data counts.
#   4. Run first install at HEAD with
#      STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart
#      and a release file. inject.StallHere fires inside applyPostSwap
#      AFTER waitForDBHealth and BEFORE the d.reconnect(ctx) call;
#      the install process parks there.
#   5. Harness waits for the stall to be observable (the install
#      process is alive, the release file is still in place). Holds
#      STALL_HOLD_S to give the parked-reconnect state time to be
#      visible in the upgrade.log + journalctl.
#   6. Harness removes the release file. The stall returns; reconnect
#      proceeds; the rest of applyPostSwap runs to completion.
#   7. Assert: data intact, upgrade row reached terminal state,
#      health check passes.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit. The recovery
#   path (post-release reconnect succeeds → applyPostSwap continues)
#   is the same code that runs on every successful upgrade.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/19-watchdog-reconnect.sh \
#     statbus-recovery-19

set -euo pipefail

VM_NAME="${1:-statbus-recovery-19}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_HOLD_S="${STALL_HOLD_S:-30}"           # short hold — proves stall is reachable; not testing watchdog
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release-c15"

trap '
    rc=$?
    remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE" 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 19: watchdog-reconnect  (C15 / Race D — site diagnostic)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Stall hold: ${STALL_HOLD_S}s  (reachability test, NOT watchdog test)"
echo ""
echo "  This scenario validates the C15 inject site is REACHABLE and"
echo "  the stall releases cleanly. It does NOT exercise the systemd"
echo "  watchdog — that requires unit-dispatched upgrade, out of scope."
echo "  See scenario header for the full rationale + future-fix shape."
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
# Phase 3 — first install at HEAD with C15 stall injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── creating release file + first install at HEAD with C15 stall ──"
ip=$(hcloud server ip "$VM_NAME")
VM_EXEC bash -c "touch '$RELEASE_FILE'"

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
STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart \
STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
scp "${SSH_OPTS[@]}" -q "$INSTALL_SCRIPT" root@"$ip":/tmp/install-c15.sh
rm -f "$INSTALL_SCRIPT"

# Detached tmux session so the install can park at the stall while the
# harness polls. Pattern borrowed from scenario 12.
ssh "${SSH_OPTS[@]}" root@"$ip" "
    rm -f /tmp/install-c15.exit /tmp/install-c15.log
    sudo -u statbus tmux new-session -d -s install-c15 'bash -lc \"( bash /tmp/install-c15.sh ) > /tmp/install-c15.log 2>&1; echo \\\$? > /tmp/install-c15.exit\"'
"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — wait for stall to be active
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for C15 stall to be active inside applyPostSwap ──"
# Reach-test: the install process exists AND the release file is in
# place AND the upgrade row state is in_progress (set by executeUpgrade
# before applyPostSwap runs).
STALL_REACHED=0
START_TS=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge 300 ]; then
        echo "✗ stall never reached within 300 s" >&2
        ssh "${SSH_OPTS[@]}" root@"$ip" "tail -50 /tmp/install-c15.log" 2>/dev/null || true
        exit 1
    fi
    # Three-piece probe: install proc alive, release file present,
    # upgrade row in in_progress.
    PROBE=$(VM_EXEC bash -c "
        cd ~/statbus
        ALIVE=\$(pgrep -nf '/sb install' 2>/dev/null | wc -l | tr -d ' ')
        REL=0; [ -f '$RELEASE_FILE' ] && REL=1
        STATE=\$(echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A 2>/dev/null | tr -d ' \r\n' || echo '?')
        echo \"alive=\$ALIVE rel=\$REL state=\$STATE\"
    " 2>/dev/null || echo "alive=? rel=? state=?")
    if echo "$PROBE" | grep -q "alive=1 rel=1 state=in_progress"; then
        STALL_REACHED=1
        echo "  ✓ stall active (t+${elapsed}s): $PROBE"
        break
    fi
    if [ $((elapsed % 30)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
        echo "    [t+${elapsed}s] $PROBE"
    fi
    sleep 5
done

# Brief hold so the parked-reconnect state is visible in logs.
echo "  holding the stall for ${STALL_HOLD_S}s (visibility window for upgrade.log + journalctl)"
sleep "$STALL_HOLD_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — release the stall + wait for install to complete
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing release file; reconnect should proceed ──"
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

# Poll for the install tmux session to exit.
echo "  waiting for install to complete (budget ~$((INSTALL_BUDGET_S - STALL_HOLD_S))s) ..."
elapsed=0
poll_s=10
max_iter=$(( (INSTALL_BUDGET_S - STALL_HOLD_S) / poll_s ))
INSTALL_EXIT=""
for ((i=0; i<max_iter; i++)); do
    if ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/install-c15.exit" 2>/dev/null; then
        INSTALL_EXIT=$(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c15.exit" 2>/dev/null | tr -d ' \n')
        break
    fi
    sleep "$poll_s"
    elapsed=$((elapsed + poll_s))
done

if [ -z "$INSTALL_EXIT" ]; then
    echo "  ✗ install did not complete within budget; tail of log:"
    ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c15.log" 2>/dev/null || true
    exit 1
fi
echo "  install exited: $INSTALL_EXIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Load-bearing: the upgrade completes after the stall releases (proves
# the inject site doesn't poison the rest of applyPostSwap) AND data
# is intact.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

assert_upgrade_row_state "$VM_NAME" "completed"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: watchdog-reconnect (C15 inject site reachable; stall release leads to upgrade completion; data intact)"
echo ""
echo "  NOTE: This scenario does NOT test the systemd watchdog firing — that"
echo "  requires unit-dispatched upgrade (out of scope; see scenario header)."
echo "  The fix shape — WATCHDOG=1 ticker around the reconnect block,"
echo "  mirroring commit e6df084b7's migrate-ticker pattern — lands as a"
echo "  follow-up commit. Add a watchdog-supervision scenario at that point"
echo "  if the regression net needs an active runtime check."
