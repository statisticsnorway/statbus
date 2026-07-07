#!/bin/bash
# Scenario: 4-rollback-abort-write-lands  (STATBUS-136's own oracle — the
# git-corrupt ABORT branch's terminal write survives, killing the r17 x3
# death loop).
#
# MECHANISM — direct state fabrication (no dispatch, no claim gate, no real
# executeUpgrade — same style as 3-postswap-resume-died-parked.sh's
# fabricate_resume_state, see that file's header for the general rationale).
# The point of THIS scenario is narrower and simpler than the park scenario:
# prove that a SINGLE pass through rollback()'s git-corrupt ABORT branch now
# concludes CLEANLY (state='failed', flag removed, one ordinary restart) —
# ZERO kills required — where before STATBUS-136 it looped (r17: the ABORT's
# own terminal write hit a DB it had just stopped, failed, kept the flag, and
# the whole abort re-ran on the next restart, x3, forever).
#
# WHY THIS IS A SEPARATE SCENARIO FROM rollback-pair-terminal-arc.sh
# (STATBUS-134's oracle) — verified against shipped code, architect-ruled
# 2026-07-06: STATBUS-136's EnsureDBReachable/StartDBForRecovery fix
# (service.go:~6655-6659) lives EXCLUSIVELY inside rollback()'s git-corrupt
# ABORT branch (restoreGitState failure). STATBUS-134's 2-consecutive-
# rollback-deaths pair-terminal is a DIFFERENT code path (recoveryRollback's
# rollbackResumeIsTerminal, formed by two deaths at the NORMAL, non-abort
# KillHere site). A single fabrication cannot exercise both: this scenario's
# construction (no resolvable git restore target) resolves in ONE clean pass
# with 136 shipped — there is no "second death" to have here, by design; that
# is exactly the property being proven.
#
# THE FABRICATED "NO RESOLVABLE TARGET" SHAPE (the true r17 shape, per the
# architect's construction requirement): flag.CommitSHA is a VALID, resolvable
# commit (HEAD) — Service.Run's OWN pre-flight `git checkout flag.CommitSHA`
# (service.go:1774, for any service-held FORWARD flag) must succeed, or the
# daemon fails before ever reaching recoverFromFlag at all (a different,
# unrelated crash loop, NOT what this scenario tests). The UNRESOLVABLE part
# is specific to rollback()'s OWN restore target: recoveryRollback always
# passes restoreTargetSHA="" (service.go:2605, STATBUS-077 — single source of
# truth is the pinned `pre-upgrade` git branch), which restoreGitState falls
# back to. Direct fabrication (this scenario, like the park scenario) never
# runs a real executeUpgrade, so that branch was NEVER created on this VM —
# restoreGitState has nothing to check out and fails, exactly as it did live
# on the r17 VM. No bogus/invalid CommitSHA is needed or wanted.
#
# THE DETERMINISTIC-BEHIND TRIGGER (architect's hard construction requirement,
# 2026-07-06): ground truth must read Behind (migrations missing, DB
# reachable) so recoverFromFlag's Resuming branch routes to recoveryRollback
# at all. This needs a VALID-named far-future PENDING migration whose BODY
# errors deterministically — NOT an invalid-version filename. r17's original
# construction leaned on an invalid-version file that ground truth counted
# but `migrate` itself rejected — that mismatch IS the STATBUS-138 bug
# (open, will be fixed) and a scenario relying on it would silently break the
# day 138 lands. This scenario uses the SAME valid 14-digit far-future
# timestamp format the park scenario uses (20990101000000-class), with a
# body that fails every application deterministically (a division-by-zero
# error, not a stall — this scenario asserts a CLEAN CONCLUSION, not a
# kill/hang, so pg_sleep is the wrong tool here).
#
# Phase IS "resuming" (FlagPhaseResuming), NOT "post_swap": fabricate_resume_state's
# default ("post_swap") would route recoverFromFlag through the FlagPhasePostSwap
# branch -> resumePostSwap -> applyPostSwap -> postSwapFailure -> d.rollback()
# DIRECTLY (IN-PROCESS, never through recoveryRollback) — a completely
# different, non-deterministic path this scenario does not want. Patching the
# fabricated flag's phase to "resuming" routes recoverFromFlag straight to its
# ground-truth branch (service.go's FlagPhaseResuming case) on the very FIRST
# boot, which is what reaches recoveryRollback -> d.rollback() -> the ABORT
# branch deterministically, in one pass.
#
# STATBUS-144 (real product finding, surfaced by this scenario's round-2 run):
# a FLAGLESS crash loop is uncounted — once the terminal write removes the
# flag, nothing stops a still-present deterministically-failing migration
# from re-erroring boot-migrate on every restart, churning to a systemd
# StartLimit death. THIS scenario deletes the synthetic migration right after
# the terminal lands specifically so it stays a clean, narrow 136 oracle
# (ONE restart, alive-idle). The scenario-WITHOUT-that-cleanup-step is 144's
# own future oracle (assert the StartLimit death instead of alive-idle) —
# not built here.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/4-rollback-abort-write-lands.sh \
#     statbus-recovery-4-rollback-abort-write-lands

set -euo pipefail

VM_NAME="${1:-statbus-recovery-4-rollback-abort-write-lands}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
CONCLUDE_WAIT_BUDGET_S="${CONCLUDE_WAIT_BUDGET_S:-300}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 4-rollback-abort-write-lands  (STATBUS-136 — the ABORT terminal write survives; ZERO kills)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_present() { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

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
# UPGRADE_CALLBACK — same safe file-transfer + glue-proof-append pattern as
# rollback-pair-terminal-arc.sh / 3-postswap-resume-died-parked.sh. The
# ABORT branch's callback (service.go:~6631) fires the SAME env-var shape as
# the pair-terminal's (STATBUS_ROLLBACK_FAILED / STATBUS_ROLLBACK_ERROR /
# STATBUS_RECOVERY_CMD) — no STATBUS_EVENT (STATBUS-137, open; noted not
# asserted).
# ─────────────────────────────────────────────────────────────────────────
CALLBACK_LOG='/tmp/rollback-abort-callback-log.txt'
echo ""
echo "── writing the rollback-abort callback script (transferred as a FILE) ──"
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/bash
echo "\${STATBUS_ROLLBACK_FAILED:-} \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/rollback-abort-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    'mv /tmp/rollback-abort-callback.sh /home/statbus/rollback-abort-callback.sh && chown statbus:statbus /home/statbus/rollback-abort-callback.sh && chmod 0755 /home/statbus/rollback-abort-callback.sh'
echo "  ✓ /home/statbus/rollback-abort-callback.sh installed (chmod 0755)"

VM_EXEC bash -c "rm -f $CALLBACK_LOG"
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/rollback-abort-callback.sh\n" >> .env.config'
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env.config" || { echo "✗ UPGRADE_CALLBACK injection did not land in .env.config" >&2; exit 1; }

echo ""
echo "── staging HEAD + checking out the working tree ──"
upload_sb_to_vm "$VM_NAME"
VM_EXEC bash -c "cd ~/statbus && git fetch --depth 1 origin $HEAD_SHA 2>/dev/null || true; git -c advice.detachedHead=false checkout $HEAD_SHA"
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"

echo ""
echo "── pre-applying the real migration delta (steady-state — same rationale as the park scenario: the recovery_* columns must already exist before pass 1, or RecoveryBudgetGuard's fail-open 42703 path shifts the arithmetic) ──"
VM_EXEC bash -c "cd ~/statbus && timeout 600 ./sb migrate up --verbose"

# ─────────────────────────────────────────────────────────────────────────
# Deterministically-FAILING migration — valid 14-digit far-future version
# (STATBUS-138 caveat: NOT an invalid-version file), body errors every
# application. No pinned inject needed: a division-by-zero is unconditional.
# ─────────────────────────────────────────────────────────────────────────
FAIL_MIGRATION_FILE='20990101000000_rollback_abort_scenario_deterministic_fail.up.sql'
echo ""
echo "── writing the synthetic deterministically-failing migration (division by zero, valid far-future version) ──"
VM_EXEC bash -c "cd ~/statbus && printf 'SELECT 1/0;\n' > migrations/$FAIL_MIGRATION_FILE"
VM_EXEC bash -c "test -f ~/statbus/migrations/$FAIL_MIGRATION_FILE" || { echo "✗ synthetic failing migration did not land" >&2; exit 1; }
echo "  ✓ migrations/$FAIL_MIGRATION_FILE written"

echo ""
echo "── fabricating the in_progress row + service-held flag (dead pid), then patching phase to 'resuming' ──"
fabricate_resume_state "$VM_NAME" "$HEAD_SHA" >/dev/null
# fabricate_resume_state's default phase is "post_swap" (routes through
# resumePostSwap — the wrong, non-deterministic path for THIS scenario; see
# the header). Patch to "resuming" so recoverFromFlag routes straight to its
# ground-truth branch on the very first boot. No other field needs to
# change: Step/PriorDeathStep are already omitted (fresh crash, never
# recorded a death) and BackupPath is already absent (empty — this
# fabrication was never a real upgrade, so there is no snapshot; restoreDatabase
# refuses to touch the volume on every pass here, matching the true r17
# fabrication exactly).
VM_EXEC bash -c "cd ~/statbus && sed -i 's/\"phase\":\"post_swap\"/\"phase\":\"resuming\"/' tmp/upgrade-in-progress.json"
VM_EXEC bash -c "grep -q '\"phase\":\"resuming\"' ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ phase patch to 'resuming' did not land" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json" >&2 || true
    exit 1
}
echo "  ✓ flag fabricated + patched: phase=resuming, commit_sha=$HEAD_SHA"

echo ""
echo "── restarting upgrade-service unit onto HEAD (discovers the fabricated flag — this single boot IS the whole scenario, no kill) ──"
vm_restart_unit "statbus-upgrade@statbus.service"
echo "  ✓ unit restart issued"

# ─────────────────────────────────────────────────────────────────────────
# Wait for the ABORT branch to conclude: state leaves 'in_progress'. No kill
# anywhere in this scenario — the load-bearing claim is that ONE pass is
# enough, unassisted.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for the row to leave 'in_progress' (budget ${CONCLUDE_WAIT_BUDGET_S}s) ──"
START=$(date +%s)
FINAL_STATE="in_progress"
while :; do
    NOW=$(date +%s); ELAPSED=$((NOW - START))
    FINAL_STATE=$(row_state)
    if [ "$FINAL_STATE" != "in_progress" ] && [ "$FINAL_STATE" != "(db-down/?)" ]; then
        echo "  [OBSERVE] row left in_progress after ${ELAPSED}s: state=$FINAL_STATE"
        break
    fi
    if [ "$ELAPSED" -ge "$CONCLUDE_WAIT_BUDGET_S" ]; then
        echo "✗ row still '$FINAL_STATE' after ${CONCLUDE_WAIT_BUDGET_S}s — the ABORT branch did not conclude (136 regression, or the fabrication never reached rollback() at all)" >&2
        exit 1
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Delete the synthetic failing migration IMMEDIATELY the row leaves
# in_progress — BEFORE any settle/NRestarts assertion (park-scenario cleanup
# ordering, 3-postswap-resume-died-parked.sh:736-740, verbatim pattern).
# Architect autopsy, round 2 (STATBUS-144, real product finding): the flag is
# gone once the terminal write lands, but the migration file is NOT — a
# FLAGLESS boot still runs boot-migrate, which still finds this
# deterministically-failing migration pending and still fails on it, every
# restart, forever, churning the daemon into a systemd StartLimit death (the
# scenario's own second run caught this live: NRestarts was at 7 and
# climbing on the kept VM). That is a genuine, separate bug (no death-budget
# guard covers a FLAGLESS crash loop — filed as STATBUS-144) which this
# 136-only scenario must not trip over. Deleting the migration promptly is
# what makes the ABORT's own exit the ONLY legitimate restart in this
# scenario's lifetime, so the strict NRestarts<=1 bound below still holds.
# NOTE — 144's own future oracle is exactly THIS scenario WITHOUT this
# cleanup step (leave the migration in place after the terminal write and
# assert the StartLimit death instead of alive-idle); not built here.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── deleting the synthetic failing migration (must not survive past the terminal — STATBUS-144) ──"
VM_EXEC bash -c "cd ~/statbus && rm -f migrations/$FAIL_MIGRATION_FILE"
VM_EXEC bash -c "test ! -f ~/statbus/migrations/$FAIL_MIGRATION_FILE" || { echo "✗ synthetic failing migration still present after rm" >&2; exit 1; }
echo "  ✓ migrations/$FAIL_MIGRATION_FILE removed"

# The unit's own restart (after the ABORT's unconditional os.Exit(1)) needs a
# moment to come back up healthy before the alive-idle assertions below.
echo ""
echo "── waiting for the unit to settle after its own post-ABORT restart (budget ${RESTART_WAIT_BUDGET_S}s) ──"
SETTLE_START=$(date +%s)
while :; do
    NOW=$(date +%s); ELAPSED=$((NOW - SETTLE_START))
    STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$STATE" = "active" ] && { echo "  ✓ unit active (settled after ${ELAPSED}s)"; break; }
    if [ "$ELAPSED" -ge "$RESTART_WAIT_BUDGET_S" ]; then
        echo "✗ unit did not settle to 'active' within ${RESTART_WAIT_BUDGET_S}s (last state: $STATE)" >&2
        exit 1
    fi
    sleep 3
done
# A brief further settle window, then confirm NRestarts is FROZEN — the
# anti-loop assertion: with 136 shipped, exactly ONE restart total (the
# ABORT's own os.Exit(1)); the box must NOT keep restarting.
sleep 15

echo ""
echo "── convergence checks (ABORT concluded cleanly in ONE pass, zero kills) ──"
echo "[OBSERVE] final row state: $FINAL_STATE"
[ "$FINAL_STATE" != "rolled_back" ] || { echo "✗ state='rolled_back' — a git-restore-fail ABORT must record 'failed' (degraded, services stopped), never 'rolled_back' (which claims a healthy old-version box)" >&2; exit 1; }
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — impossible on this route (ground truth read Behind, forward was never attempted)" >&2; exit 1; }
[ "$FINAL_STATE" = "failed" ] || { echo "✗ expected terminal 'failed' (ABORT), got '$FINAL_STATE'" >&2; exit 1; }
echo "  ✓ state='failed' (the ABORT's terminal, written by the FIRST and ONLY pass)"

assert_upgrade_row_error_matches "$VM_NAME" "ROLLBACK_FAILED_GIT_CORRUPT"
assert_flag_file_absent "$VM_NAME"
echo "  ✓ flag removed — the terminal write landed (STATBUS-136's fix: this used to hang the flag forever on a stopped DB, r17 x3)"

# NRestarts bound of 1: this scenario never kills anything — the ONLY
# restart in its entire lifetime is the ABORT branch's own unconditional
# os.Exit(1) (rc.67 trifecta) after its terminal write succeeds. Anything
# higher means the box is still looping (the exact r17 pathology 136 fixed).
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 1

CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ callback line does not carry STATBUS_ROLLBACK_FAILED=1" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_ROLLBACK_FAILED=1 callback fired (STATBUS-137's STATBUS_EVENT gap noted, not asserted)"

# Note (intentionally NOT asserted here): the box is in the ABORT's
# degraded-but-recorded state — services were stopped for the (never-run)
# restore and this branch never brings them back up (maintenance stays ON,
# by design, until an operator completes the manual recovery steps the
# ABORT's progress log prints). health-passes / demo-data assertions do not
# apply to this terminal the way they do to rollback-pair-terminal's (whose
# services were never touched past the stop). This scenario's contract is
# narrowly: does the terminal WRITE land, and does the box stay alive-idle
# rather than crash-loop.

echo ""
echo "PASS: 4-rollback-abort-write-lands (the git-corrupt ABORT branch concluded in exactly ONE pass — zero kills — state='failed', flag removed, callback fired once, unit alive-idle with NRestarts bounded at 1; STATBUS-136 killed the r17 x3 death loop)"
