#!/bin/bash
# Scenario: 3-postswap-resume-died-parked  (STATBUS-044, PARK-SCENARIO ASSERTION SPEC)
#
# Renamed from the deleted 3-postswap-resume-died-rollback.sh (STATBUS-099,
# 2026-06-19): that file asserted a ROLLBACK terminal and was deleted as
# product-impossible against the code as it stood then (resumePostSwap's
# self-heal canary converged before any re-kill; grounded by VM-run
# 27820228835). STATBUS-046 (D3, shipped 2026-07-03) added a genuinely NEW
# mechanism since that deletion — the crash-resume death budget
# (cli/internal/upgrade/recovery_escalation.go: resumeEscalation) — that
# PARKS a persistently-failing at-target forward attempt instead of looping
# loud forever or rolling back. This file is a FRESH build against that new
# mechanism, not a resurrection of the deleted rollback-asserting file. The
# terminal here is PARKED, then UN-PARKED — never rolled_back.
#
# Assertion spec: STATBUS-044 comment #1 (architect, 2026-07-03).
#
# ─────────────────────────────────────────────────────────────────────────
# MECHANISM — why this scenario does NOT use an inject.KillHere class
# ─────────────────────────────────────────────────────────────────────────
# The death-budget path (resumeEscalation) only engages on a DAEMON PROCESS
# DEATH — recovery_attempts increments inside resumePostSwap, which only
# runs when the daemon PROCESS restarts and recoverFromFlag finds
# Phase=FlagPhaseResuming (or FlagPhasePostSwap, the normal exit-42
# continuation — both route to resumePostSwap). Killing a SPAWNED
# SUBPROCESS (e.g. `sb migrate up`, which is where the existing
# "killed-by-system-during-individual-migration-execution" class fires,
# cli/internal/migrate/migrate.go:466) does NOT kill the daemon — it
# returns an error that postSwapFailure/parkForDeterministicFailure handle
# WITHOUT the process exiting (verified by reading both functions: neither
# calls os.Exit; postSwapFailure just records the failure and returns an
# error up the call stack). That is a DIFFERENT, already-shipped mechanism
# (STATBUS-046 slice 2, park-on-first for classDeterministic/classResource)
# — not what this scenario needs to drive.
#
# The only existing DAEMON-level (in-process) inject.KillHere class inside
# the Phase-3 forward flow is "killed-by-system-during-container-restart"
# (service.go:5128, between StepStartServices and StepHealthCheck) — but
# that site sits AFTER migrate-up, so resumePostSwap's self-heal canary
# (containersAtFlagTarget + no-pending-migrations + healthCheck, service.go
# ~5459) is live at that point and — per STATBUS-099's own grounded VM
# evidence — reliably converges to 'completed' on the very next resume
# instead of re-entering the SAME step twice. That is exactly the race this
# scenario must NOT run into.
#
# So: this scenario uses a REAL external SIGKILL of the daemon's OS process
# (the same primitive as wedge-helpers.sh's simulate_sigkill_upgrade_service,
# Stage F — "kill -9 the upgrade-service Go process directly, bypassing
# systemd's signal handling entirely"), GATED on the flag file's "step"
# field reaching "migrate-up" (StepMigrateUp, cli/internal/upgrade/
# recovery_escalation.go:33 — recorded by markStep BEFORE the migrate
# subprocess spawns, cli/internal/upgrade/service.go:4986). Migrate-up runs
# strictly BEFORE StepStartServices, so containers are never touched before
# either kill — containersAtFlagTarget is false on every resume, the
# self-heal canary never fires, and applyPostSwap reliably re-enters
# StepMigrateUp on every subsequent resume. The wait-for-step poll has a
# bounded budget and fails LOUD (not silently) if it never observes the
# target step — see wait_for_flag_step below.
#
# ─────────────────────────────────────────────────────────────────────────
# SCENARIO SHAPE
# ─────────────────────────────────────────────────────────────────────────
#   1. Install at INSTALL_VERSION. Populate demo data, snapshot.
#   2. Fabricate a scheduled row for HEAD — the RUNNING daemon (Restart=
#      always, RestartSec=30) claims + dispatches it unattended (mirrors
#      0-happy-upgrade / 3-postswap-migration-timeout — do NOT quiesce the
#      service; its own dispatch + auto-restart IS the mechanism this
#      scenario needs).
#   3. Kill #1: poll for flag.step=="migrate-up", SIGKILL the daemon
#      process. This is resumePostSwap attempt=1 (the normal exit-42
#      continuation dying at migrate-up — attempts=1, deaths=0 at THIS
#      resume; resumeEscalation(1, "", "", false) → continue, so attempt 1
#      always runs applyPostSwap once before the kill can land).
#   4. Wait for the unit to auto-restart (systemd RestartSec=30).
#   5. Kill #2: same poll+kill. This is resumePostSwap attempt=2 (flag.Step
#      going in = "migrate-up" from kill #1, flag.PriorDeathStep="" —
#      resumeEscalation(2, "migrate-up", "", false): deaths=1, sameStepTwice
#      false (priorDeathStep empty) → continue; applyPostSwap re-runs, dies
#      at migrate-up again).
#   6. Right after kill #2, inject UPGRADE_CALLBACK into .env directly
#      (config.Generate() does not propagate this key — see the Phase 5
#      comment below — so it must land AFTER the LAST config-generate that
#      will run. attempt=3 never calls
#      config-generate: same-step-twice parks INSIDE resumePostSwap, before
#      applyPostSwap/StepConfigGenerate runs again — attempt 2's
#      config-generate, which already completed before this kill, is
#      therefore the last one).
#   7. Wait for the unit to auto-restart again → attempt=3: flag.Step=
#      "migrate-up" (from kill #2), flag.PriorDeathStep="migrate-up" (from
#      kill #1, rolled forward at the start of attempt 2) →
#      resumeEscalation(3, "migrate-up", "migrate-up", false): sameStepTwice
#      TRUE → PARK immediately, NO third kill needed (attempt 3 parks before
#      ever re-entering applyPostSwap).
#   8. Assert the PARK STATE (spec items 1-5).
#   9. Two EXTRA systemd restarts — assert each is skipped (parked-skip),
#      no attempts increment, no additional siren.
#  10. UN-PARK via the install arm (spec item 6, the happy/preferred
#      terminal): the kill-gate is already lifted (nothing left to kill —
#      the poll loop only ran for kills #1/#2 above), so the fresh
#      un-parked attempt runs `./sb install` and COMPLETES. Assert:
#      UN-PARKED log line, parked_at NULL, recovery_attempts==1, terminal
#      state='completed', health passes, data intact — proving the
#      park/un-park cycle left the pipeline undamaged.
#
#   Item 7 (the NOTIFY/RunSchedule un-park arm) is NOT covered — architect's
#   spec says "install arm at minimum"; covering both arms would require a
#   SECOND full park cycle (2 more kills) to reach a fresh parked row to
#   un-park via NOTIFY instead, roughly doubling this scenario's runtime.
#   Flagged as a deliberate scope cut, not an oversight.
#
# Hetzner-runnability:
#   BUILD-ONLY. Not run on a paid VM yet (sequenced separately per the
#   foreman/architect). The external-SIGKILL-gated-on-flag-step mechanism
#   is novel to this scenario (no prior scenario uses a step-gated external
#   kill rather than an inject.KillHere class) — the first VM run is the
#   real empirical test of the poll timing and the config-generate/
#   UPGRADE_CALLBACK persistence assumption documented above.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-resume-died-parked.sh \
#     statbus-recovery-3-postswap-resume-died-parked

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-resume-died-parked}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# Budget for each "wait for flag.step to reach migrate-up" poll. Generous —
# StepConfigGenerate + StepImagePull + StepDBUp + StepReconnect all run
# before migrate-up, and image-pull can be slow on a cold VM.
STEP_WAIT_BUDGET_S="${STEP_WAIT_BUDGET_S:-300}"
# systemd RestartSec=30 (ops/statbus-upgrade.service) + boot/reconnect
# overhead before the flag is even readable again.
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-180}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-resume-died-parked  (STATBUS-044/046 park-not-loop)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FLAG_PATH='~/statbus/tmp/upgrade-in-progress.json'
CALLBACK_LOG='/tmp/park-callback-log.txt'

# ─────────────────────────────────────────────────────────────────────────
# helpers local to this scenario
# ─────────────────────────────────────────────────────────────────────────

# read_flag_step — extract the "step" field from the flag JSON (grep/sed —
# no assumption that jq is installed on the VM). Empty string if the flag
# is absent or the field isn't present (Step is `omitempty`).
read_flag_step() {
    VM_EXEC bash -c "grep '\"step\":' $FLAG_PATH 2>/dev/null | sed -E 's/.*\"step\": *\"([^\"]*)\".*/\1/'" 2>/dev/null | tr -d ' \r\n'
}

# read_flag_prior_step — same, for prior_death_step (used only for
# diagnostics/logging here; the assertions read recovery_parked_reason
# instead, which is the durable DB-side record of the same fact).
read_flag_prior_step() {
    VM_EXEC bash -c "grep '\"prior_death_step\":' $FLAG_PATH 2>/dev/null | sed -E 's/.*\"prior_death_step\": *\"([^\"]*)\".*/\1/'" 2>/dev/null | tr -d ' \r\n'
}

# daemon_pid — the live upgrade-service Go process PID, or empty if not
# running. Mirrors wedge-helpers.sh's simulate_sigkill_upgrade_service
# process-discovery (pgrep -f "sb upgrade service").
daemon_pid() {
    VM_EXEC bash -c 'pgrep -f "sb upgrade service" 2>/dev/null | head -1' 2>/dev/null | tr -d ' \r\n'
}

# wait_for_flag_step <target_step> <budget_s> — poll every 1s for the flag's
# step field to equal <target_step>. Fails LOUD (non-zero, diagnostic dump)
# on timeout rather than silently racing past — see the MECHANISM header
# comment for why this is a real (bounded, diagnosable) timing dependency
# rather than a deterministic code-level trigger.
wait_for_flag_step() {
    local target="$1" budget="$2"
    local start now elapsed step
    start=$(date +%s)
    while true; do
        now=$(date +%s)
        elapsed=$((now - start))
        step=$(read_flag_step)
        if [ "$step" = "$target" ]; then
            echo "  ✓ flag.step == '$target' (t+${elapsed}s)"
            return 0
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ flag.step never reached '$target' within ${budget}s (last observed: '${step:-<absent>}')" >&2
            echo "  This means either the upgrade never dispatched, or it raced past migrate-up faster" >&2
            echo "  than this 1s poll could observe — the scenario's external-kill mechanism (see the" >&2
            echo "  MECHANISM header comment) depends on catching this window. Diagnostic flag dump:" >&2
            VM_EXEC bash -c "cat $FLAG_PATH 2>/dev/null" >&2 || true
            return 1
        fi
        sleep 1
    done
}

# kill_daemon_at_step <target_step> — wait for flag.step==<target_step>,
# then SIGKILL the live daemon PID. Fails loud if the process isn't found
# (the step observation and the PID lookup are two separate reads — a
# process that dies on its own between them is a real race, but the
# subsequent restart-wait step would then fail loudly too, so this is not
# a silent-pass path). Sets the global LAST_KILLED_PID (mirrors arc-helpers.sh's
# ARC_DISPATCH_RC global-output convention) so wait_for_restart can confirm
# the NEXT observed PID is genuinely a different (new) process, not a
# not-yet-reaped stale pgrep match of the process we just killed.
LAST_KILLED_PID=""
kill_daemon_at_step() {
    local target="$1"
    wait_for_flag_step "$target" "$STEP_WAIT_BUDGET_S" || return 1
    local pid
    pid=$(daemon_pid)
    if [ -z "$pid" ]; then
        echo "✗ flag.step=='$target' observed but no live 'sb upgrade service' process found to kill" >&2
        return 1
    fi
    echo "  killing upgrade-service PID=$pid at step='$target'"
    VM_EXEC bash -c "kill -9 $pid" 2>/dev/null || true
    # shellcheck disable=SC2034  # read by wait_for_restart after this call
    LAST_KILLED_PID="$pid"
    return 0
}

# wait_for_restart <budget_s> [prev_pid] — poll for the daemon process to
# come back alive after a kill (systemd Restart=always, RestartSec=30). When
# prev_pid is given, requires the observed PID to DIFFER from it — otherwise
# a not-yet-reaped stale pgrep match of the just-killed process would read
# as "restarted" one poll cycle early.
wait_for_restart() {
    local budget="$1" prev_pid="${2:-}"
    local start now elapsed pid
    start=$(date +%s)
    while true; do
        now=$(date +%s); elapsed=$((now - start))
        pid=$(daemon_pid)
        if [ -n "$pid" ] && { [ -z "$prev_pid" ] || [ "$pid" != "$prev_pid" ]; }; then
            echo "  ✓ upgrade-service restarted, PID=$pid (t+${elapsed}s)"
            return 0
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ upgrade-service did not restart (with a new PID) within ${budget}s" >&2
            VM_EXEC systemctl --user status "$UPGRADE_UNIT" --no-pager -l 2>/dev/null | tail -30 >&2 || true
            return 1
        fi
        sleep 2
    done
}

# recovery_row_cols — SELECT the three recovery_* columns + state for the
# latest upgrade row, pipe-separated.
recovery_row_cols() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, recovery_attempts, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'
}

echo ""
echo "── initial install at $INSTALL_VERSION ──"
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — fabricate the scheduled row for HEAD; the RUNNING daemon claims
# + dispatches it unattended. Do NOT quiesce the service — its own dispatch
# and its systemd-driven auto-restart across the two kills below ARE the
# mechanism this scenario drives (mirrors 0-happy-upgrade /
# 3-postswap-migration-timeout, the two existing service-dispatched
# scenarios per wedge-helpers.sh's INVARIANT comment on quiesce_upgrade_service).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── uploading HEAD sb binary + fabricating scheduled row (daemon-dispatched) ──"
upload_sb_to_vm "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — kill #1 (resumePostSwap attempt=1, the normal exit-42
# continuation) and kill #2 (attempt=2), both pinned at flag.step==
# "migrate-up". See the MECHANISM header comment for why this step and why
# an external kill rather than inject.KillHere.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── kill #1: waiting for flag.step=='migrate-up' (attempt=1) ──"
kill_daemon_at_step "migrate-up"
wait_for_restart "$RESTART_WAIT_BUDGET_S" "$LAST_KILLED_PID"

echo ""
echo "── kill #2: waiting for flag.step=='migrate-up' (attempt=2) ──"
kill_daemon_at_step "migrate-up"
KILL2_PID="$LAST_KILLED_PID"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — inject the callback marker BEFORE the daemon restarts into
# attempt=3. attempt=3 same-step-twice parks INSIDE resumePostSwap without
# ever calling applyPostSwap again (no further config-generate to clobber
# this), so this is the last safe window to set it. runCallback
# (cli/internal/upgrade/service.go:5866) reads UPGRADE_CALLBACK from .env
# directly via dotenv.Load — config.Generate() does not propagate this key
# (grepped cli/internal/config/config.go: zero references), so .env is the
# right and only place to put it, and this is the right and only time.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── injecting UPGRADE_CALLBACK marker into .env (observability for the siren-once assertion) ──"
VM_EXEC bash -c "cd ~/statbus && rm -f $CALLBACK_LOG && printf 'UPGRADE_CALLBACK=echo \"\$STATBUS_EVENT \$(date -u +%%FT%%TZ)\" >> $CALLBACK_LOG\n' >> .env"
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env" || { echo "✗ UPGRADE_CALLBACK injection did not land in .env" >&2; exit 1; }

echo ""
echo "── waiting for restart into attempt=3 (expect same-step-twice PARK, no further kill needed) ──"
wait_for_restart "$RESTART_WAIT_BUDGET_S" "$KILL2_PID"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — wait for the PARK to land (recovery_parked_at IS NOT NULL).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for park (recovery_parked_at IS NOT NULL) ──"
PARK_START=$(date +%s)
while true; do
    NOW=$(date +%s); ELAPSED=$((NOW - PARK_START))
    ROW=$(recovery_row_cols)
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "  ✓ row parked (t+${ELAPSED}s): $ROW"
        break
    fi
    if [ "$ELAPSED" -ge "$PARK_WAIT_BUDGET_S" ]; then
        echo "✗ row did not park within ${PARK_WAIT_BUDGET_S}s (last: $ROW)" >&2
        exit 1
    fi
    sleep 3
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — ASSERT PARK STATE (spec items 1-5)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── assert 1: row state + recovery_attempts + parked_reason (same-step-twice path, attempts 2-3) ──"
ROW=$(recovery_row_cols)
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_REASON=$(echo "$ROW" | cut -d'|' -f4)
echo "  state=$ROW_STATE attempts=$ROW_ATTEMPTS reason=$ROW_REASON"

[ "$ROW_STATE" = "in_progress" ] || { echo "✗ expected state='in_progress' while parked, got '$ROW_STATE'" >&2; exit 1; }

# Pin the same-step-twice path: this scenario ALWAYS kills at the SAME step
# ("migrate-up") both times, so the reason MUST name same-step-twice, never
# the budget-exhaust message — the budget message appearing instead would
# mean the dying-step write-ahead (recordFlagStep) broke (STATBUS-044
# comment #1's explicit diagnostic: "the budget message showing up instead
# means the dying-step write-ahead broke").
echo "$ROW_REASON" | grep -qE 'two consecutive crash-deaths at step "migrate-up".*same-step-twice' || {
    echo "✗ recovery_parked_reason does not match the same-step-twice pattern for step 'migrate-up'" >&2
    echo "  actual: $ROW_REASON" >&2
    if echo "$ROW_REASON" | grep -q 'budget exhausted'; then
        echo "  got the BUDGET-EXHAUST message instead — the dying-step write-ahead (recordFlagStep) likely broke" >&2
    fi
    exit 1
}
echo "  ✓ reason matches same-step-twice at step 'migrate-up'"

# Same-step-twice parks on the resume immediately following the second
# kill WITHOUT a third applyPostSwap run — attempts==3 exactly (see the
# MECHANISM/SCENARIO SHAPE header trace). Accept 2-3 per the architect's
# own stated range (comment #1) rather than pinning a single value.
case "$ROW_ATTEMPTS" in
    2|3) echo "  ✓ recovery_attempts=$ROW_ATTEMPTS (same-step-twice path, expected 2-3)" ;;
    *) echo "✗ recovery_attempts=$ROW_ATTEMPTS — expected 2 or 3 for the same-step-twice path" >&2; exit 1 ;;
esac

echo ""
echo "── assert 2: unit alive-idle, NRestarts BOUNDED and FROZEN across a settle window (anti-rune, load-bearing) ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
NR_BEFORE=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
echo "  NRestarts (pre-settle) = $NR_BEFORE"
[[ "$NR_BEFORE" =~ ^[0-9]+$ ]] || { echo "✗ could not parse NRestarts (got '$NR_BEFORE')" >&2; exit 1; }
# Bound, never pin: 2 real kills so far (2 restarts) plus normal systemd
# start/stop churn margin. NOT an exact-equality check (systemd's counter
# includes unrelated starts — anti-assertion in the spec).
[ "$NR_BEFORE" -le 6 ] || { echo "✗ NRestarts=$NR_BEFORE exceeds the bound of 6 after 2 kills — restart-loop pathology" >&2; exit 1; }
echo "  settling 30s, then re-checking NRestarts is UNCHANGED (parked ⇒ alive-idle, no further crash-restart cycle)..."
sleep 30
NR_AFTER=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
echo "  NRestarts (post-settle) = $NR_AFTER"
[ "$NR_AFTER" = "$NR_BEFORE" ] || { echo "✗ NRestarts changed during the settle window ($NR_BEFORE → $NR_AFTER) — the unit is still crash-looping, not alive-idle" >&2; exit 1; }
echo "  ✓ NRestarts bounded ($NR_BEFORE) and frozen across the 30s settle window"

echo ""
echo "── assert 3: siren fired exactly once ──"
CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^parked " || { echo "✗ callback line does not carry STATBUS_EVENT=parked" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_EVENT=parked callback fired"

echo ""
echo "── assert 4: flag file still present (parked row keeps it) ──"
VM_EXEC bash -c "ls -la $FLAG_PATH" >/dev/null 2>&1 || { echo "✗ expected flag file present while parked" >&2; exit 1; }
echo "  ✓ flag present"

echo ""
echo "── assert 5: never rolled_back ──"
[ "$ROW_STATE" != "rolled_back" ] || { echo "✗ row state is 'rolled_back' — at-target exhaust must PARK, never roll back (039)" >&2; exit 1; }
echo "  ✓ state was never rolled_back (confirmed in_progress above)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — two EXTRA restarts after park: each must be skipped
# (parked-skip), no attempts increment, no additional siren.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── two extra restarts after park: assert parked-skip, no attempts bump, no re-siren ──"
for i in 1 2; do
    echo "  extra restart #$i..."
    ATTEMPTS_BEFORE=$(recovery_row_cols | cut -d"|" -f2)
    PRE_RESTART_PID=$(daemon_pid)
    VM_EXEC systemctl --user restart "$UPGRADE_UNIT" 2>/dev/null || true
    wait_for_restart "$RESTART_WAIT_BUDGET_S" "$PRE_RESTART_PID"
    # Give the daemon a moment to run its boot sequence (recoverFromFlag →
    # resumePostSwap → parked-skip → return) before reading state.
    sleep 5
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 60 2>/dev/null" || echo "")
    echo "$JOURNAL_TAIL" | grep -q "is PARKED.*skipping automatic resume" || {
        echo "✗ extra restart #$i: journal does not show the parked-skip log line" >&2
        echo "$JOURNAL_TAIL" | tail -20 >&2
        exit 1
    }
    echo "  ✓ extra restart #$i logged the parked-skip line"
    ATTEMPTS_AFTER=$(recovery_row_cols | cut -d"|" -f2)
    [ "$ATTEMPTS_AFTER" = "$ATTEMPTS_BEFORE" ] || {
        echo "✗ extra restart #$i: recovery_attempts changed ($ATTEMPTS_BEFORE → $ATTEMPTS_AFTER) — a parked-skip must NOT consume an attempt" >&2
        exit 1
    }
    echo "  ✓ extra restart #$i: recovery_attempts unchanged ($ATTEMPTS_AFTER)"
done
CALLBACK_COUNT_AFTER=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_AFTER" = "1" ] || { echo "✗ callback fired again across the extra restarts (count=$CALLBACK_COUNT_AFTER, expected still 1)" >&2; exit 1; }
echo "  ✓ siren still fired exactly once across both extra restarts"

# ─────────────────────────────────────────────────────────────────────────
# Phase 9 — UN-PARK via the install arm (spec item 6, preferred terminal:
# the fresh attempt COMPLETES, proving the park/un-park cycle left the
# pipeline undamaged). The kill-gate is already lifted — nothing in this
# script kills the daemon again — so this fresh attempt runs to completion.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── un-park via ./sb install (deliberate operator trigger) ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install (un-park) exit: $INSTALL_RC"
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ un-park install did not exit 0 (expected the fresh attempt to complete cleanly since the kill-gate is lifted)" >&2; exit 1; }

grep -qE "UN-PARKED upgrade id=[0-9]+" "$INSTALL_OUT" || {
    echo "✗ expected the 'UN-PARKED upgrade id=N' line in ./sb install's output" >&2
    exit 1
}
echo "  ✓ install logged the UN-PARKED line"
rm -f "$INSTALL_OUT"

echo ""
echo "── assert un-park + fresh-attempt convergence ──"
ROW=$(recovery_row_cols)
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_PARKED=$(echo "$ROW" | cut -d'|' -f3)
echo "  post-unpark row: $ROW"

[ "$ROW_PARKED" = "f" ] || { echo "✗ expected recovery_parked_at IS NULL after un-park, still parked" >&2; exit 1; }
echo "  ✓ parked_at cleared"

# Exactly ONE fresh attempt: UnparkByID resets recovery_attempts to 0, then
# the fresh resume increments it to 1.
[ "$ROW_ATTEMPTS" = "1" ] || { echo "✗ expected recovery_attempts==1 after the fresh un-parked attempt, got $ROW_ATTEMPTS" >&2; exit 1; }
echo "  ✓ recovery_attempts==1 (exactly one fresh attempt)"

[ "$ROW_STATE" = "completed" ] || { echo "✗ expected the un-parked fresh attempt to reach 'completed' (kill-gate was lifted), got '$ROW_STATE'" >&2; exit 1; }
echo "  ✓ terminal state == 'completed' — the park/un-park cycle did NOT damage the pipeline"

assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo ""
echo "PASS: 3-postswap-resume-died-parked (two same-step deaths at migrate-up PARKED the upgrade — alive-idle, NRestarts bounded+frozen, siren fired exactly once including two extra skipped restarts, never rolled_back — then ./sb install UN-PARKED it for exactly one fresh attempt, which COMPLETED cleanly, proving the pipeline is undamaged by the park/un-park cycle)"
