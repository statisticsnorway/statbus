#!/bin/bash
# Arc: restore-broke-reattempt  (STATBUS-071 coverage-map row 96; the arc-proof
# obligation carried over from STATBUS-111 AC#1/#5 — "the operator RE-ATTEMPTS
# a broken restore".)
#
# WHAT THIS PROVES — `./sb install` re-attempts a restore-broke row (STATBUS-111)
# instead of dead-ending at the idempotent step-table, and it does so SAFELY on
# BOTH row shapes the product's own probe (QueryReattemptableRestore: state=
# 'failed' AND backup_path IS NOT NULL) can match. DUAL-CLASS oracle, both
# REQUIRED (map row 96):
#
#   (i)  PAIR-TERMINAL class — a restore-broke row reached via TWO consecutive
#        mid-rollback crash-deaths (STATBUS-134's own construction, reused
#        verbatim from rollback-pair-terminal-arc.sh: the PreSwap route with a
#        C5 kill then two re-armed C9 kills). Git + binary are ALREADY at the
#        old era when the pair-terminal fires (the C9 kill site is AFTER
#        restoreGitState/restoreBinary/restoreDatabase have already run, per
#        restoreAndFinalize's own header). THE RE-ATTEMPT HAPPENS IN THE SAME
#        DISPATCH AS THE CONSTRUCTION (empirically confirmed, arc run
#        29325230294): `runInstall` re-runs `install.Detect()` after
#        crash-recovery settles, so the 4th (clean) dispatch's ONE `./sb
#        install` call first fires the pair-terminal write via
#        rollbackResumeIsTerminal, THEN immediately re-detects
#        StateRestoreReattemptable on the row it just wrote and replays the
#        idempotent restore tail to completion — watchdog armed, git-state
#        guard first (no-op — already correct), db stop, shared
#        restoreAndFinalize — landing at the honest 'rolled_back' terminal,
#        byte-identical to the pre-upgrade state. (This is STATBUS-111's own
#        behavior, shipped after rollback-pair-terminal-arc.sh was written —
#        there is no dispatch-boundary left between "constructed" and
#        "re-attempted" to assert on separately.)
#
#   (ii) ABORT class with STILL-CORRUPT git — a restore-broke row reached via
#        rollback()'s git-restore ABORT branch (STATBUS-136), constructed for
#        REAL (not fabricated, unlike the interim scenario
#        4-rollback-abort-write-lands): register+schedule a real commit C,
#        kill it POST-SWAP before its migration runs (C6 —
#        killed-by-system-during-individual-migration-execution, which fires
#        BEFORE the migrate subprocess so ground truth reads Behind
#        deterministically regardless of whether C's own migration would have
#        applied cleanly), then CORRUPT THE RESTORE INPUT for real: delete the
#        `pre-upgrade` git branch executeUpgrade pinned earlier in the SAME
#        dispatch (STATBUS-077 — the single source restoreGitState falls back
#        to) via a real `git branch -D` on the VM — genuine environment
#        manipulation of real machinery state, not a fabricated row. The next
#        clean dispatch's recovery finds ground truth Behind, rolls back,
#        restoreGitState fails for real (no resolvable target) → the ABORT
#        branch fires: state='failed' + ROLLBACK_FAILED_GIT_CORRUPT, backup_path
#        retained, DB brought back up so the terminal WRITE LANDS in one pass
#        (STATBUS-136; folds scenario 4-rollback-abort-write-lands' own oracle:
#        the abort terminal lands state+error together, flag removed, zero
#        loop). THE RE-ATTEMPT (a further clean `./sb install`) must REFUSE
#        actionably (ErrRollbackGitCorrupt) BEFORE any destructive step — the
#        git-state guard runs FIRST in ReattemptRestore precisely so an abort
#        row never gets its binary+DB restored to the old era while the git
#        tree stays wrecked (never a mixed-era box). The row is untouched by
#        the refusal: still 'failed', same backup_path, tree still corrupt.
#
# Deliberately ONE arc, ONE VM, two sequential phases: phase (i) uses commit
# B (the FAILING lineage's V_fail — content is irrelevant to the PreSwap route,
# which never reaches the migration); phase (ii) uses commit C (the SAME
# lineage's fix — likewise irrelevant here, since the C6 kill fires before its
# migration runs either way). commit_sha carries a UNIQUE constraint
# (upsertCandidate's ON CONFLICT), so phase (ii) cannot re-register B after
# phase (i) leaves it 'rolled_back' — a distinct commit is required, and the
# failing lineage already provides one (C) for free.
#
# Inputs (env): BASE_SHA, B_FULL, C_FULL (40-hex), B_BRANCH, C_BRANCH,
#   V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-restore-broke-reattempt}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${C_FULL:?C_FULL required}"
: "${C_BRANCH:?C_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

# _dump_restore_broke_reattempt_failure_diagnostics — STATBUS-155 rider (mirrors
# rollback-pair-terminal-arc.sh / postswap-rollback-restore-watchdog-arc.sh): on
# ANY non-zero exit, pull the latest (B or C) upgrade progress log + the daemon
# journal + row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true).
_dump_restore_broke_reattempt_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (latest progress log + daemon journal + row state) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha IN ('${B_FULL:-}', '${C_FULL:-}') ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── latest (B or C) upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B/C's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B=${B_FULL:-?}, C=${C_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, backup_path IS NOT NULL AS has_backup_path, error FROM public.upgrade WHERE commit_sha IN ('${B_FULL:-}', '${C_FULL:-}') ORDER BY id;\" | ./sb psql" >&2 || true
    echo "── pre-upgrade git branch on the VM ──" >&2
    VM_EXEC bash -c "cd ~/statbus && git rev-parse --verify pre-upgrade^{commit} 2>&1" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_restore_broke_reattempt_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: restore-broke-reattempt  (STATBUS-111 AC#1/#5 — dual-class ./sb install re-attempt)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

row_state_for()  { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_id_for()     { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_attempts_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT recovery_attempts FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_has_backup_path_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT backup_path IS NOT NULL FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_error_for()  { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo ""; }
flag_present()   { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
pre_upgrade_branch_present() { VM_EXEC bash -c "cd ~/statbus && git rev-parse --verify pre-upgrade^{commit} >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# read_flag_field <field> — space-tolerant on-disk flag JSON reader (lifted
# verbatim from rollback-pair-terminal-arc.sh: json.MarshalIndent renders
# `"field": "value"` WITH a space after the colon; sed tolerates 0+ spaces).
read_flag_field() {
    local field="$1"
    VM_EXEC bash -c "cd ~/statbus && grep '\"${field}\":' tmp/upgrade-in-progress.json 2>/dev/null | sed -E 's/.*\"${field}\": *\"([^\"]*)\".*/\\1/'" 2>/dev/null | tr -d ' \r\n' || echo ""
}

# ── A: install + prepare; register B (daemon up) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
echo "── capturing baseline clean-slate fingerprint (post-A) — phase (i)'s re-attempt restore must reach THIS byte-for-byte ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"
BASELINE_MAX_VERSION=$(migration_max_version)
echo "  baseline db.migration max version: $BASELINE_MAX_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# UPGRADE_CALLBACK — same safe file-transfer + glue-proof-append pattern as
# rollback-pair-terminal-arc.sh. Both restore-broke terminals fire the same
# env-var shape (STATBUS_ROLLBACK_FAILED / _ERROR / _RECOVERY_CMD); no
# STATBUS_EVENT (STATBUS-137, open; noted not asserted). The log is cleared
# between phases so each phase's callback count is independently checkable.
# ─────────────────────────────────────────────────────────────────────────
CALLBACK_LOG='/tmp/restore-broke-reattempt-callback-log.txt'
echo ""
echo "── writing the restore-broke-reattempt callback script (transferred as a FILE) ──"
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/bash
echo "\${STATBUS_ROLLBACK_FAILED:-} \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/restore-broke-reattempt-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    'mv /tmp/restore-broke-reattempt-callback.sh /home/statbus/restore-broke-reattempt-callback.sh && chown statbus:statbus /home/statbus/restore-broke-reattempt-callback.sh && chmod 0755 /home/statbus/restore-broke-reattempt-callback.sh'
echo "  ✓ /home/statbus/restore-broke-reattempt-callback.sh installed (chmod 0755)"

VM_EXEC bash -c "rm -f $CALLBACK_LOG"
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/restore-broke-reattempt-callback.sh\n" >> .env.config'
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env.config" || { echo "✗ UPGRADE_CALLBACK injection did not land in .env.config" >&2; exit 1; }

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# ═══════════════════════════════════════════════════════════════════════
# PHASE (i) — PAIR-TERMINAL class: 2 consecutive mid-rollback crash-deaths
# (STATBUS-134, construction reused verbatim from rollback-pair-terminal-arc.sh)
# then a clean RE-ATTEMPT that must complete the restore for real.
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "═══ PHASE (i): pair-terminal restore-broke row + clean re-attempt ═══"

echo ""
echo "── 1st dispatch: C5 binary-swap kill (PreSwap wedge) ──"
arc_install_dispatch_with_inject "killed-by-system-during-binary-swap"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 1st dispatch exited $ARC_DISPATCH_RC (expected 137) — the C5 kill did not fire; no wedge" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after the C5 kill" >&2; exit 1; }
echo "[OBSERVE] C5 wedge: exit 137, flag present (Phase=PreSwap)"

echo ""
echo "── 2nd dispatch: recovery + C9 builtin-rollback kill, ARMED marker #1 (death 1) ──"
MARKER_1="/tmp/restore-broke-reattempt-kill-1-$$"
VM_EXEC bash -c "touch $MARKER_1"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback" "$INSTALL_BUDGET_S" "$MARKER_1"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 2nd dispatch exited $ARC_DISPATCH_RC (expected 137) — C9 death #1 did not fire" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after C9 death #1 (partial-rollback wedge)" >&2; exit 1; }
VM_EXEC bash -c "test -e $MARKER_1" && { echo "✗ kill marker #1 was NOT consumed — C9 site was not reached" >&2; exit 1; }
STEP_AFTER_D1=$(read_flag_field "step")
PRIOR_AFTER_D1=$(read_flag_field "prior_death_step")
echo "[OBSERVE] DEATH 1: exit 137, marker #1 consumed, flag.step=\"$STEP_AFTER_D1\" flag.prior_death_step=\"$PRIOR_AFTER_D1\""
[ "$STEP_AFTER_D1" = "rollback" ] || { echo "✗ expected flag.step=\"rollback\" after death 1, got \"$STEP_AFTER_D1\"" >&2; exit 1; }
[ "$PRIOR_AFTER_D1" != "rollback" ] || { echo "✗ flag.prior_death_step already \"rollback\" after ONE death — arithmetic drift" >&2; exit 1; }

echo ""
echo "── 3rd dispatch: recovery + C9 builtin-rollback kill, RE-ARMED marker #2 (death 2) ──"
MARKER_2="/tmp/restore-broke-reattempt-kill-2-$$"
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
# 4th dispatch — STATBUS-111 (shipped AFTER rollback-pair-terminal-arc.sh was
# written) changed what a clean `./sb install` does here. `runInstall`
# re-runs `install.Detect()` after crash-recovery settles (dispatchInstallState
# fires on BOTH the initial Detect and the post-recovery re-Detect, same
# process, same invocation) — so THIS ONE dispatch now does both halves in
# sequence: recoverFromFlag's rollbackResumeIsTerminal fires the pair-terminal
# write (state='failed', backup_path retained), and the SAME `./sb install`
# immediately re-detects StateRestoreReattemptable on that just-written row
# and replays the restore to 'rolled_back' — confirmed empirically (arc run
# 29325230294): the row is observed 'failed' then 'rolled_back' ~23s apart,
# both inside the one VM_EXEC call. There is no longer a dispatch-boundary
# between "pair-terminal constructed" and "re-attempted" to assert on
# separately; phase (i)'s whole proof (construction AND re-attempt) lives in
# this single dispatch. (rollback-pair-terminal-arc.sh's own final assertion
# — state='failed' after ITS 4th, also-clean dispatch — is now LATENT-BROKEN
# by this same 111 behavior; flagged separately, not fixed here.)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 4th dispatch: ./sb install (no inject) → pair-terminal fires, THEN the SAME dispatch re-attempts it to 'rolled_back' ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > ${ARC_DISPATCH_LOG} 2>&1" || REC_RC=$?
VM_EXEC bash -c "cat ${ARC_DISPATCH_LOG} 2>/dev/null" || true
echo "[OBSERVE] 4th dispatch exit: $REC_RC"
[ "$REC_RC" = "0" ] || { echo "✗ 4th dispatch (pair-terminal + re-attempt, one clean pass, no crash) exited $REC_RC, expected 0" >&2; exit 1; }

# The pair-terminal's own moment is checked via the process's stdlib `log`
# summary line ("recoveryRollback: RESTORE-BROKE upgrade <id> after <n>
# attempt(s) — two consecutive rollback deaths", os.Stderr, captured by our
# `2>&1`) rather than the DB `error` text itself (service.go ~2727): the row
# also gets a full JSON dump to stdout at this transition (logUpgradeRow),
# so the error text DOES appear in the log too, but by the time THIS
# assertion runs the row has already moved on to the re-attempt's own
# terminal write (same dispatch) — the log line is the stable thing to grep
# for regardless of dump formatting; the FINAL row state is asserted below.
[ "$(arc_dispatch_log_has "RESTORE-BROKE upgrade")" = "yes" ] || { echo "✗ dispatch output does not show the pair-terminal's own log line — did rollbackResumeIsTerminal actually fire?" >&2; exit 1; }
[ "$(arc_dispatch_log_has "Re-attempting the restore from the retained snapshot")" = "yes" ] || { echo "✗ dispatch output does not show the STATBUS-111 re-attempt legend — did it really re-detect StateRestoreReattemptable in the same pass?" >&2; exit 1; }
echo "  ✓ dispatch log shows BOTH halves: the pair-terminal's own RESTORE-BROKE log line, then the STATBUS-111 re-attempt legend — the same clean pass did both"

FINAL_STATE_B=$(row_state_for "$B_FULL")
echo "[OBSERVE] B's row after the 4th dispatch: state=$FINAL_STATE_B"
[ "$FINAL_STATE_B" = "rolled_back" ] || { echo "✗ expected B's row 'rolled_back' (pair-terminal immediately re-attempted, STATBUS-111) after the 4th dispatch, got '$FINAL_STATE_B'" >&2; exit 1; }
echo "  ✓ the row reached its honest 'rolled_back' terminal — the pair-terminal construction AND its re-attempt both completed in this one dispatch"

[ "$(row_has_backup_path_for "$B_FULL")" = "t" ] || { echo "✗ B's row has NO retained backup_path — the STATBUS-111 probe (state=failed AND backup_path IS NOT NULL) would not have matched it at the intermediate 'failed' moment" >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
MROWS_B=$(migration_row_count)
[ "$MROWS_B" = "0" ] || { echo "✗ B left a ledger row (count=$MROWS_B, want 0) — the restore did not unrecord it" >&2; exit 1; }
assert_fingerprint_matches "phase (i): post-re-attempt-restore == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_no_orphan_backup "$VM_NAME"

# Exactly 2 callback lines: the pair-terminal's own STATBUS_ROLLBACK_FAILED=1
# (rollbackResumeIsTerminal's write), then the re-attempt's own success
# callback (STATBUS_EVENT=rolled_back, no STATBUS_ROLLBACK_FAILED key — see
# restoreAndFinalize's success branch) — both fire in this one dispatch now.
CALLBACK_COUNT_1=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_1" = "2" ] || { echo "✗ expected exactly 2 callback lines (pair-terminal + re-attempt success) after the merged dispatch, got $CALLBACK_COUNT_1" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "head -1 $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ first callback line does not carry STATBUS_ROLLBACK_FAILED=1 (the pair-terminal's own callback)" >&2; exit 1; }
echo "  ✓ exactly 2 callback lines: the pair-terminal's STATBUS_ROLLBACK_FAILED=1, then the re-attempt's own success callback"
echo "  ✓ phase (i) COMPLETE: pair-terminal construction + its immediate STATBUS-111 re-attempt, one dispatch, byte-identical clean-slate 'rolled_back', healthy, data intact"

# ═══════════════════════════════════════════════════════════════════════
# PHASE (ii) — ABORT class with STILL-CORRUPT git: real dispatch of C,
# killed post-swap before its migration runs, THEN the `pre-upgrade` git
# branch is deleted for real on the VM (environment manipulation of real
# machinery state — the map row's own recipe). The next dispatch's
# recovery hits the git-corrupt ABORT branch; the RE-ATTEMPT after that
# must refuse actionably, before any destructive step.
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "═══ PHASE (ii): git-corrupt ABORT restore-broke row + refusing re-attempt ═══"

echo ""
echo "── restarting the upgrade daemon to register C (verifyArtifacts needs a live daemon) ──"
vm_start_unit "statbus-upgrade@statbus.service"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $C_BRANCH && git cat-file -e $C_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $C_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$C_FULL" "$TICK_WAIT_S"
arc_schedule_daemon_down "$C_FULL"

echo ""
echo "── 6th dispatch: C6 kill (killed-by-system-during-individual-migration-execution) — fires POST-SWAP, BEFORE C's migration runs ──"
VM_EXEC bash -c "rm -f $CALLBACK_LOG"
arc_install_dispatch_with_inject "killed-by-system-during-individual-migration-execution"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 6th dispatch exited $ARC_DISPATCH_RC (expected 137) — the C6 kill did not fire" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after the C6 kill (crashed post-swap, pre-migrate)" >&2; exit 1; }
PHASE_AFTER_D6=$(read_flag_field "phase")
echo "[OBSERVE] C6 wedge: exit 137, flag present, flag.phase=\"$PHASE_AFTER_D6\""
[ "$PHASE_AFTER_D6" = "new-sb-upgrading" ] || { echo "✗ expected flag.phase=\"new-sb-upgrading\" after the C6 kill (resumeNewSb already committed to applyNewSbUpgrading; canonical bytes since STATBUS-164 half 2), got \"$PHASE_AFTER_D6\"" >&2; exit 1; }
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
[ "$(pre_upgrade_branch_present)" = "yes" ] || { echo "✗ the 'pre-upgrade' branch is already gone before we corrupted anything — construction invalid" >&2; exit 1; }
echo "  ✓ crashed mid-post-swap with ground truth Behind (migration never ran); 'pre-upgrade' branch present (executeUpgrade's own pin, not yet corrupted)"

echo ""
echo "── corrupting the restore input FOR REAL: deleting the pinned 'pre-upgrade' git branch on the VM ──"
VM_EXEC bash -c "cd ~/statbus && git branch -D pre-upgrade"
[ "$(pre_upgrade_branch_present)" = "no" ] || { echo "✗ 'pre-upgrade' branch still resolves after deletion — corruption did not take" >&2; exit 1; }
echo "  ✓ 'pre-upgrade' branch deleted — restoreGitState now has no resolvable target (the true r17/136 shape, constructed live)"

echo ""
echo "── 7th dispatch: ./sb install (no inject) → recovery rolls back → restoreGitState fails for real → the ABORT branch fires ──"
ABORT_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || ABORT_RC=$?
echo "[OBSERVE] 7th dispatch (abort) exit: $ABORT_RC"
[ "$ABORT_RC" = "1" ] || { echo "✗ the ABORT dispatch exited $ABORT_RC, expected 1 (rollback()'s git-corrupt ABORT branch, catastrophic exit code per service.go)" >&2; exit 1; }

FINAL_STATE_C=$(row_state_for "$C_FULL")
FINAL_ERROR_C=$(row_error_for "$C_FULL")
echo "[OBSERVE] C's row after the ABORT: state=$FINAL_STATE_C error=${FINAL_ERROR_C:0:120}..."
[ "$FINAL_STATE_C" = "failed" ] || { echo "✗ expected C's row 'failed' (ABORT terminal) after the git-corrupt rollback, got '$FINAL_STATE_C'" >&2; exit 1; }
echo "$FINAL_ERROR_C" | grep -E "ROLLBACK_FAILED_GIT_CORRUPT" >/dev/null || { echo "✗ C's row error does not match ROLLBACK_FAILED_GIT_CORRUPT: $FINAL_ERROR_C" >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
[ "$(row_has_backup_path_for "$C_FULL")" = "t" ] || { echo "✗ C's row has NO retained backup_path after the ABORT — the STATBUS-111 probe would not match it" >&2; exit 1; }
[ "$(pre_upgrade_branch_present)" = "no" ] || { echo "✗ 'pre-upgrade' branch reappeared after the ABORT — the tree should still be corrupt (nothing restores it)" >&2; exit 1; }
echo "  ✓ ABORT terminal landed in ONE pass (STATBUS-136 folded in from 4-rollback-abort-write-lands): state='failed' + ROLLBACK_FAILED_GIT_CORRUPT together, flag removed, backup_path retained, tree still corrupt"

CALLBACK_COUNT_3=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_3" = "1" ] || { echo "✗ expected exactly 1 callback line for the ABORT, got $CALLBACK_COUNT_3" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ ABORT callback line does not carry STATBUS_ROLLBACK_FAILED=1" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_ROLLBACK_FAILED=1 callback fired for the ABORT"

# ─────────────────────────────────────────────────────────────────────────
# 8th dispatch — THE RE-ATTEMPT on the abort row (phase (ii)'s own proof):
# must REFUSE actionably, BEFORE any destructive step — never mixed-era.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── 8th dispatch: ./sb install (no inject) → THE RE-ATTEMPT on the abort row — must REFUSE before touching anything ──"
VM_EXEC bash -c "rm -f $CALLBACK_LOG"
REFUSAL_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout ${INSTALL_BUDGET_S} ./sb install --non-interactive --trust-github-user jhf > ${ARC_DISPATCH_LOG} 2>&1" || REFUSAL_RC=$?
VM_EXEC bash -c "cat ${ARC_DISPATCH_LOG} 2>/dev/null" || true
echo "[OBSERVE] 8th dispatch (refusal re-attempt) exit: $REFUSAL_RC"
[ "$REFUSAL_RC" != "0" ] || { echo "✗ the re-attempt on a STILL-CORRUPT git tree exited 0 — it must refuse, never silently succeed" >&2; exit 1; }
[ "$(arc_dispatch_log_has "ROLLBACK_FAILED_GIT_CORRUPT")" = "yes" ] || { echo "✗ refusal output does not name ROLLBACK_FAILED_GIT_CORRUPT" >&2; exit 1; }
[ "$(arc_dispatch_log_has "the git tree is corrupt")" = "yes" ] || { echo "✗ refusal output does not name the corruption (\"the git tree is corrupt\")" >&2; exit 1; }
[ "$(arc_dispatch_log_has "do NOT proceed")" = "yes" ] || { echo "✗ refusal output does not tell the operator not to proceed" >&2; exit 1; }
[ "$(arc_dispatch_log_has "Restoring database from backup at")" = "no" ] || { echo "✗ refusal output shows the database restore STARTED — the git-state guard must refuse BEFORE any destructive step, never mixed-era" >&2; exit 1; }
echo "  ✓ refused actionably (ErrRollbackGitCorrupt), naming the corruption + telling the operator not to proceed — and the log proves the DB restore was NEVER reached"

FINAL_STATE_C2=$(row_state_for "$C_FULL")
FINAL_ERROR_C2=$(row_error_for "$C_FULL")
[ "$FINAL_STATE_C2" = "failed" ] || { echo "✗ C's row changed state to '$FINAL_STATE_C2' after the REFUSED re-attempt — it must stay untouched" >&2; exit 1; }
[ "$FINAL_ERROR_C2" = "$FINAL_ERROR_C" ] || { echo "✗ C's row error changed after the refused re-attempt (before: ${FINAL_ERROR_C:0:80}... / after: ${FINAL_ERROR_C2:0:80}...) — a refusal must not rewrite the row" >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
[ "$(row_has_backup_path_for "$C_FULL")" = "t" ] || { echo "✗ C's row lost its backup_path after the refused re-attempt" >&2; exit 1; }
CALLBACK_COUNT_4=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_4" = "0" ] || { echo "✗ expected ZERO callback lines for the refused re-attempt (ReattemptRestore's git-guard error returns before any runCallback), got $CALLBACK_COUNT_4" >&2; exit 1; }
echo "  ✓ row untouched by the refusal: state='failed', identical error, backup_path retained, flag absent, no callback fired"
echo "  ✓ phase (ii) COMPLETE: git-corrupt ABORT row → re-attempt REFUSES actionably before any destructive step, never mixed-era"

# Bound=2, not 0: `runCrashRecovery` explicitly `systemctl --user start`s the
# quiesced daemon right after the pair-terminal write (line ~506 of
# install_upgrade.go — restartUpgradeService's is-active gate would no-op
# there, so crash-recovery uses an explicit start instead), in the SAME
# window the 4th dispatch's own re-attempt is stopping/restoring the DB
# containers (both inside that one merged dispatch, run 29325230294's own
# journal: daemon start 10:41:19-20, its own boot-migrate fails ~10:41:23
# against the DB the re-attempt is mid-teardown/restore on, systemd
# Restart=always retries at 10:41:53 and succeeds once the restore has
# completed). Benign and self-healing (observed in the very run this arc's
# fix responds to) — NOT an arc-script artifact, a genuine product timing
# window between two independent actors (crash-recovery's own daemon
# restart vs. the re-attempt's docker-stop) that happens to race on a fast
# VM. Bounded generously so a future green run isn't flagged for a restart
# cycle that costs nothing (the daemon comes back healthy either way).
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: restore-broke-reattempt (dual-class STATBUS-111 proof — (i) a pair-terminal restore-broke row's re-attempt replays the restore to a byte-identical 'rolled_back'; (ii) a git-corrupt ABORT row's re-attempt refuses actionably, ErrRollbackGitCorrupt, before any destructive step, never mixed-era; both rows constructed via real dispatch + real kills + a real on-disk git-branch deletion, not fabrication)"
