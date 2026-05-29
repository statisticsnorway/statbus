#!/bin/bash
# Scenario 27: archivebackup-resume-active-phase
#   (recovery-arc flaw — archiveBackup on the exit-42 resume; fixed by active-phase + FIX A)
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
# EXPECTED PRINCIPLED BEHAVIOR (post-fix, plan piece #2 + FIX A):
#   Plan piece #2 — READY=1 + LISTEN are moved BEFORE recoverFromFlag, so
#     the exit-42 resume now runs in the ACTIVE phase (post-READY=1), governed
#     by WatchdogSec (not TimeoutStartSec). The applyPostSwap WATCHDOG=1
#     ticker (a BLIND 30 s timer — it keeps the unit alive regardless of
#     whether progress is being made) covers the stalled tar; there are 0
#     kills expected. TimeoutStartSec is inert for the resume path (the resume
#     runs active-phase; TimeoutStartSec only governs the pre-READY=1 window).
#   FIX A — archiveBackup is reordered AFTER the terminal `state='completed'`
#     UPDATE + removeUpgradeFlag. The row is ALREADY completed and the flag
#     removed by the time the tar runs, so even if a kill occurred (systemd
#     jitter) it would be harmless: the next start finds no flag and no-ops.
#     The fast terminal UPDATE persists well inside the WatchdogSec budget;
#     the multi-minute tar that follows is non-critical-path (pruning already
#     runs post-completion).
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
#      held by the release file) AND a SHORT TimeoutStartSec (inert post-fix
#      since the resume is active-phase; keeps pre-fix RED cycles fast).
#      Restart the unit. Service.Run boots → READY=1 fires → recoverFromFlag →
#      resumePostSwap → applyPostSwap → reaches archiveBackup → stalls.
#   6. Hold the stall past the WatchdogSec window and observe:
#        RED (pre-fix): the row STAYS in_progress and NRestarts CLIMBS as
#          systemd SIGTERMs each start-phase tar before the terminal UPDATE,
#          WITHOUT tripping StartLimitBurst (the load-bearing slow-loop
#          signature — see the RED_EXPECT block below).
#        GREEN (post-fix, plan piece #2 + FIX A): the resume runs ACTIVE-phase
#          (READY=1 fired before recoverFromFlag); the WATCHDOG=1 ticker keeps
#          the unit alive across the stalled tar — 0 kills expected. The row
#          reaches 'completed' while the tar is still stalled (FIX A: the
#          terminal UPDATE ran BEFORE the tar). NRestarts stays bounded (0
#          expected; 1 = systemd jitter headroom).
#   7. Release the stall + remove the drop-in, assert convergence:
#      row='completed', flag absent, data intact, services healthy,
#      NRestarts bounded. PLUS ATOMIC (task #8): no orphan *-pre.tar.gz.tmp
#      and every final *-pre.tar.gz passes `gzip -t` (no partial at the final
#      name).
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
#     ./test/install-recovery/scenarios/27-archivebackup-resume-active-phase.sh \
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
# Must be @statbus (matches the VM user, vm-bootstrap.sh:286) so the unit's
# ExecStartPre invariant `/usr/bin/test "%i" = "%u"` (ops/statbus-upgrade.
# service:55, drift-guard commit dc6802df0) passes. Pre-fix: @test caused
# every systemctl start to fail status=1 → Restart=always loop →
# StartLimitBurst exhausted → the archiveBackup stall was never reached.
UNIT="statbus-upgrade@statbus.service"
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
echo "  Scenario 27: archivebackup-resume-active-phase"
echo "  (exit-42 RESUME runs active-phase; WATCHDOG=1 ticker keeps unit alive across archiveBackup)"
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

# Seed a scheduled public.upgrade row at HEAD so the install state detector
# classifies as StateScheduledUpgrade (and dispatches executeUpgrade → applyPostSwap
# → the kill site). Without this, RUN 1 sees nothing-scheduled (current==target:
# both derive from the running binary's ldflags version, which is HEAD after
# upload_sb_to_vm overwrote the v2026.05.2 binary) → idempotent step-table refresh
# → exits 0 → KillHere never fires. Pattern-A fix (harness regression run 26539222000).
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
# Short start budget: post-fix this is inert for the resume (the resume
# runs active-phase; TimeoutStartSec doesn't govern it). Pre-fix (EXPECT_RED)
# it makes each doomed start-phase cycle fast. Short stop grace so
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
# Phase 6 — hold the stall WHILE the archiveBackup is blocked, and watch the
# row. This is the heart of the FIX A test:
#
#   Plan piece #2 + FIX A: the resume runs ACTIVE-phase (READY=1 fired before
#   recoverFromFlag); the WATCHDOG=1 ticker (a blind 30 s timer) keeps the unit
#   alive across the stalled tar — 0 kills expected. FIX A moved the terminal
#   state='completed' UPDATE + removeUpgradeFlag to BEFORE archiveBackup, so
#   the row reaches 'completed' and the flag is removed BEFORE the stall is
#   even hit — i.e. DURING this hold, while the tar is blocked. That is the
#   load-bearing proof: the slow tar can no longer prevent the row from
#   completing. If a kill did occur (systemd jitter), it would be harmless:
#   the next start finds no flag and no-ops → the unit converges.
#
#   Pre-fix (no #2 / no FIX A): the UPDATE runs AFTER the tar and the resume
#   runs start-phase; each cycle is SIGTERM'd at TimeoutStartSec before the
#   UPDATE, so the row stays in_progress → loop. The row NEVER reaches
#   completed during the hold. (EXPECT_RED mode asserts exactly that.)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the resume archiveBackup stall (up to ${STALL_HOLD_S}s); watching the row ──"
echo "    (plan piece #2 + FIX A: row reaches 'completed' BEFORE the stalled tar — during this hold;"
echo "     pre-fix: row stays in_progress and the unit loop-restarts)"
START_TS=$(date +%s)
ROW_COMPLETED_DURING_HOLD=0
ROW_DURING=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$STALL_HOLD_S" ]; then break; fi
    NR=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
    SUB=$(VM_EXEC systemctl --user show "$UNIT" --property=SubState --value 2>/dev/null | tr -d ' \r\n' || echo "?")
    ROW_DURING=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ $((elapsed % 30)) -eq 0 ]; then
        echo "    [t+${elapsed}s] NRestarts=$NR substate=$SUB row=$ROW_DURING (baseline NRestarts=$NRESTARTS_BASELINE)"
    fi
    # FIX A signature: row completes while the tar is still stalled.
    if [ "$ROW_DURING" = "completed" ]; then
        ROW_COMPLETED_DURING_HOLD=1
        echo "  ✓ row reached 'completed' at t+${elapsed}s — WHILE archiveBackup is still stalled"
        echo "    (plan piece #2 + FIX A: terminal UPDATE persisted before the tar; active-phase ticker kept the unit alive)"
        break
    fi
    sleep 5
done

NRESTARTS_DURING=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA_DURING=$((NRESTARTS_DURING - NRESTARTS_BASELINE))
echo ""
echo "  during-hold: NRestarts=$NRESTARTS_DURING (delta=$RESTART_DELTA_DURING) row=$ROW_DURING completed_during_hold=$ROW_COMPLETED_DURING_HOLD"

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
# GREEN load-bearing assertion (post-fix, plan piece #2 + FIX A): the row
# MUST have reached 'completed' DURING the hold — i.e. before the stalled
# archiveBackup. This is the single decisive proof: the terminal UPDATE
# persisted ahead of the tar, so the tar can no longer keep the row
# in_progress regardless of kills. The resume runs active-phase (plan #2:
# READY=1 before recoverFromFlag) so the watchdog ticker keeps it alive;
# FIX A ensures the UPDATE already ran. If this fails, plan piece #2 + FIX A
# are not in effect — the row was still in_progress while the tar was blocked.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── GREEN load-bearing check: row completed before the stalled tar (plan #2 + FIX A) ──"
if [ "$ROW_COMPLETED_DURING_HOLD" != "1" ]; then
    echo "✗ row did NOT reach 'completed' during the hold (last seen: '$ROW_DURING')." >&2
    echo "  Plan piece #2 + FIX A not in effect: the tar still runs before the UPDATE" >&2
    echo "  and/or the resume is not active-phase, so a kill (or ctx cancel) keeps" >&2
    echo "  the row in_progress — the NO/rune wedge. See plan" >&2
    echo "  recovery-arc-flaw-timeoutstartsec.md §4a FIX A + plan piece #2." >&2
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
    VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ plan piece #2 + FIX A hold: the row was 'completed' while archiveBackup was still stalled"

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — release the stall + drop-in so the tar finishes and the unit
# settles; then confirm convergence + cleanup. The row is ALREADY 'completed'
# (asserted above); this phase just lets archiveBackup finish and the unit
# reach a steady active state, then runs the final cleanup assertions.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── releasing stall + removing drop-in; letting the tar finish + unit settle ──"
VM_EXEC bash -c "
    rm -f $RELEASE_FILE
    rm -f $DROPIN_FILE
    systemctl --user daemon-reload
    systemctl --user --no-block restart $UNIT 2>/dev/null || true
"

# The row is already 'completed' (asserted during the hold); this just
# confirms it stays terminal once the tar finishes and the unit settles.
START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$CONVERGE_BUDGET_S" ]; then
        echo "✗ row not in a terminal state ${CONVERGE_BUDGET_S}s after release (unexpected —" >&2
        echo "  it was 'completed' during the hold; a regression to in_progress would mean" >&2
        echo "  something re-opened the row). Investigate." >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
        VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade settled at state='$STATE' (t+${elapsed}s after release)"
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

# Convergence bound: the resume runs ACTIVE-phase (plan piece #2: READY=1 +
# LISTEN before recoverFromFlag); the applyExtendCtx ticker is already pinging
# WATCHDOG=1 every 30 s before the stalled tar begins, so the unit stays alive
# — 0 kills, period. FIX A ensures the row is 'completed' and the flag is gone
# before the tar runs, so even a stray kill would no-ops on the next start. Any
# NRestarts increment means the resume is not active-phase or the ticker is not
# covering the stall — plan piece #2 + FIX A not in effect. The decisive proof
# is the ROW_COMPLETED_DURING_HOLD check above; this bound catches any residual
# kill.
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
FINAL_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$FINAL_DELTA"
if [ "$FINAL_DELTA" -gt 0 ]; then
    echo "✗ NRestarts grew by $FINAL_DELTA — the resume was killed (expected 0 kills)." >&2
    echo "  The resume must run active-phase with the applyExtendCtx ticker already" >&2
    echo "  pinging WATCHDOG=1 every 30 s before the stalled tar. A kill means plan" >&2
    echo "  piece #2 (READY=1 before recoverFromFlag) or the ticker coverage is not" >&2
    echo "  in effect." >&2
    exit 1
fi

# ATOMIC (task #8) archive integrity: after convergence, the backups dir must
# contain NO partial/orphan archive. Two checks:
#   (1) no `*-pre.tar.gz.tmp` orphan — pruneArchives reaps stale .tmp from any
#       killed tar, so a leftover here means the sweep regressed.
#   (2) every final `*-pre.tar.gz` passes `gzip -t` — a complete archive. A
#       partial at the final name (the PRE-ATOMIC bug: tar -czf wrote directly
#       to the final name and was killed/failed mid-write) would FAIL gzip -t.
# This proves the atomic rename publishes only complete archives. (The
# mid-tar-WRITE kill itself is exercised by the Go guard
# TestArchiveBackup_FailedTarLeavesNoFinal; this scenario check confirms the
# end-state on a real box across the resume.)
echo ""
echo "── ATOMIC archive integrity (task #8) ──"
# The resume's archiveBackup runs its tar AFTER the stall release (above); give
# it a bounded window to finalize (tar → .tmp → atomic rename → final) before we
# assert. Without this the check could race a still-running tar and read a
# transient .tmp or a not-yet-present final. Tiny on demo data; generous ceiling.
echo "  waiting (≤${ARCHIVE_SETTLE_S:-90}s) for archiveBackup tar to finalize..."
_settle_deadline=$(( $(date +%s) + ${ARCHIVE_SETTLE_S:-90} ))
while :; do
    _state=$(VM_EXEC bash -c 'echo "$(ls ~/statbus-backups/*-pre.tar.gz 2>/dev/null | wc -l) $(ls ~/statbus-backups/*-pre.tar.gz.tmp 2>/dev/null | wc -l)"' 2>/dev/null | tr -d '\r' || echo "0 0")
    _nfin=${_state%% *}; _ntmp=${_state##* }
    if [ "${_nfin:-0}" -ge 1 ] && [ "${_ntmp:-0}" -eq 0 ]; then
        echo "  ✓ tar finalized ($_nfin archive(s), no .tmp in flight)"; break
    fi
    if [ "$(date +%s)" -ge "$_settle_deadline" ]; then
        echo "  ⚠ settle window elapsed (final=$_nfin tmp=$_ntmp); asserting on current state" >&2; break
    fi
    sleep 3
done
# Integrity verdict. CRITICAL: ship the check as a script FILE (VM_EXEC_SCRIPT),
# NEVER inline `VM_EXEC bash -c '<multiline>'` — the inline form is silently
# corrupted by the sudo -i arg-join and exits non-zero WITHOUT running, which the
# old `|| echo "FAILED"` swallow then mislabeled as "a PARTIAL was published."
# Honest, distinct exit codes: 0 clean / 1 partial-at-final (paths on stdout) /
# 3 no archive produced / 4 orphan .tmp / other (e.g. 255) the check COULD NOT
# RUN on the VM (infra/SSH) — which must NEVER read as a production violation.
ARCHIVE_CHECK_OUT=$(VM_EXEC_SCRIPT <<'ARCHIVE_CHECK_EOF'
shopt -s nullglob
tmps=(~/statbus-backups/*-pre.tar.gz.tmp)
if [ "${#tmps[@]}" -ne 0 ]; then printf 'ORPHAN %s\n' "${tmps[@]}"; exit 4; fi
archives=(~/statbus-backups/*-pre.tar.gz)
if [ "${#archives[@]}" -eq 0 ]; then echo "NO_ARCHIVE"; exit 3; fi
rc=0
for f in "${archives[@]}"; do
    if ! gzip -t "$f" 2>/dev/null; then printf 'BAD %s\n' "$f"; rc=1; fi
done
exit $rc
ARCHIVE_CHECK_EOF
)
ARCHIVE_CHECK_RC=$?
case "$ARCHIVE_CHECK_RC" in
    0) echo "  ✓ archive(s) present, no .tmp orphan, all gzip -t clean" ;;
    1) echo "✗ a final *-pre.tar.gz failed gzip -t — a PARTIAL was published at the final name" >&2
       echo "    (the pre-ATOMIC bug: tar must write .tmp then rename-on-success):" >&2
       printf '    %s\n' "$ARCHIVE_CHECK_OUT" >&2; exit 1 ;;
    3) echo "✗ the resume's archiveBackup produced NO *-pre.tar.gz (tar never finalized)" >&2
       VM_EXEC bash -c 'ls -la ~/statbus-backups/ 2>/dev/null' >&2 || true; exit 1 ;;
    4) echo "✗ orphan *-pre.tar.gz.tmp present — pruneArchives must reap stale .tmp:" >&2
       printf '    %s\n' "$ARCHIVE_CHECK_OUT" >&2; exit 1 ;;
    *) echo "✗ harness: archive-integrity check could not run on the VM (rc=$ARCHIVE_CHECK_RC)" >&2
       echo "    INFRASTRUCTURE/exec failure (SSH/delivery) — NOT a production atomicity violation." >&2
       [ -n "$ARCHIVE_CHECK_OUT" ] && printf '    output: %s\n' "$ARCHIVE_CHECK_OUT" >&2
       exit 1 ;;
esac

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: archivebackup-resume-active-phase"
echo "  (exit-42 resume runs active-phase; applyExtendCtx ticker pings WATCHDOG=1 every"
echo "   30 s before the stalled tar — 0 kills, period; FIX A ensures the row reaches"
echo "   'completed' before the tar runs; archive written atomically — no partial at the"
echo "   final name. The NO/rune 40 h wedge is fixed.)"
