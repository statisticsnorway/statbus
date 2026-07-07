#!/bin/bash
# Arc: rollback-pair-terminal  (STATBUS-134 — the 2-consecutive-rollback-deaths
# restore-broke terminal). Sibling / direct extension of rollback-kill-arc.sh:
# same deterministic PreSwap-wedge entry, ONE MORE builtin-rollback kill added
# before the clean dispatch, so the (rollback, rollback) step pair forms on
# disk and rollbackResumeIsTerminal (recovery_escalation.go:163) fires BEFORE
# any third restore attempt.
#
# WHY THIS ROUTE, NOT A BOOT-MIGRATE/GROUND-TRUTH ("V_fail") ENTRY (architect
# ruling, 2026-07-06 — verified against shipped code before building this file):
# recordRollbackCommit (service.go:552, the ONLY call site is :2599 inside
# recoveryRollback) is what stamps flag.Step←"rollback" / rolls
# PriorDeathStep←the prior step. A live in-process forward failure
# (executeUpgrade/resumePostSwap → postSwapFailure → service.go:~6530
# d.rollback() DIRECTLY) never goes through recoveryRollback and so never
# stamps Step="rollback" at all — killing THAT path would need 4 kills
# interleaved with forward machinery to ever reach the stamped pair, and even
# then non-deterministically. The PreSwap route is the one place
# recoverFromFlag calls d.recoveryRollback() UNCONDITIONALLY, no ground-truth
# check, no forward attempt (service.go's FlagPhasePreSwap branch — see
# rollback-kill-arc.sh's own header for the DETERMINISTIC proof) — so it is
# the clean, deterministic way to reach the STAMPED rollback regime twice.
#
# CHOREOGRAPHY (verified against service.go / recovery_escalation.go):
#   1st dispatch (C5 killed-by-system-during-binary-swap):
#     exit 137 -> PreSwap wedge (flag.Phase=PreSwap, Step/PriorDeathStep empty).
#   2nd dispatch (C9 killed-by-system-during-builtin-rollback, ARMED marker #1):
#     recoverFromFlag PreSwap branch -> recoveryRollback:
#       - RecoveryBudgetGuard no-ops (PreSwap flag: !IsServiceForwardRecovery()
#         -> service.go:5692-5696 "a PreSwap flag that rolls back" is an
#         explicitly named no-op case).
#       - countRecoveryAttemptOnce -> attempts=1.
#       - rollbackResumeIsTerminal(Step="", Prior="") = false (Step != "rollback").
#       - recordRollbackCommit: PriorDeathStep <- "" (old Step), Step <- "rollback".
#       - d.rollback() runs the destructive steps -> hits the C9 KillHere site
#         (service.go:~6744) -> marker #1 consumed -> exit 137.
#     => DEATH 1. On-disk: Step="rollback", PriorDeathStep="" (NOT yet "rollback").
#   3rd dispatch (C9 again, ARMED marker #2 — RE-ARMED, doc-017/STATBUS-022 style):
#     RecoveryBudgetGuard still no-ops (still a PreSwap-rooted flag — Phase
#     never changed; PreSwap never becomes a forward flag). recoverFromFlag
#     PreSwap branch -> recoveryRollback again:
#       - attempts=2.
#       - rollbackResumeIsTerminal(Step="rollback", Prior="") = false (Prior != rollback
#         yet — "the first rollback resume is free BY CONSTRUCTION", service.go:2595).
#       - recordRollbackCommit: PriorDeathStep <- "rollback" (old Step), Step <- "rollback".
#       - d.rollback() runs again -> hits C9 -> marker #2 consumed -> exit 137.
#     => DEATH 2. On-disk: Step="rollback", PriorDeathStep="rollback" — the PAIR.
#   4th dispatch (clean, no inject):
#     recoveryRollback: attempts=3. rollbackResumeIsTerminal(Step="rollback",
#     Prior="rollback") = TRUE -> fires the restore-broke terminal DIRECTLY
#     (service.go:2575-2591) -- BEFORE any d.rollback() call, so there is no
#     third restore attempt and the C9 site is never reached this dispatch.
#     writeRollbackTerminal (state='failed') succeeds: the recovery boot's own
#     ordinary EnsureDBUp (service.go:1789, install_upgrade.go's own DB-up
#     preflight) already brought the DB up before this guard runs — this path
#     does NOT go through rollback()'s git-corrupt ABORT branch and so does
#     NOT depend on STATBUS-136's DB-start-before-write fix (that fix lives
#     exclusively in the OTHER rollback failure mode — see the sibling arc
#     rollback-abort-write-lands-arc.sh). On success: removeUpgradeFlag(),
#     runCallback(STATBUS_ROLLBACK_FAILED=1), returns normally (no exit) —
#     the box concludes alive-idle, not crash-looping.
#
# Exactly 2 kills total (the designed restore-broke contract: TWO consecutive
# mid-rollback deaths, never budget-exhaustion, never a third restore
# attempt). NOTE (STATBUS-137, open): the callback fires WITHOUT a
# STATBUS_EVENT key (only STATBUS_ROLLBACK_FAILED / STATBUS_ROLLBACK_ERROR /
# STATBUS_RECOVERY_CMD) — this arc asserts what the shipped code emits today
# and does not assert a STATBUS_EVENT value that does not exist yet.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-rollback-pair-terminal}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: rollback-pair-terminal  (STATBUS-134 — 2 consecutive rollback deaths -> restore-broke 'failed')"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

row_state()      { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_attempts()   { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT recovery_attempts FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
flag_present()   { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# read_flag_field <field> — grep/sed the on-disk flag JSON (no dependency on
# the live daemon — every dispatch here is a synchronous ./sb install
# invocation, so a point-in-time read after each dispatch suffices; no polling
# loop needed, unlike a persistent-service scenario watching a live process).
read_flag_field() {
    local field="$1"
    VM_EXEC bash -c "cd ~/statbus && grep -o '\"${field}\":\"[^\"]*\"' tmp/upgrade-in-progress.json 2>/dev/null | head -1 | sed -E 's/.*:\"([^\"]*)\"/\\1/'" 2>/dev/null | tr -d ' \r\n' || echo ""
}

# ── A: install + prepare; register B ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ─────────────────────────────────────────────────────────────────────────
# UPGRADE_CALLBACK — configured via .env.config BEFORE any dispatch (STATBUS-131
# AC#3 style: survives every ./sb config generate). Script transferred as a
# FILE (not an inline VM_EXEC arg with a raw $STATBUS_ROLLBACK_FAILED
# reference) — sudo -i strips bare $-expansions in transit except literal
# dollar signs (the same trap documented at length in
# 3-postswap-resume-died-parked.sh); a file with the $ references INSIDE it,
# evaluated by the shell that finally execs it on the VM, sidesteps the whole
# problem. STATBUS-137 is open (no STATBUS_EVENT on this path) — log
# STATBUS_ROLLBACK_FAILED, the key this path DOES emit.
# ─────────────────────────────────────────────────────────────────────────
CALLBACK_LOG='/tmp/rollback-pair-terminal-callback-log.txt'
echo ""
echo "── writing the rollback-pair-terminal callback script (transferred as a FILE) ──"
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/bash
echo "\${STATBUS_ROLLBACK_FAILED:-} \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/rollback-pair-terminal-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
VM_EXEC bash -c \
    'mv /tmp/rollback-pair-terminal-callback.sh /home/statbus/rollback-pair-terminal-callback.sh && chown statbus:statbus /home/statbus/rollback-pair-terminal-callback.sh && chmod 0755 /home/statbus/rollback-pair-terminal-callback.sh'
echo "  ✓ /home/statbus/rollback-pair-terminal-callback.sh installed (chmod 0755)"

VM_EXEC bash -c "rm -f $CALLBACK_LOG"
# Glue-proof append (STATBUS-140): guarantee .env.config ends with a newline
# before appending, exactly like the operator-documented flow must, so the
# key lands on its own line rather than gluing onto the last existing one.
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/rollback-pair-terminal-callback.sh\n" >> .env.config'
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env.config" || { echo "✗ UPGRADE_CALLBACK injection did not land in .env.config" >&2; exit 1; }

arc_schedule_daemon_down "$B_FULL"

# ─────────────────────────────────────────────────────────────────────────
# 1st dispatch — C5 binary-swap kill -> PreSwap wedge (identical to
# rollback-kill-arc.sh; see that file's header for the determinism proof).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 1st dispatch: C5 binary-swap kill (PreSwap wedge) ──"
arc_install_dispatch_with_inject "killed-by-system-during-binary-swap"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 1st dispatch exited $ARC_DISPATCH_RC (expected 137) — the C5 kill did not fire; no wedge" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after the C5 kill" >&2; exit 1; }
echo "[OBSERVE] C5 wedge: exit 137, flag present (Phase=PreSwap)"

# ─────────────────────────────────────────────────────────────────────────
# 2nd dispatch — C9 builtin-rollback kill, ARMED (marker #1) -> DEATH 1.
# recoveryRollback stamps Step="rollback" (recordRollbackCommit) BEFORE
# calling d.rollback(), so the kill lands with the stamp already on disk.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 2nd dispatch: recovery + C9 builtin-rollback kill, ARMED marker #1 (death 1) ──"
MARKER_1="/tmp/rollback-pair-terminal-kill-1-$$"
VM_EXEC bash -c "touch $MARKER_1"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback" "$INSTALL_BUDGET_S" "$MARKER_1"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 2nd dispatch exited $ARC_DISPATCH_RC (expected 137) — C9 death #1 did not fire" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after C9 death #1 (partial-rollback wedge)" >&2; exit 1; }
VM_EXEC bash -c "test -e $MARKER_1" && { echo "✗ kill marker #1 was NOT consumed — C9 site was not reached (or fired without consuming the marker)" >&2; exit 1; }
STEP_AFTER_D1=$(read_flag_field "step")
PRIOR_AFTER_D1=$(read_flag_field "prior_death_step")
echo "[OBSERVE] DEATH 1: exit 137, marker #1 consumed, flag.step=\"$STEP_AFTER_D1\" flag.prior_death_step=\"$PRIOR_AFTER_D1\""
[ "$STEP_AFTER_D1" = "rollback" ] || { echo "✗ expected flag.step=\"rollback\" after death 1 (recordRollbackCommit stamp), got \"$STEP_AFTER_D1\"" >&2; exit 1; }
[ "$PRIOR_AFTER_D1" != "rollback" ] || { echo "✗ flag.prior_death_step is already \"rollback\" after only ONE death — the pair would form one death too early (arithmetic drift)" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────
# 3rd dispatch — C9 again, RE-ARMED (marker #2) -> DEATH 2. This is the
# extension past rollback-kill-arc.sh: that arc's 3rd dispatch was clean
# (completing to rolled_back). Here it is ALSO killed, so PriorDeathStep
# rolls to "rollback" too -> the pair forms.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 3rd dispatch: recovery + C9 builtin-rollback kill, RE-ARMED marker #2 (death 2) ──"
MARKER_2="/tmp/rollback-pair-terminal-kill-2-$$"
VM_EXEC bash -c "touch $MARKER_2"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback" "$INSTALL_BUDGET_S" "$MARKER_2"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 3rd dispatch exited $ARC_DISPATCH_RC (expected 137) — C9 death #2 did not fire" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after C9 death #2 (partial-rollback wedge)" >&2; exit 1; }
VM_EXEC bash -c "test -e $MARKER_2" && { echo "✗ kill marker #2 was NOT consumed — C9 site was not reached on the re-armed dispatch" >&2; exit 1; }
STEP_AFTER_D2=$(read_flag_field "step")
PRIOR_AFTER_D2=$(read_flag_field "prior_death_step")
echo "[OBSERVE] DEATH 2: exit 137, marker #2 consumed, flag.step=\"$STEP_AFTER_D2\" flag.prior_death_step=\"$PRIOR_AFTER_D2\""
[ "$STEP_AFTER_D2" = "rollback" ] && [ "$PRIOR_AFTER_D2" = "rollback" ] || { echo "✗ expected the (rollback, rollback) pair after death 2, got step=\"$STEP_AFTER_D2\" prior=\"$PRIOR_AFTER_D2\"" >&2; exit 1; }
echo "  ✓ the (rollback, rollback) pair is on disk — the NEXT dispatch must fire restore-broke BEFORE any restore attempt"

# ─────────────────────────────────────────────────────────────────────────
# 4th dispatch — clean (no inject). rollbackResumeIsTerminal fires directly;
# no third restore attempt; the C9 site is never reached this dispatch.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 4th dispatch: ./sb install (no inject) → restore-broke terminal fires directly ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "[OBSERVE] 4th dispatch exit: $REC_RC"

echo ""
echo "── convergence checks (restore-broke: exactly 2 rollback deaths, human stop) ──"
FINAL_STATE=$(row_state)
FINAL_ATTEMPTS=$(row_attempts)
echo "[OBSERVE] final row: state=$FINAL_STATE attempts=$FINAL_ATTEMPTS"
[ "$FINAL_STATE" != "rolled_back" ] || { echo "✗ state='rolled_back' — two consecutive mid-rollback deaths must terminal to 'failed' (restore-broke human stop), never a silent successful rollback" >&2; exit 1; }
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — impossible on this route (never a forward attempt); a regression somewhere upstream" >&2; exit 1; }
[ "$FINAL_STATE" = "failed" ] || { echo "✗ expected terminal 'failed' (restore-broke), got '$FINAL_STATE'" >&2; exit 1; }
echo "  ✓ state='failed' (restore-broke human stop)"
[ "$FINAL_ATTEMPTS" = "3" ] || { echo "✗ recovery_attempts=$FINAL_ATTEMPTS — expected exactly 3 (2 killed rollback passes + the terminal pass that fires without another restore), got $FINAL_ATTEMPTS" >&2; exit 1; }
echo "  ✓ recovery_attempts=3 (2 rollback deaths + the terminal pass)"

# The message names BOTH the mechanism ("two consecutive crash-deaths during
# rollback") and the ONLY legal source (ErrRollbackDBRestore) — see
# recovery_escalation.go rollbackResumeIsTerminal + service.go:2575-2591.
assert_upgrade_row_error_matches "$VM_NAME" "two consecutive crash-deaths during rollback"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
# NOTE: intentionally NOT asserting counts-match-snapshot here — no restore
# ever ran (the pair-terminal fires BEFORE any third restore attempt), so the
# DB is whatever state the FIRST killed restoreDatabase pass left it in
# (identity-keyed, PreSwap backupPath is empty -> restoreDatabase refuses to
# touch the volume in every pass here — data present is the right bar, an
# exact snapshot match is not a claim this route makes).
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

# ── callback: exactly ONE STATBUS_ROLLBACK_FAILED=1 line (fired once, at the
# terminal — the two killed passes never reach runCallback; only the 4th,
# terminal-writing dispatch calls it). STATBUS-137 (open): no STATBUS_EVENT
# key exists on this path — assert on what ships today, not a future key.
CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ callback line does not carry STATBUS_ROLLBACK_FAILED=1" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_ROLLBACK_FAILED=1 callback fired (STATBUS-137's STATBUS_EVENT gap noted, not asserted)"

echo ""
echo "PASS: rollback-pair-terminal (2 consecutive mid-rollback deaths formed the (rollback,rollback) step pair; the 3rd recovery pass fired the restore-broke 'failed' terminal BEFORE any further restore attempt; flag removed; unit alive-idle; callback fired once; data intact)"
