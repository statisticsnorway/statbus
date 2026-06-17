#!/bin/bash
# Scenario: 3-postswap-resume-died-rollback
#   (one-shot FlagPhaseResuming latch — a death DURING the post-swap resume
#    becomes ONE rollback, never a retry loop)
#
# Class:      upgrade-died-during-resume
# Class kind: Kill (on the resume path, AFTER the Resuming stamp)
# Contract:   doc/upgrade-timeline.md § Binary-swap restart + resume / § Complete / rollback
#
# WHAT THIS PROVES (the inverse of scenario 3-postswap-archivebackup-resume's RED signature):
#   #29 converts the post-swap resume from a retry into a single attempt. The
#   instant resumePostSwap commits to applyPostSwap on the new binary it stamps
#   the flag Phase=Resuming (service.go, FlagPhaseResuming). If THAT process then
#   dies (watchdog SIGABRT on a hung step, OOM, reboot, kill), the next
#   recoverFromFlag sees Phase=Resuming and ROLLS BACK to the snapshot instead of
#   re-resuming. So a death during resume resolves in ONE rollback cycle, not the
#   StartLimitBurst-evading loop that wedged NO/rune for 40 h (scenario 3-postswap-archivebackup-resume RED).
#
#   This is the precise gap that made the external liveness sidecar necessary;
#   the latch closes it, so #29 deletes the sidecar (one unit, no observer).
#
# NO NEW INJECT SITE: this reuses killed-by-system-during-container-restart
# (service.go applyPostSwap docker-up). That site fires AFTER the Resuming stamp
# (the stamp is at resumePostSwap's flock re-acquire; applyPostSwap runs after),
# so the kill lands with the flag already at Resuming — exactly the death the
# latch must turn into a rollback.
#
# Trigger logic (two single-injection process runs; the inject framework gates on
# ONE STATBUS_INJECT_AT at a time):
#   1. Install at INSTALL_VERSION. Populate. Snapshot data + baseline NRestarts.
#   2. Stage HEAD on the VM (so the resume runs HEAD's latch code).
#   3. RUN 1 — drive an exit-42 resume state: install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-container-restart. The kill fires
#      inside applyPostSwap; the process exits 137 with the flag pinned PostSwap
#      and the row in_progress (the resume precondition — same as scenario 3-postswap-archivebackup-resume).
#   4. Verify the resume precondition: flag present + row in_progress.
#   5. RUN 2 — install a drop-in pinning the SAME kill into the unit env, then
#      start the unit. On boot: recoverFromFlag sees PostSwap → resumePostSwap →
#      stamps Phase=Resuming → applyPostSwap → reconnect + migrate run → docker-up
#      KILL fires (137). The flag is now Resuming, the row still in_progress, and
#      migrate has already mutated the DB.
#   6. systemd Restart=always restarts the unit → recoverFromFlag sees
#      Phase=Resuming → recoveryRollback → rollback() restores the snapshot
#      (undoing the resume's migrate), marks the row rolled_back with
#      UPGRADE_DIED_DURING_RESUME, fires the Slack callback, removes the flag,
#      and exits 75 → one more restart → normal listen.
#   7. Assert ONE rollback, NOT a loop:
#        - row terminal: rolled_back (degraded only if the restore itself fails:
#          failed), error contains UPGRADE_DIED_DURING_RESUME;
#        - flag absent;
#        - NRestarts settles (bounded; ~2 — the kill restart + the rollback
#          restart — then stable), NOT climbing (the inverse of 27 RED);
#        - data restored intact from the snapshot (the resume's migrate undone);
#        - after removing the inject drop-in, the unit settles healthy + listening.
#
# Hetzner-runnability:
#   READY for the tester to run. Reuses scenario 3-postswap-archivebackup-resume's kill primitive +
#   HEAD-staging fixture + fabricate_scheduled_upgrade_row; no new inject site.
#   NOTE FOR TESTER: this scenario has not yet been run on real systemd — verify
#   on a Hetzner VM and tune the hold/budget knobs as scenario 3-postswap-archivebackup-resume required.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh \
#     statbus-recovery-3-postswap-resume-died-rollback

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-resume-died-rollback}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# Short stop grace so the kill→SIGTERM→SIGKILL stays inside the test budget; a
# normal RestartSec so the rollback restart is prompt.
INJECT_RESTART_S="${INJECT_RESTART_S:-10}"
# Watch window: long enough to see the kill → rollback → settle, and to confirm
# NRestarts does NOT keep climbing afterward (the no-loop proof).
SETTLE_WATCH_S="${SETTLE_WATCH_S:-180}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

# The standalone/cloud upgrade unit instance used by the harness VMs. Must be
# @statbus (matches the VM user) so the unit's ExecStartPre invariant
# `/usr/bin/test "%i" = "%u"` passes (see scenario 3-postswap-archivebackup-resume's note).
UNIT="statbus-upgrade@statbus.service"
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="$DROPIN_DIR/resume-died-inject.conf"

trap '
    rc=$?
    VM_EXEC bash -c "
        systemctl --user stop '"$UNIT"' 2>/dev/null || true
        rm -f '"$DROPIN_FILE"' 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user start '"$UNIT"' 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-resume-died-rollback"
echo "  (death during the post-swap resume → ONE rollback via the Resuming latch, no loop)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
SB_INSTALL_SKIP_SEED=1 install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — stage HEAD on the VM (so the resume runs HEAD's latch code)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")
upload_sb_to_vm "$VM_NAME"
scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/stage-head.sh" \
    root@"$VM_IP":/tmp/stage-head.sh
VM_EXEC bash /tmp/stage-head.sh "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — RUN 1: drive an exit-42 resume state via a mid-applyPostSwap kill.
# (Same primitive as scenario 3-postswap-archivebackup-resume: the install process exits 137, leaving the
#  flag pinned PostSwap and the row in_progress — the resume precondition.)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 1: install at HEAD, killed mid-applyPostSwap (establishes resume state) ──"
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-container-restart \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-resume-kill.sh

# Seed a scheduled public.upgrade row at HEAD so the install state detector
# classifies as StateScheduledUpgrade → executeUpgrade → applyPostSwap → kill.
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-resume-kill.sh"
FIRST_EXIT=$?
set -e
echo "  RUN 1 exited: $FIRST_EXIT (137 = injected SIGKILL semantics)"
if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ RUN 1 timed out — kill site did not fire" >&2
    exit 1
fi

echo ""
echo "── verifying resume precondition (flag present + row in_progress) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
echo "  ✓ resume precondition: flag pinned PostSwap, row in_progress"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — RUN 2: pin the SAME kill into the unit env via a drop-in, then start
# the unit. The resume stamps Phase=Resuming, runs applyPostSwap, and the kill
# fires at docker-up — a death DURING resume. The next restart MUST roll back.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 2: installing resume-died kill drop-in (the kill fires after the Resuming stamp) ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true

_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="\$DROPIN_DIR/resume-died-inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=killed-by-system-during-container-restart
# Short stop grace so the kill→SIGTERM→SIGKILL stays inside the test budget.
TimeoutStopSec=5s
RestartSec=${INJECT_RESTART_S}s
DROPIN_EOF
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin_script"
scp -O "${SSH_OPTS[@]}" "$_dropin_script" root@"$VM_IP":/tmp/harness-install-dropin.sh
rm -f "$_dropin_script"
VM_EXEC bash /tmp/harness-install-dropin.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-install-dropin.sh" 2>/dev/null || true
echo "  ✓ drop-in installed (resume will stamp Resuming, then the kill fires)"

echo "── starting unit; resume reaches docker-up and is killed in the Resuming phase ──"
VM_EXEC bash -c "systemctl --user --no-block start $UNIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — watch for the rollback to land and the unit to SETTLE. The
# load-bearing proof: the row reaches a terminal state (rolled_back) and
# NRestarts STOPS climbing — one rollback, not a loop.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── watching for rollback + settle (up to ${SETTLE_WATCH_S}s) ──"
START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$SETTLE_WATCH_S" ]; then break; fi
    NR=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ $((elapsed % 20)) -eq 0 ]; then
        echo "    [t+${elapsed}s] NRestarts=$NR row=$STATE (baseline NRestarts=$NRESTARTS_BASELINE)"
    fi
    case "$STATE" in
        rolled_back|failed)
            FINAL_STATE="$STATE"
            echo "  ✓ row reached terminal '$STATE' at t+${elapsed}s"
            break
            ;;
        completed)
            echo "✗ row reached 'completed' — the resume was NOT supposed to succeed (the kill should have died it)." >&2
            exit 1
            ;;
    esac
    sleep 5
done

if [ -z "$FINAL_STATE" ]; then
    echo "✗ row did not reach a terminal state within ${SETTLE_WATCH_S}s — the latch did not roll back" >&2
    echo "  (a stuck in_progress + climbing NRestarts here would be the OLD retry-loop wedge the latch removes)." >&2
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
    VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — assertions (LOAD-BEARING — these define the #29 latch contract)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── latch-contract checks (LOAD-BEARING) ──"

# The expected tier is rolled_back: the snapshot restore succeeds → healthy at
# the old version. (failed is acceptable only if the restore itself also fails —
# the degraded tier; flag it loudly but do not hard-fail, the latch still fired.)
if [ "$FINAL_STATE" = "failed" ]; then
    echo "  ⚠ terminal state is 'failed' (degraded tier) — the rollback's restore ALSO failed."
    echo "    The latch fired correctly, but investigate why restoreDatabase could not restore the snapshot."
else
    assert_upgrade_row_state "$VM_NAME" "rolled_back"
fi

# The error column is the unattended operator's diagnostic surface — it must name
# the latch code so support knows this was a death-during-resume, not a clean step failure.
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME"

# The flag is gone — the mutex is released so ./sb install is not wedged.
assert_flag_file_absent "$VM_NAME"

# Data restored intact from the snapshot — the resume's migrate was undone.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — the NO-LOOP proof: remove the inject drop-in and confirm NRestarts
# SETTLES (bounded; the kill restart + the rollback restart, then stable) rather
# than climbing. This is the inverse of scenario 3-postswap-archivebackup-resume's RED signature — the latch
# converts the climb into a single rollback.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing inject drop-in; confirming the unit settles (no loop) ──"
VM_EXEC bash -c "rm -f $DROPIN_FILE; systemctl --user daemon-reload; systemctl --user --no-block restart $UNIT 2>/dev/null || true"
# Bound: a death-during-resume costs the kill restart + the rollback restart;
# anything beyond a small handful past baseline means the unit is still looping
# (latch broken). The helper compares ABSOLUTE NRestarts, so bound = baseline + 5.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UNIT" "$((NRESTARTS_BASELINE + 5))"

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 3-postswap-resume-died-rollback"
echo "  (a death during the post-swap resume became ONE rollback via the Resuming latch:"
echo "   row rolled_back with UPGRADE_DIED_DURING_RESUME, snapshot restored, flag cleared,"
echo "   NRestarts bounded — no retry loop. The gap that needed the liveness sidecar is closed.)"
