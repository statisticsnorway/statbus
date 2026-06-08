#!/bin/bash
# Scenario: 3-postswap-archivebackup-resume
#   (recovery-arc flaw — archiveBackup on the exit-42 resume; fixed by active-phase + FIX A)
#
# Class:                 archive-backup-exceeds-systemd-budget-on-resume
# Class kind:            Stall (on the resume path)
# Source forensics:      doc/recovery/recovery-arc-flaw-timeoutstartsec.md
#                        (the NO/rune 40 h wedge; upgrade id=187)
#
# WHAT THIS CATCHES (the gap between scenarios 18 and 26):
#   - `3-postswap-archivebackup-watchdog` stalls archiveBackup in the ACTIVE phase (post-READY=1),
#     reached via the SCHEDULED dispatch from the main loop. The WATCHDOG=1
#     ticker keeps the unit alive there — so 26 passed while the production
#     RESUME path was unprotected.
#   - `1-boot-startup-timeout` stalls a GENERIC startup step pre-READY=1 under
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
#      scenario 3-postswap-container-restart-kill phase 3).
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
#          terminal UPDATE ran BEFORE the tar). NRestarts stays bounded.
#      NOTE (VERIFIED — runs 27107825797 + 27109134019): this kill path actually
#      leaves Phase=Resuming, so the resume ROLLS BACK then reconciles to
#      'completed' (rollback-then-recomplete); NRestarts=1 is EXPECTED (not
#      jitter), and archiveBackup is never reached. The NRestarts assertion below
#      is bounded accordingly. Full analysis + the open "redesign to actually
#      reach archiveBackup?" question: tmp/architect-archivebackup-resume-diagnosis.md.
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
#   READY. Reuses the scenario 3-postswap-container-restart-kill kill primitive + the scenario 3-postswap-archivebackup-watchdog stall
#   primitive + the scenario 3-postswap-archivebackup-watchdog HEAD-staging fixture; no new inject sites.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-archivebackup-resume.sh \
#     statbus-recovery-3-postswap-archivebackup-resume

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-archivebackup-resume}"
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

# Diagnostic dump (rec 1, architect 2026-06-08): on any UNEXPECTED NRestarts
# increment the active-phase unit was killed+restarted by systemd — capture WHY.
# run 27107825797 saw a silent 0→1 with NO kill reason logged (the failure path
# dumped nothing, the VM is ephemeral, the t+30 sample was skipped). The decisive
# field is the journal kill record (Watchdog timeout vs "start operation timed
# out" vs OOM vs SIGABRT) + Result/ExecMainStatus. Dumps to stdout so it lands in
# the CI stage-log. Read-only.
dump_unit_diagnostics() {
    local _ctx="${1:-diagnostics}"
    echo ""
    echo "──────── UNIT DIAGNOSTICS (${_ctx}) ────────"
    echo "  [systemctl --user show — kill-reason fields]"
    VM_EXEC systemctl --user show "$UNIT" \
        --property=NRestarts,Result,ActiveState,SubState,ExecMainStatus,ExecMainCode,StatusErrno,ActiveEnterTimestamp,InactiveEnterTimestamp 2>/dev/null || true
    echo "  [systemctl --user status]"
    VM_EXEC systemctl --user status "$UNIT" --no-pager -n 40 2>/dev/null || true
    echo "  [journalctl --user -u $UNIT — last 200 lines: kill records + service stdout]"
    VM_EXEC journalctl --user -u "$UNIT" --no-pager -n 200 2>/dev/null || true
    echo "──────── END UNIT DIAGNOSTICS (${_ctx}) ────────"
    echo ""
}

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-archivebackup-resume"
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
    "$LIB_DIR/../fixtures/stage-head.sh" \
    root@"$VM_IP":/tmp/stage-head.sh
VM_EXEC bash /tmp/stage-head.sh "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — RUN 1: drive an exit-42 resume state via a mid-applyPostSwap kill
# (same primitive as scenario 3-postswap-container-restart-kill; the install process exits 137, leaving the
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
    # Echo EVERY 5 s sample (rec 1, architect): the prior `elapsed % 30 == 0`
    # gate silently SKIPPED when elapsed jumped 0→6→…→43 (ssh latency + sleep 5
    # never landing on an exact multiple of 30), so run 27107825797 logged ONLY
    # t+0 — no substate/NRestarts progression to localize the 0→1 transition.
    echo "    [t+${elapsed}s] NRestarts=$NR substate=$SUB row=$ROW_DURING (baseline NRestarts=$NRESTARTS_BASELINE)"
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

# rec 1 (architect): if the unit restarted during the hold, dump the kill reason
# IMMEDIATELY (freshest capture, ~t+45 s) — this is the active-phase kill whose
# cause run 27107825797 never recorded. Diagnostic only; does NOT change control
# flow (the strict 0-kills assertion is still evaluated at the final check below).
if [ "$RESTART_DELTA_DURING" -gt 0 ]; then
    dump_unit_diagnostics "during-hold NRestarts delta=$RESTART_DELTA_DURING (active-phase kill — pin the cause)"
fi

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

# NRestarts bound (rec 2, architect — VERIFIED behavior, runs 27107825797 +
# 27109134019). The strict "0 kills" assertion was WRONG: it assumed an
# active-phase resume reaching the tar with no death. What ACTUALLY happens — the
# RUN-1 kill leaves Phase=Resuming, so recoverFromFlag rolls back to the snapshot
# (one-shot latch, service.go:755) + exit-75, systemd auto-restarts ONCE, and the
# row reconciles to 'completed' (rollback-then-recomplete; archiveBackup is never
# reached). So NRestarts=1 is the EXPECTED, correct outcome — NOT a kill to fail
# on. What this STILL catches (the real wedge): NRestarts CLIMBING toward
# StartLimitBurst=5 — a genuine restart LOOP (the NO/rune non-convergence
# signature) — OR a wrong final state (row not 'completed' / data not intact, both
# asserted above). See tmp/architect-archivebackup-resume-diagnosis.md (UPDATE 3/4).
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
FINAL_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$FINAL_DELTA"
# 1 = the expected rollback→recomplete restart; 2 = jitter headroom; >=3 = a real
# loop (well under StartLimitBurst=5, at which systemd marks the unit failed).
RESTART_LOOP_BOUND=3
if [ "$FINAL_DELTA" -ge "$RESTART_LOOP_BOUND" ]; then
    echo "✗ NRestarts grew by $FINAL_DELTA (>= $RESTART_LOOP_BOUND) — a restart LOOP, not the single" >&2
    echo "  rollback→recomplete cycle: the unit is failing to converge (the NO/rune wedge" >&2
    echo "  signature — restarts climbing toward StartLimitBurst=5). The final-state checks" >&2
    echo "  above (row='completed', data intact) must also hold." >&2
    dump_unit_diagnostics "NRestarts LOOP: delta=$FINAL_DELTA >= $RESTART_LOOP_BOUND"
    exit 1
fi
echo "  ✓ NRestarts delta=$FINAL_DELTA within bound (1 = the expected rollback→recomplete restart; <$RESTART_LOOP_BOUND)"

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
TMP_ORPHANS=$(VM_EXEC bash -c 'ls ~/statbus-backups/*-pre.tar.gz.tmp 2>/dev/null | wc -l' 2>/dev/null | tr -d ' \r\n' || echo "0")
if [ "$TMP_ORPHANS" != "0" ]; then
    echo "✗ found $TMP_ORPHANS orphan *-pre.tar.gz.tmp archive(s) — pruneArchives must reap stale .tmp:" >&2
    VM_EXEC bash -c 'ls -la ~/statbus-backups/*-pre.tar.gz.tmp' >&2 || true
    exit 1
fi
echo "  ✓ no orphan .tmp archives"
# gzip -t every final archive; any failure = a partial published at the final
# name = ATOMIC not in effect.
BAD_ARCHIVE=$(VM_EXEC bash -c '
    rc=0
    for f in ~/statbus-backups/*-pre.tar.gz; do
        [ -e "$f" ] || continue
        if ! gzip -t "$f" 2>/dev/null; then echo "$f"; rc=1; fi
    done
    exit $rc
' 2>/dev/null || echo "FAILED")
if [ -n "$BAD_ARCHIVE" ]; then
    echo "✗ a final *-pre.tar.gz failed gzip -t — a PARTIAL was published at the final name" >&2
    echo "  (the pre-ATOMIC bug). ATOMIC requires tar→.tmp then rename-on-success. Bad: $BAD_ARCHIVE" >&2
    exit 1
fi
echo "  ✓ all final *-pre.tar.gz archives are complete (gzip -t clean)"

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 3-postswap-archivebackup-resume"
echo "  (post-swap kill → Phase=Resuming → rollback (one-shot latch) + exit-75 → systemd"
echo "   restarts ONCE → row reconciles to 'completed': the upgrade CONVERGES, NRestarts"
echo "   bounded (1 expected, <3), data intact, backups atomic. The NO/rune non-convergence"
echo "   wedge is fixed. NB: archiveBackup is not reached on this kill path — see the header.)"
