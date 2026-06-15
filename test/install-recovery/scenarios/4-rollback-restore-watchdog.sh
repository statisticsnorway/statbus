#!/bin/bash
# Scenario: 4-rollback-restore-watchdog  (STATBUS-031 — rollback()'s restore has a watchdog cover)
#
# Class:                 restore-db-stall-watchdog
# Class kind:            Stall
# Source:                STATBUS-031 / tmp/architect-047D-pid-liveness.md sibling sweep
#
# WHAT THIS PROVES (the 012-pattern RED→GREEN pair for the LAST recovery wedge):
#   rollback()'s restoreDatabase rsync restores the WHOLE DB volume — onAdvance=nil,
#   output to progress.File(), which bypasses the heartbeat. On the STARTUP recovery
#   path (recoverFromFlag → recoveryRollback → rollback → restoreDatabase) there is NO
#   other WATCHDOG=1 source. On a large DB (Norway 32 GB) the restore runs minutes;
#   without a heartbeat, systemd's active-phase WatchdogSec=120s SIGABRTs the unit
#   mid-restore. Because the flag is removed only AFTER the restore completes, the
#   next boot restores FROM SCRATCH and is killed again — an indefinite restore loop
#   on the recovery path itself (the rune-wedge shape).
#
#   STATBUS-031 wraps rollback()'s body in an always-ping watchdog ticker
#   (runGatedWatchdogTicker, nil progress) so a legitimately-slow restore keeps
#   feeding WATCHDOG=1 from a goroutine independent of the parked main goroutine.
#
#   GREEN (fixed, master): the stall holds restoreDatabase silent for
#   STALL_HOLD_S=180s (> WatchdogSec=120s); the always-ping ticker keeps the unit
#   alive; on release the restore completes; the rollback lands terminal; NRestarts
#   stays at baseline; data is restored intact; the flag is gone.
#   RED (unfixed — master MINUS the rollback() ticker block; see the RED-delta in
#   STATBUS-031): the 180s silent restore exceeds WatchdogSec → SIGABRT → NRestarts
#   climbs → the row never reaches terminal → this scenario FAILS. That failure IS
#   the RED observation.
#
# DETERMINISTIC ROLLBACK TRIGGER — why the resume-died-rollback dance, not 4-rollback-kill:
#   Post-STATBUS-039, recoverFromFlag prefers FORWARD recovery; it reaches rollback()
#   ONLY on a positively-behind verdict, which 4-rollback-kill documents as
#   non-deterministic (needs forward-recovery to fail; no injection class for that).
#   The Resuming latch IS deterministic: the instant resumePostSwap commits it stamps
#   Phase=Resuming; if that process then dies, the next recoverFromFlag sees Resuming
#   and ROLLS BACK (never re-resumes). So we drive a death-during-resume to land a
#   guaranteed rollback, then STALL that rollback's restoreDatabase.
#
# Trigger logic (three single-injection runs; inject gates on ONE STATBUS_INJECT_AT):
#   1. Install at INSTALL_VERSION. Populate. Snapshot data + baseline NRestarts.
#   2. Stage HEAD on the VM (so the resume + rollback run HEAD's code).
#   3. RUN 1 — install at HEAD with STATBUS_INJECT_AT=killed-by-system-during-container-restart.
#      The kill fires inside applyPostSwap; the process exits 137 with the flag pinned
#      PostSwap and the row in_progress — AND a finalized pre-upgrade snapshot recorded
#      on the flag (flag.BackupPath, stamped by updateFlagPostSwap), which is the
#      identity-keyed source restoreDatabase will later consume.
#   4. RUN 2 — drop-in with the SAME kill + a LONG RestartSec (so no auto-restart
#      races us). Start the unit: recoverFromFlag sees PostSwap → resumePostSwap stamps
#      Phase=Resuming → applyPostSwap → docker-up KILL (137). The flag is now Resuming;
#      the row still in_progress. Confirm Phase=Resuming, then the long RestartSec
#      leaves the unit idle (no rollback yet).
#   5. RUN 3 — SWAP the drop-in to the STALL env (STATBUS_INJECT_AT=restore-db-stall-watchdog
#      + STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<release file>, present) + a short
#      RestartSec; restart the unit. recoverFromFlag sees Phase=Resuming →
#      recoveryRollback → rollback() → restoreGitState → restoreBinary → config gen →
#      restoreDatabase → the stall site parks the restore SILENT.
#   6. HOLD STALL_HOLD_S=180s. GREEN: NRestarts stays at baseline (the always-ping
#      ticker keeps the unit alive across the silent restore). RED: NRestarts climbs.
#   7. Remove the release file → the rsync proceeds → rollback completes → the row
#      reaches a terminal state.
#   8. Assert (LOAD-BEARING, the GREEN contract): NRestarts delta = 0 (bounded),
#      row rolled_back (failed only if the restore itself failed — degraded), flag
#      absent, data restored intact, unit settles healthy.
#
# Hetzner-runnability:
#   NOTE FOR TESTER: this scenario has NOT yet been run on real systemd. Verify on a
#   Hetzner VM and tune the knobs (STALL_HOLD_S vs WatchdogSec, the RUN2 long
#   RestartSec window, SETTLE_WATCH_S, INSTALL_VERSION's migration delta). It reuses
#   resume-died-rollback's kill primitive + HEAD-staging fixture +
#   fabricate_scheduled_upgrade_row, and the new restore-db-stall-watchdog inject site
#   (no other new machinery). Run it on the GREEN build (master) — expect PASS — and
#   on the RED build (master minus the rollback() ticker block) — expect the t+STALL
#   watch to detect a climbing NRestarts / no-terminal-row = the RED observation.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/4-rollback-restore-watchdog.sh \
#     statbus-recovery-4-rollback-restore-watchdog

set -euo pipefail

VM_NAME="${1:-statbus-recovery-4-rollback-restore-watchdog}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# RUN 2 long RestartSec: after the Resuming-death the unit must NOT auto-restart
# (and roll back) before we swap to the stall drop-in. An hour is plenty; we drive
# the next start explicitly in RUN 3.
RUN2_RESTART_S="${RUN2_RESTART_S:-3600}"
# RUN 3 short RestartSec: prompt rollback restart once the stall drop-in is in place.
RUN3_RESTART_S="${RUN3_RESTART_S:-10}"
# Stall hold: MUST exceed WatchdogSec=120s to prove the cover. The RED build is
# SIGABRT'd around the 120s mark; the GREEN build sails through.
STALL_HOLD_S="${STALL_HOLD_S:-180}"
# Settle watch after the stall is released — see the rollback land + the unit settle.
SETTLE_WATCH_S="${SETTLE_WATCH_S:-180}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

# Must be @statbus (matches the VM user) so the unit's ExecStartPre invariant
# `/usr/bin/test "%i" = "%u"` passes (see resume-died-rollback's note).
UNIT="statbus-upgrade@statbus.service"
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="$DROPIN_DIR/rollback-restore-watchdog-inject.conf"
# Release file: while present, the stall holds inside restoreDatabase. Removing it
# releases the rsync. Lives under the VM's home so the unit (running as statbus) can
# stat it.
RELEASE_FILE="\$HOME/statbus/tmp/restore-db-stall-release"

trap '
    rc=$?
    VM_EXEC bash -c "
        systemctl --user stop '"$UNIT"' 2>/dev/null || true
        rm -f '"$DROPIN_FILE"' '"$RELEASE_FILE"' 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user start '"$UNIT"' 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 4-rollback-restore-watchdog  (STATBUS-031)"
echo "  (a startup-recovery rollback's restoreDatabase stalls 180s > WatchdogSec;"
echo "   the always-ping ticker must keep the unit alive — GREEN; RED = SIGABRT loop)"
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

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — stage HEAD on the VM (resume + rollback run HEAD's code)
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
# Phase 3 — RUN 1: install at HEAD, killed mid-applyPostSwap. Leaves the flag
# pinned PostSwap with a finalized snapshot recorded (flag.BackupPath) and the
# row in_progress — the resume precondition + the identity-keyed restore source.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 1: install at HEAD, killed mid-applyPostSwap (establishes PostSwap + recorded snapshot) ──"
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
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-postswap-kill.sh

# Seed a scheduled public.upgrade row at HEAD so install classifies as
# StateScheduledUpgrade → executeUpgrade → backupDatabase → applyPostSwap → kill.
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-postswap-kill.sh"
FIRST_EXIT=$?
set -e
echo "  RUN 1 exited: $FIRST_EXIT (137 = injected SIGKILL semantics)"
if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ RUN 1 timed out — kill site did not fire" >&2
    exit 1
fi

echo ""
echo "── verifying PostSwap precondition (flag present + row in_progress) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
# The flag must carry a recorded backup path — restoreDatabase is identity-keyed and
# will refuse (return nil, no rsync, no stall) if backup_path is empty.
if ! VM_EXEC bash -c "grep -q '\"backup_path\"[^,]*[^\"]' ~/statbus/tmp/upgrade-in-progress.json"; then
    echo "✗ flag has no backup_path — the kill fired BEFORE updateFlagPostSwap; restoreDatabase would no-op (no rsync to stall)." >&2
    echo "  (Tune: ensure RUN1's kill site is killed-by-system-during-container-restart, which is AFTER the post-swap snapshot commit.)" >&2
    exit 1
fi
echo "  ✓ PostSwap precondition: flag present (with backup_path), row in_progress"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — RUN 2: kill drop-in + LONG RestartSec. Start the unit: resume stamps
# Phase=Resuming, then the docker-up kill fires (137). The long RestartSec leaves
# the unit idle afterward so RUN 3 can swap to the stall before any rollback.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 2: kill drop-in (resume stamps Resuming, then dies at docker-up) ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true
_dropin2=$(mktemp /tmp/harness-dropin-kill-XXXXXX.sh)
cat > "$_dropin2" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_DIR/rollback-restore-watchdog-inject.conf" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=killed-by-system-during-container-restart
TimeoutStopSec=5s
RestartSec=${RUN2_RESTART_S}s
DROPIN_EOF
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin2"
scp -O "${SSH_OPTS[@]}" "$_dropin2" root@"$VM_IP":/tmp/harness-dropin-kill.sh
rm -f "$_dropin2"
VM_EXEC bash /tmp/harness-dropin-kill.sh
echo "── starting unit; resume reaches docker-up and is killed in the Resuming phase ──"
VM_EXEC bash -c "systemctl --user --no-block start $UNIT"

echo "── waiting for the Resuming-death (flag Phase=Resuming, unit idle in RestartSec backoff) ──"
RESUMING_TS=$(date +%s)
SAW_RESUMING=""
while [ $(( $(date +%s) - RESUMING_TS )) -lt 120 ]; do
    if VM_EXEC bash -c "grep -q '\"phase\"[^,]*[Rr]esuming' ~/statbus/tmp/upgrade-in-progress.json" 2>/dev/null; then
        SAW_RESUMING="yes"
        echo "  ✓ flag Phase=Resuming observed"
        break
    fi
    sleep 3
done
if [ -z "$SAW_RESUMING" ]; then
    echo "✗ flag never reached Phase=Resuming within 120s — the resume did not stamp/die as expected." >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null; systemctl --user status $UNIT --no-pager" >&2 || true
    exit 1
fi
assert_upgrade_row_state "$VM_NAME" "in_progress"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — RUN 3: swap to the STALL drop-in + create the release file, then
# restart. recoverFromFlag sees Resuming → recoveryRollback → rollback() →
# restoreDatabase → stall site parks the restore SILENT.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 3: swap to STALL drop-in; the rollback's restoreDatabase will park silent ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true
_dropin3=$(mktemp /tmp/harness-dropin-stall-XXXXXX.sh)
cat > "$_dropin3" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
mkdir -p "\$DROPIN_DIR"
mkdir -p "\$HOME/statbus/tmp"
# Create the release file FIRST so the stall holds the instant restoreDatabase is reached.
touch "$RELEASE_FILE"
cat > "\$DROPIN_DIR/rollback-restore-watchdog-inject.conf" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=restore-db-stall-watchdog
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
TimeoutStopSec=5s
RestartSec=${RUN3_RESTART_S}s
DROPIN_EOF
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin3"
scp -O "${SSH_OPTS[@]}" "$_dropin3" root@"$VM_IP":/tmp/harness-dropin-stall.sh
rm -f "$_dropin3"
VM_EXEC bash /tmp/harness-dropin-stall.sh
echo "── starting unit; rollback runs, restoreDatabase parks at the stall site ──"
VM_EXEC bash -c "systemctl --user --no-block start $UNIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — HOLD the stall > WatchdogSec and watch NRestarts. This is the
# LOAD-BEARING watchdog-cover proof: on the GREEN build the always-ping ticker
# keeps the unit alive across the silent restore (NRestarts flat). On the RED
# build (no ticker) systemd SIGABRTs around the 120s mark and NRestarts climbs.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the restore stall for ${STALL_HOLD_S}s (> WatchdogSec=120s); watching NRestarts ──"
HOLD_TS=$(date +%s)
while [ $(( $(date +%s) - HOLD_TS )) -lt "$STALL_HOLD_S" ]; do
    elapsed=$(( $(date +%s) - HOLD_TS ))
    NR=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ $((elapsed % 20)) -eq 0 ]; then
        echo "    [t+${elapsed}s] NRestarts=$NR (baseline=$NRESTARTS_BASELINE) — flat=GREEN, climbing=RED(watchdog kill)"
    fi
    # Fail fast on a climb: the RED observation. (On the GREEN build this never trips.)
    if [ "$NR" != "?" ] && [ "$NR" -gt "$((NRESTARTS_BASELINE + 1))" ]; then
        echo "✗ NRestarts climbed to $NR during the silent restore (baseline=$NRESTARTS_BASELINE)" >&2
        echo "  → WatchdogSec SIGABRT'd the unit mid-restore: the rollback restore has NO watchdog cover (RED / unfixed code)." >&2
        echo "  This is the EXPECTED outcome on the RED build (master minus the rollback() ticker block); a PASS requires the STATBUS-031 fix." >&2
        exit 1
    fi
    sleep 5
done
echo "  ✓ NRestarts stayed bounded through the ${STALL_HOLD_S}s silent restore — the always-ping ticker held the unit alive (GREEN)."

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — release the stall → the rsync proceeds → the rollback completes.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── releasing the stall (rm release file); watching for the rollback to land (up to ${SETTLE_WATCH_S}s) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
START_TS=$(date +%s)
FINAL_STATE=""
while [ $(( $(date +%s) - START_TS )) -lt "$SETTLE_WATCH_S" ]; do
    elapsed=$(( $(date +%s) - START_TS ))
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ $((elapsed % 20)) -eq 0 ]; then
        echo "    [t+${elapsed}s] row=$STATE"
    fi
    case "$STATE" in
        rolled_back|failed) FINAL_STATE="$STATE"; echo "  ✓ row reached terminal '$STATE' at t+${elapsed}s"; break ;;
        completed) echo "✗ row reached 'completed' — a rollback was expected, not a forward success." >&2; exit 1 ;;
    esac
    sleep 5
done
if [ -z "$FINAL_STATE" ]; then
    echo "✗ row did not reach a terminal state within ${SETTLE_WATCH_S}s after releasing the stall." >&2
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
    VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — assertions (LOAD-BEARING — the GREEN contract for STATBUS-031)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── GREEN-contract checks (LOAD-BEARING) ──"

# rolled_back is the healthy tier (snapshot restored). failed is acceptable only if
# the restore itself ALSO failed — flag it loudly but don't hard-fail (the cover
# still fired; the watchdog proof is NRestarts-bounded above).
if [ "$FINAL_STATE" = "failed" ]; then
    echo "  ⚠ terminal state 'failed' (degraded) — the rollback's restore ALSO failed; investigate restoreDatabase, but the watchdog cover still held (NRestarts stayed bounded)."
else
    assert_upgrade_row_state "$VM_NAME" "rolled_back"
fi

# The flag is gone — the mutex is released so ./sb install is not wedged.
assert_flag_file_absent "$VM_NAME"

# Data restored intact from the upgrade's own (identity-keyed) snapshot.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Remove the inject drop-in; confirm the unit settles bounded (NOT looping).
echo ""
echo "── removing inject drop-in; confirming the unit settles (no loop) ──"
VM_EXEC bash -c "rm -f $DROPIN_FILE; systemctl --user daemon-reload; systemctl --user --no-block restart $UNIT 2>/dev/null || true"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UNIT" "$((NRESTARTS_BASELINE + 3))"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 4-rollback-restore-watchdog"
echo "  (a startup-recovery rollback's restoreDatabase stalled ${STALL_HOLD_S}s > WatchdogSec;"
echo "   the STATBUS-031 always-ping ticker kept the unit alive — NRestarts bounded — the"
echo "   restore completed on release, the row rolled_back, the snapshot restored intact,"
echo "   and the flag was cleared. On the RED build this run fails at the t+${STALL_HOLD_S} watch.)"
