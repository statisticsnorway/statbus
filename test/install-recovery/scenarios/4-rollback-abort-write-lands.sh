#!/bin/bash
# Scenario: 4-rollback-abort-write-lands  (STATBUS-136's own oracle — the
# git-corrupt ABORT branch's terminal write survives, killing the r17 x3
# death loop — AND, promoted round 3 [architect autopsy], a live proof of
# the flagless STATBUS-039 self-heal: this fabrication's commit_sha IS the
# running binary's version, so once the flag + synthetic migration are gone
# the very same boot that recorded the ABORT's 'failed' terminal is also a
# genuinely-healthy-at-target box, and markCurrentVersionCompleted converts
# it failed->completed, error->NULL. Both properties are asserted, each from
# its own correctly-timed read — see the two combined state+error reads
# below).
#
# INTERIM: deleted, TOGETHER WITH its 4-rollback-abort-churn-then-alive-idle
# variant (STATBUS-144 AC#3, which inherits this scenario's ABORT construction
# verbatim to reach the abort-aftermath state), when the restore-broke
# re-attempt arc goes green (same pattern as the r19 park scenario).
# Architect-ruled (STATBUS-071): this scenario is a remaining
# fabricate_resume_state caller alongside 3-postswap-rune-wedge and its own
# churn-then-alive-idle variant; this scenario's abort-row construction
# produces exactly the state that arc's re-attempt will build for real — one
# construction, three oracles now — so BOTH members of this family stay until
# that arc proves out.
#
# MECHANISM — direct state fabrication (no dispatch, no claim gate, no real
# executeUpgrade — direct state fabrication via the fabricate_resume_state
# helper (see its header in lib/data-helpers.sh for the general rationale; the
# 3-postswap-resume-died-parked scenario that also documented it was retired, STATBUS-071).
# The point of THIS scenario is narrower and simpler than the park scenario:
# prove that a SINGLE pass through rollback()'s git-corrupt ABORT branch now
# concludes CLEANLY (state='failed', full ROLLBACK_FAILED_GIT_CORRUPT error,
# flag removed, one ordinary restart) — ZERO kills required — where before
# STATBUS-136 it looped (r17: the ABORT's own terminal write hit a DB it had
# just stopped, failed, kept the flag, and the whole abort re-ran on the
# next restart, x3, forever). Round 3's autopsy then found that the SAME
# clean restart, being flagless AND genuinely at-target, self-heals to
# 'completed' moments later — a real, separate, correct product behavior
# this scenario now also asserts rather than being surprised by.
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
# row_state_and_error — SELECT state + error in ONE query (park scenario's
# recovery_row_cols pattern, pipe-separated). Used for the early combined
# read immediately after the row leaves in_progress: a single query means
# state and error are read from the SAME row snapshot, so there is no window
# for the flagless self-heal boot (which needs daemon exit + RestartSec=30 +
# boot — tens of seconds away) to change the answer between two separate
# reads.
row_state_and_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'; }

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
# rollback-pair-terminal-arc.sh / postswap-health-park-arc.sh (the latter
# superseded the retired 3-postswap-resume-died-parked). The
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
# COMBINED early read (architect autopsy, round 3): state AND error must be
# read from the SAME row snapshot, taken immediately here — the ABORT's
# terminal write is complete at this point (single UPDATE, state='failed'
# and the full ROLLBACK_FAILED_GIT_CORRUPT error land together), but this
# fabricated row is a genuinely at-target shape (commit_sha IS the running
# binary's version) on a box a flagless boot will find otherwise healthy —
# so a LATER read races the flagless self-heal (markCurrentVersionCompleted),
# which turns failed->completed and NULLs error. That self-heal cannot fire
# before daemon exit + RestartSec=30s + boot, so this read (taken within
# a few seconds of the wait loop's own break) is safe by comfortable margin
# (>20s). Asserting here proves the ABORT terminal itself landed correctly,
# independent of and before the self-heal this scenario now ALSO proves at
# the end.
# ─────────────────────────────────────────────────────────────────────────
EARLY_ROW=$(row_state_and_error)
EARLY_STATE=$(echo "$EARLY_ROW" | cut -d'|' -f1)
EARLY_ERROR=$(echo "$EARLY_ROW" | cut -d'|' -f2-)
echo "[OBSERVE] early combined read: state=$EARLY_STATE error=${EARLY_ERROR:0:100}..."
[ "$EARLY_STATE" = "failed" ] || { echo "✗ expected the ABORT terminal 'failed' on the early read, got '$EARLY_STATE'" >&2; exit 1; }
echo "$EARLY_ERROR" | grep -E "ROLLBACK_FAILED_GIT_CORRUPT" >/dev/null || { echo "✗ early error does not match ROLLBACK_FAILED_GIT_CORRUPT: $EARLY_ERROR" >&2; exit 1; }
echo "  ✓ ABORT terminal landed correctly: state='failed', error matches ROLLBACK_FAILED_GIT_CORRUPT (read before the flagless self-heal window opens)"

# ─────────────────────────────────────────────────────────────────────────
# Delete the synthetic failing migration IMMEDIATELY the row leaves
# in_progress — BEFORE any settle/NRestarts assertion (park-scenario cleanup
# ordering; the pattern lives on in postswap-health-park-arc.sh after the
# retired 3-postswap-resume-died-parked was deleted, STATBUS-071).
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
echo "── final convergence checks (the flagless self-heal, round-3 autopsy) ──"
# By now the settle window has passed — comfortably past daemon exit +
# RestartSec=30s + boot. The clean (flagless, thanks to the STATBUS-144
# cleanup above) boot re-verifies ground truth: this fabrication's
# commit_sha IS the running binary's version and the box is genuinely
# healthy, so the SAME self-heal that resolves the rune class
# (markCurrentVersionCompleted, STATBUS-039's designed at-target behavior)
# converts the row failed->completed and NULLs error. A REAL abort box
# (services actually stopped, genuinely not at-target) cannot self-heal this
# way — this fabrication's "no resolvable git target" shape happens to also
# be an at-target shape once the flag and migration are gone, which is
# exactly what makes this scenario ALSO a live proof of the flagless
# self-heal, not just of 136's terminal-write fix.
FINAL_ROW=$(row_state_and_error)
FINAL_STATE=$(echo "$FINAL_ROW" | cut -d'|' -f1)
FINAL_ERROR=$(echo "$FINAL_ROW" | cut -d'|' -f2-)
echo "[OBSERVE] final row: state=$FINAL_STATE error='${FINAL_ERROR}'"
[ "$FINAL_STATE" = "completed" ] || { echo "✗ expected the flagless self-heal to converge to 'completed', got '$FINAL_STATE'" >&2; exit 1; }
[ -z "$FINAL_ERROR" ] || { echo "✗ expected error IS NULL after the self-heal, got '$FINAL_ERROR'" >&2; exit 1; }
echo "  ✓ state='completed', error IS NULL (the flagless self-heal converged cleanly, on top of the ABORT terminal already proven above)"

assert_flag_file_absent "$VM_NAME"
echo "  ✓ flag removed — the terminal write landed (STATBUS-136's fix: this used to hang the flag forever on a stopped DB, r17 x3)"

# NRestarts bound of 1: this scenario never kills anything — the ONLY
# restart in its entire lifetime is the ABORT branch's own unconditional
# os.Exit(1) (rc.67 trifecta) after its terminal write succeeds; the
# flagless self-heal runs INSIDE that one restart's boot, not a second one.
# Anything higher means the box is still looping (the exact r17 pathology
# 136 fixed, or the STATBUS-144 flagless-migration churn the cleanup step
# above prevents).
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 1

CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^1 " || { echo "✗ callback line does not carry STATBUS_ROLLBACK_FAILED=1" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_ROLLBACK_FAILED=1 callback fired (STATBUS-137's STATBUS_EVENT gap noted, not asserted; fired by the ABORT branch, before the self-heal)"

echo ""
echo "PASS: 4-rollback-abort-write-lands (the git-corrupt ABORT branch concluded in exactly ONE pass — zero kills — state='failed' + ROLLBACK_FAILED_GIT_CORRUPT error read early and correctly; the STATBUS-144 cleanup then let the SAME boot's flagless self-heal converge the row to state='completed'/error=NULL; flag removed, callback fired once, unit alive-idle with NRestarts bounded at 1; STATBUS-136 killed the r17 x3 death loop, and this scenario now also live-proves the flagless self-heal)"
