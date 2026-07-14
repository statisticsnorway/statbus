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

# _dump_rollback_pair_terminal_failure_diagnostics — STATBUS-155 rider
# (mirrors postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics):
# on ANY non-zero exit, pull B's own upgrade progress log + the daemon journal
# + its row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_rollback_pair_terminal_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + daemon journal + row state) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_rollback_pair_terminal_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: rollback-pair-terminal  (STATBUS-134 — 2 consecutive rollback deaths -> restore-broke 'failed')"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

row_state()      { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_present()   { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# read_flag_field <field> — grep/sed the on-disk flag JSON (no dependency on
# the live daemon — every dispatch here is a synchronous ./sb install
# invocation, so a point-in-time read after each dispatch suffices; no polling
# loop needed, unlike a persistent-service scenario watching a live process).
read_flag_field() {
    local field="$1"
    # Space-tolerant (architect autopsy, run 28838952364): the flag is
    # product-written via json.MarshalIndent, which renders `"step": "rollback"`
    # WITH a space after the colon — the old compact-only `"step":"..."` grep
    # matched nothing, silently reading both fields empty. Lifted from the
    # park proof's proven reader (postswap-health-park-arc.sh; the read_flag_field
    # pattern originated in the retired 3-postswap-resume-died-parked): grep matches the KEY only (no value-shape assumption;
    # "step" vs "prior_death_step" don't collide — the char before "step" in
    # "prior_death_step" is '_', not '"'), sed's `: *"` tolerates 0+ spaces.
    VM_EXEC bash -c "cd ~/statbus && grep '\"${field}\":' tmp/upgrade-in-progress.json 2>/dev/null | sed -E 's/.*\"${field}\": *\"([^\"]*)\".*/\\1/'" 2>/dev/null | tr -d ' \r\n' || echo ""
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
# dollar signs (the same trap documented at length in the retired
# 3-postswap-resume-died-parked, pattern preserved in postswap-health-park-arc.sh);
# a file with the $ references INSIDE it,
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
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
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
#
# POST-STATBUS-111 UPDATE: this dispatch no longer STOPS at the pair-terminal
# write. `runInstall` re-runs `install.Detect()` after crash-recovery settles
# (dispatchInstallState fires on both the initial Detect and the post-
# recovery re-Detect, same process, same `./sb install` invocation) — and
# since STATBUS-111 shipped (after this arc was authored), a row that is now
# `state='failed' AND backup_path IS NOT NULL` (true here: the DB COLUMN
# backup_path is set during the very first dispatch's backup step, before the
# C5 kill — a PreSwap-route fact independent of flag.BackupPath, which IS
# empty on this route) hits StateRestoreReattemptable and gets IMMEDIATELY
# re-attempted, in this SAME dispatch. Empirically confirmed by the identical
# mechanism in test/install-recovery/arcs/restore-broke-reattempt-arc.sh
# (arc run 29325230294: 'failed' then 'rolled_back' ~23s apart, one VM_EXEC
# call). THE STATBUS-134 PAIR-BOUND ORACLE ITSELF IS UNCHANGED: 2 killed
# rollback passes + the terminal pass that fires WITHOUT a third restore
# attempt (recovery_attempts=3 at that moment, verified via the dispatch
# log's JSON row dump before it's overwritten) still holds — what changed is
# only what happens AFTER that terminal, automatically, later in the same
# process.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 4th dispatch: ./sb install (no inject) → pair-terminal fires, THEN the SAME dispatch re-attempts it (STATBUS-111) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > ${ARC_DISPATCH_LOG} 2>&1" || REC_RC=$?
VM_EXEC bash -c "cat ${ARC_DISPATCH_LOG} 2>/dev/null" || true
echo "[OBSERVE] 4th dispatch exit: $REC_RC"
[ "$REC_RC" = "0" ] || { echo "✗ 4th dispatch (pair-terminal + re-attempt, one clean pass, no crash) exited $REC_RC, expected 0" >&2; exit 1; }

echo ""
echo "── convergence checks (2 rollback deaths -> pair-terminal -> immediate STATBUS-111 re-attempt -> 'rolled_back') ──"
# The pair-terminal's own moment: verified via the dispatch log (the stdlib
# `log` summary line names both the mechanism and the exact attempts count —
# service.go recoveryRollback/rollbackResumeIsTerminal), NOT a DB re-read
# after the fact — by the time this dispatch returns, the row's error column
# has already been overwritten by the re-attempt's own success message.
[ "$(arc_dispatch_log_has "RESTORE-BROKE upgrade")" = "yes" ] || { echo "✗ dispatch output does not show the pair-terminal's own log line — did rollbackResumeIsTerminal actually fire?" >&2; exit 1; }
[ "$(arc_dispatch_log_has "after 3 attempt(s)")" = "yes" ] || { echo "✗ dispatch output does not confirm recovery_attempts=3 at the pair-terminal moment (2 killed rollback passes + the terminal pass, no third restore attempt)" >&2; exit 1; }
echo "  ✓ pair-terminal fired with recovery_attempts=3 (2 rollback deaths + the terminal pass, no third restore attempt) — the STATBUS-134 oracle itself, unchanged"

[ "$(arc_dispatch_log_has "Re-attempting the restore from the retained snapshot")" = "yes" ] || { echo "✗ dispatch output does not show the STATBUS-111 re-attempt legend — did it really re-detect StateRestoreReattemptable in the same pass?" >&2; exit 1; }
echo "  ✓ dispatch log shows the STATBUS-111 re-attempt legend — the same clean pass continued past the pair-terminal"

FINAL_STATE=$(row_state)
echo "[OBSERVE] final row: state=$FINAL_STATE"
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — impossible on this route (never a forward attempt); a regression somewhere upstream" >&2; exit 1; }
[ "$FINAL_STATE" = "rolled_back" ] || { echo "✗ expected terminal 'rolled_back' (pair-terminal immediately re-attempted, STATBUS-111), got '$FINAL_STATE'" >&2; exit 1; }
echo "  ✓ state='rolled_back' — the pair-terminal's own re-attempt completed the restore for real"

assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
# A REAL restore now runs (the re-attempt), unlike before STATBUS-111 landed
# — the exact-count claim is now true and asserted (it was deliberately NOT
# claimed pre-111, since no restore ever ran on this route back then).
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

# ── callback: TWO lines now, not one — the pair-terminal's own
# STATBUS_ROLLBACK_FAILED=1 (rollbackResumeIsTerminal's write), THEN the
# re-attempt's own success callback (STATBUS_EVENT=rolled_back, no
# STATBUS_ROLLBACK_FAILED key — restoreAndFinalize's success branch), both
# firing in this one dispatch since STATBUS-111. STATBUS-137 (open): no
# STATBUS_EVENT key on the FIRST callback — assert on what ships today.
CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "2" ] || { echo "✗ expected exactly 2 callback lines (pair-terminal + re-attempt success), got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "head -1 $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ first callback line does not carry STATBUS_ROLLBACK_FAILED=1 (the pair-terminal's own callback)" >&2; exit 1; }
echo "  ✓ exactly 2 callback lines: the pair-terminal's STATBUS_ROLLBACK_FAILED=1, then the re-attempt's own success callback (STATBUS-137's STATBUS_EVENT gap noted, not asserted)"

echo ""
echo "PASS: rollback-pair-terminal (2 consecutive mid-rollback deaths formed the (rollback,rollback) step pair; the 3rd recovery pass fired the restore-broke terminal with recovery_attempts=3 BEFORE any further restore attempt — the STATBUS-134 oracle; the SAME dispatch then immediately re-attempted it per STATBUS-111, completing to a healthy 'rolled_back' with data intact)"
