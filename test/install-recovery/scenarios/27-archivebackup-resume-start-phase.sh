#!/bin/bash
# Scenario 27: archivebackup-resume-start-phase
#   (recovery-arc flaw — archiveBackup blows TimeoutStartSec on the exit-42 resume)
#
# Class:                 archive-backup-exceeds-systemd-budget-on-resume
# Class kind:            Stall (on the resume path)
# Source forensics:      /Users/jhf/.claude-veridit/plans/recovery-arc-flaw-timeoutstartsec.md
#                        (the NO/rune 40 h wedge; upgrade id=187)
#
# WHAT THIS CATCHES (the gap between scenarios 18 and 26):
#   - Scenario 26 stalls archiveBackup in the ACTIVE phase (post-READY=1),
#     reached via the SCHEDULED dispatch from the main loop. The WATCHDOG=1
#     ticker keeps the unit alive there — so 26 passed while the production
#     RESUME path was unprotected.
#   - Scenario 18 stalls a GENERIC startup step pre-READY=1 under
#     TimeoutStartSec — right phase, but a trivial injected site, never
#     archiveBackup and never a resume.
#   - Neither drove a real exit-42 RESUME whose archiveBackup exceeds the
#     start-phase budget. That is exactly the combination that wedged NO:
#     recoverFromFlag → resumePostSwap → applyPostSwap → archiveBackup all
#     run BEFORE sdNotify("READY=1") (start phase, TimeoutStartSec), so a
#     32 GB tar is SIGTERM'd before the terminal `state='completed'` UPDATE
#     persists → row stays in_progress → Restart=always re-enters the
#     identical doomed resume → infinite loop, NRestarts climbing at a
#     cadence too slow to trip StartLimitBurst.
#
# EXPECTED PRINCIPLED BEHAVIOR (post-fix, plan §4a):
#   FIX B1 — READY=1 is emitted after the cheap init (EnsureDBUp →
#     boot-migrate-up → connect → advisory lock + LISTEN) but BEFORE
#     recoverFromFlag, so the whole resume runs in the ACTIVE phase under
#     WatchdogSec, where the existing 30 s WATCHDOG=1 ticker keeps the unit
#     alive across the tar — no kill at all.
#   FIX A — archiveBackup is reordered AFTER the terminal `state='completed'`
#     UPDATE + removeUpgradeFlag, so even if the tar is killed, the row is
#     already completed and the flag removed: the next start finds no flag
#     and no-ops. The upgrade converges regardless of which timer fires.
#
# Trigger logic (two single-injection process runs — the inject framework
# gates on ONE STATBUS_INJECT_AT at a time, so we kill in run 1 and stall on
# the resume in run 2):
#   1. Install at INSTALL_VERSION. Populate. Snapshot data + baseline NRestarts.
#   2. Stage HEAD on the VM (git checkout + image pre-tag) so the resume runs
#      HEAD's code (the fix when it lands; the unfixed code on a pre-fix SHA).
#   3. RUN 1 — drive an exit-42 resume state: run `./sb install` at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-container-restart. KillHere
#      fires inside applyPostSwap (between step 11 and step 12); the process
#      exits 137 with the flag pinned PostSwap and the row in_progress. This
#      is the canonical "interrupted post-swap, will resume" state (same as
#      scenario 15 phase 3).
#   4. Verify the resume precondition: flag present + row in_progress.
#   5. RUN 2 — install a systemd drop-in pinning the resume's archiveBackup
#      stall (STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog,
#      held by the release file) AND a SHORT TimeoutStartSec so each doomed
#      cycle is fast. Restart the unit. Service.Run boots → recoverFromFlag →
#      resumePostSwap → applyPostSwap → reaches archiveBackup → stalls.
#   6. Hold the stall past several TimeoutStartSec windows and observe:
#        RED (pre-fix): the row STAYS in_progress and NRestarts CLIMBS as
#          systemd SIGTERMs each start-phase tar before the terminal UPDATE,
#          WITHOUT tripping StartLimitBurst (the load-bearing slow-loop
#          signature — see the RED_EXPECT block below).
#        GREEN (post-fix): the row reaches 'completed' (FIX A: UPDATE ran
#          before the tar; or FIX B1: tar ran active-phase under the ticker
#          and finished) and the flag is removed; NRestarts stays bounded.
#   7. Release the stall + remove the drop-in, assert convergence:
#      row='completed', flag absent, data intact, services healthy,
#      NRestarts bounded.
#
# RED vs GREEN — how the tester reads the result:
#   Default (post-fix): GREEN-asserting — the row converges to 'completed',
#     the flag is removed, NRestarts stays bounded. Run against this branch's
#     HEAD (with the §4a fix) → PASSES.
#   EXPECT_RED=1 (pre-fix demonstration): run against a SHA at/before
#     17a6c796c (the branch base) → the scenario ASSERTS the wedge signature
#     during the hold (row stuck in_progress + NRestarts climbing under
#     StartLimitBurst) and PASSES on observing it, then stops. This makes the
#     RED→GREEN transition explicit: `EXPECT_RED=1 ...27... <vm>` on the
#     pre-fix binary PASSES (wedge reproduced), the default `...27... <vm>` on
#     the fixed binary PASSES (converges). Running the DEFAULT against a
#     pre-fix binary FAILS at the Phase 7 convergence checks — also a valid
#     reproduction, just without the explicit RED assertion.
#
# Hetzner-runnability:
#   READY. Reuses the scenario-15 kill primitive + the scenario-26 stall
#   primitive + the scenario-26 HEAD-staging fixture; no new inject sites.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/27-archivebackup-resume-start-phase.sh \
#     statbus-recovery-27

set -euo pipefail

VM_NAME="${1:-statbus-recovery-27}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# Short start budget so each doomed RED cycle is fast. The resume's
# archiveBackup stall is held longer than this, so a pre-fix binary is
# SIGTERM'd each cycle. 45 s start + 10 s RestartSec ≈ 55 s/cycle.
INJECT_TIMEOUT_START_S="${INJECT_TIMEOUT_START_S:-45}"
INJECT_RESTART_S="${INJECT_RESTART_S:-10}"
# Hold long enough to observe ≥2 doomed cycles on a pre-fix binary
# (~110 s of cycling) while staying WELL under StartLimitBurst=10 — this
# is the miniature of NO's slow-loop-under-burst signature.
STALL_HOLD_S="${STALL_HOLD_S:-150}"
# After release, the post-fix tar finishes + the upgrade completes.
CONVERGE_BUDGET_S="${CONVERGE_BUDGET_S:-300}"
# EXPECT_RED=1 flips the scenario to assert the PRE-fix wedge signature
# instead of post-fix convergence — for running against a binary at/before
# the branch base (17a6c796c) to demonstrate the RED→GREEN transition. In
# RED mode the scenario PASSES when it OBSERVES the wedge (row stuck
# in_progress + NRestarts climbing under StartLimitBurst during the hold)
# and exits before the release/convergence phase. Default (unset) = assert
# the post-fix GREEN behavior.
EXPECT_RED="${EXPECT_RED:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

# The standalone/cloud upgrade unit instance used by the harness VMs.
UNIT="statbus-upgrade@test.service"
RELEASE_FILE="/tmp/stall-release-archivebackup-resume"
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="$DROPIN_DIR/archivebackup-resume-inject.conf"

trap '
    rc=$?
    VM_EXEC bash -c "
        systemctl --user stop '"$UNIT"' 2>/dev/null || true
        rm -f '"$RELEASE_FILE"' 2>/dev/null || true
        rm -f '"$DROPIN_FILE"' 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user start '"$UNIT"' 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 27: archivebackup-resume-start-phase"
echo "  (archiveBackup blows TimeoutStartSec on the exit-42 RESUME — the NO wedge)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Inject TimeoutStartSec=${INJECT_TIMEOUT_START_S}s, hold=${STALL_HOLD_S}s"
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
# Phase 2 — stage HEAD on the VM (so the resume runs HEAD's code)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")
upload_sb_to_vm "$VM_NAME"
scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/scenario_26_stage_head.sh" \
    root@"$VM_IP":/tmp/scenario_27_stage_head.sh
VM_EXEC bash /tmp/scenario_27_stage_head.sh "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — RUN 1: drive an exit-42 resume state via a mid-applyPostSwap kill
# (same primitive as scenario 15; the install process exits 137, leaving the
#  flag pinned PostSwap and the row in_progress — the resume precondition).
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
# Phase 5 — RUN 2: stall the resume's archiveBackup under a SHORT
# TimeoutStartSec. Install the drop-in BEFORE starting the unit so there is
# no race. The unit is currently running (post-RUN-1 the systemd unit is
# still up); stop it first so the drop-in takes effect cleanly.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 2: installing archivebackup-resume stall drop-in (TimeoutStartSec=${INJECT_TIMEOUT_START_S}s) ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true

_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="\$DROPIN_DIR/archivebackup-resume-inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
# Short start budget so each pre-fix doomed cycle is fast (the resume's
# archiveBackup runs pre-READY=1 on a pre-fix binary). Short stop grace so
# SIGTERM→SIGKILL stays inside the test budget.
TimeoutStartSec=${INJECT_TIMEOUT_START_S}s
TimeoutStopSec=5s
RestartSec=${INJECT_RESTART_S}s
DROPIN_EOF
touch $RELEASE_FILE
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin_script"
scp -O "${SSH_OPTS[@]}" "$_dropin_script" root@"$VM_IP":/tmp/harness-install-dropin.sh
rm -f "$_dropin_script"
VM_EXEC bash /tmp/harness-install-dropin.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-install-dropin.sh" 2>/dev/null || true

echo "  ✓ drop-in installed + release file touched (stall will hold)"

# Start the unit. On boot it hits recoverFromFlag → resumePostSwap →
# applyPostSwap → archiveBackup → stalls. --no-block: on a pre-fix binary the
# start TIMES OUT (returns non-zero), which we must not let abort the script.
echo "── starting unit; resume will reach archiveBackup and stall ──"
VM_EXEC bash -c "systemctl --user --no-block start $UNIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — hold the stall; sample NRestarts + row state across the window.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the resume archiveBackup stall for ${STALL_HOLD_S}s ──"
echo "    (pre-fix: NRestarts climbs as each start-phase tar is SIGTERM'd;"
echo "     post-fix: tar is active-phase under the ticker — no kill)"
START_TS=$(date +%s)
LAST_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$STALL_HOLD_S" ]; then break; fi
    if [ $((elapsed % 30)) -eq 0 ]; then
        NR=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
        SUB=$(VM_EXEC systemctl --user show "$UNIT" --property=SubState --value 2>/dev/null | tr -d ' \r\n' || echo "?")
        ST=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        echo "    [t+${elapsed}s] NRestarts=$NR substate=$SUB row=$ST (baseline NRestarts=$NRESTARTS_BASELINE)"
        LAST_STATE="$ST"
    fi
    sleep 5
done

NRESTARTS_DURING=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
ROW_DURING=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA_DURING=$((NRESTARTS_DURING - NRESTARTS_BASELINE))
echo ""
echo "  during-hold: NRestarts=$NRESTARTS_DURING (delta=$RESTART_DELTA_DURING) row=$ROW_DURING"

# ─────────────────────────────────────────────────────────────────────────
# RED-mode assertion (EXPECT_RED=1 — running against a PRE-fix binary).
#   The pre-fix signature: while the stall is held, the resume's archiveBackup
#   runs pre-READY=1 (start phase); each cycle is SIGTERM'd at TimeoutStartSec
#   BEFORE the terminal UPDATE, so the row stays in_progress and NRestarts
#   climbs — WITHOUT tripping StartLimitBurst=10 (the slow-loop blind spot
#   that left NO `activating` for 40 h). We assert exactly that here, then
#   stop (don't run the convergence phase — a pre-fix binary never converges).
# Default (post-fix, EXPECT_RED unset): fall through to the Phase 7
#   convergence assertions below; the row reaches completed.
# ─────────────────────────────────────────────────────────────────────────
if [ -n "$EXPECT_RED" ]; then
    echo ""
    echo "── RED-mode assertions (EXPECT_RED=1 — expecting the pre-fix wedge) ──"
    rc=0
    if [ "$ROW_DURING" != "in_progress" ]; then
        echo "✗ RED expected row='in_progress' during the hold, got '$ROW_DURING'." >&2
        echo "  The resume's archiveBackup did not wedge the row — is this actually a pre-fix binary?" >&2
        rc=1
    else
        echo "  ✓ row stuck in_progress during the hold (terminal UPDATE never persisted)"
    fi
    if [ "$RESTART_DELTA_DURING" -lt 1 ]; then
        echo "✗ RED expected NRestarts to climb during the hold (delta≥1), got delta=$RESTART_DELTA_DURING." >&2
        echo "  The start-phase tar was not SIGTERM'd — is TimeoutStartSec=${INJECT_TIMEOUT_START_S}s in effect, or did READY=1 already fire (fixed binary)?" >&2
        rc=1
    else
        echo "  ✓ NRestarts climbed (delta=$RESTART_DELTA_DURING) — the unit is loop-restarting in the start phase"
    fi
    # Confirm the slow loop has NOT tripped StartLimitBurst (the blind spot):
    # delta well under 10 means systemd is still retrying, not `failed`.
    if [ "$RESTART_DELTA_DURING" -ge 10 ]; then
        echo "  (note: delta=$RESTART_DELTA_DURING reached StartLimitBurst — the loop tripped the cap this run;" >&2
        echo "   the NO signature is delta<10 staying under the cap, but a fast inject budget can exceed it)" >&2
    else
        echo "  ✓ NRestarts ($RESTART_DELTA_DURING) under StartLimitBurst=10 — the slow-loop blind spot reproduced"
    fi
    if [ "$rc" -eq 0 ]; then
        echo ""
        echo "PASS (RED mode): the pre-fix wedge reproduced — resume archiveBackup blew TimeoutStartSec,"
        echo "  row stuck in_progress, NRestarts climbing under StartLimitBurst (the NO/rune 40 h wedge)."
    fi
    # Release the stall so the trap's cleanup isn't fighting a held inject.
    VM_EXEC bash -c "rm -f $RELEASE_FILE $DROPIN_FILE; systemctl --user daemon-reload" 2>/dev/null || true
    exit $rc
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — release the stall + drop-in; assert convergence (POST-fix).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── releasing stall + removing drop-in; expecting convergence ──"
VM_EXEC bash -c "
    rm -f $RELEASE_FILE
    rm -f $DROPIN_FILE
    systemctl --user daemon-reload
    systemctl --user --no-block restart $UNIT 2>/dev/null || true
"

START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$CONVERGE_BUDGET_S" ]; then
        echo "✗ upgrade did not converge to a terminal state within ${CONVERGE_BUDGET_S}s after release" >&2
        echo "  This is the NO-wedge reproduction on a pre-fix binary: the resume's" >&2
        echo "  archiveBackup ran pre-READY=1 (start phase), was SIGTERM'd before the" >&2
        echo "  terminal UPDATE persisted, and the row stayed in_progress. Apply plan" >&2
        echo "  recovery-arc-flaw-timeoutstartsec.md §4a (READY=1 before recoverFromFlag" >&2
        echo "  + archiveBackup after the terminal UPDATE)." >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
        VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
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
# Phase 8 — assertions (LOAD-BEARING — these define the §4a fix contract)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks (LOAD-BEARING) ──"

# The load-bearing assertion from plan §5: the row reaches 'completed'. On a
# pre-fix binary it never does (stuck in_progress) — that is the bug.
if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ upgrade row reached '$FINAL_STATE', expected 'completed'." >&2
    echo "  The resume's terminal UPDATE must persist. Pre-fix, the start-phase" >&2
    echo "  archiveBackup kill cancelled the DB context before the UPDATE landed." >&2
    exit 1
fi
assert_upgrade_row_state "$VM_NAME" "completed"

# FIX A's signature: the flag is gone (so a stray post-completion kill no-ops).
assert_flag_file_absent "$VM_NAME"

# Data survived the interrupted-then-resumed upgrade (R5 cross-check).
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Slow-loop bound: even across the doomed RED cycles + recovery, NRestarts
# stays well under StartLimitBurst. Post-fix this is small (FIX B1 means no
# start-phase kill at all). We allow generous headroom for the RED→release
# transition since the scenario deliberately induced a short-budget loop.
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
FINAL_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$FINAL_DELTA"
if [ "$FINAL_DELTA" -gt 8 ]; then
    echo "✗ NRestarts grew by $FINAL_DELTA (>8) — the resume is still loop-restarting." >&2
    echo "  FIX B1 (READY=1 before recoverFromFlag) is not in effect: the resume is" >&2
    echo "  still running in the start phase under TimeoutStartSec." >&2
    exit 1
fi

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: archivebackup-resume-start-phase"
echo "  (the exit-42 resume's archiveBackup no longer wedges the unit in the start"
echo "   phase; the row converges to 'completed' and NRestarts stays bounded —"
echo "   the NO/rune wedge is fixed)"
