#!/bin/bash
# Arc: postswap-health-park  (STATBUS-145, doc-029 Rev 2 — the real-path B-class
# at-target park: the delta applies cleanly, the new version cannot serve past
# warmup, so the upgrade PARKS on FIRST occurrence — never same-step-twice, never
# a kill/restart loop. Real register+schedule path, zero fabrication.)
#
# REPLACES the fabricated scenario 3-postswap-resume-died-parked.sh as the proof
# of the park SUBSTRATE (row state, siren-once, alive-idle, parked-skip, un-park).
# That file targeted the D-class guard park (same-step-twice at boot-migrate) —
# under the STATBUS-145 minimal-boot-migrate geometry that class has NO on-cue
# real-path construction left (see doc-029's "finding that shapes this spec"): a
# pre-delta death now hits the atomicity flip (rollback at pass 2, no park) and a
# post-delta death on a healthy box self-heals (completed, no park). The ONLY
# live park class an Albania box will actually hit is THIS one — B-class,
# at-target, first-occurrence. The fabricated file STAYS as the D-class guard's
# regression net (unit-tested + r19-historically-proven) until this arc is green,
# per doc-029's "never delete proof coverage before its replacement is proven".
#
# CONSTRUCTION (doc-029 Rev 2, upgrade-target.sh SPEC=healthpark):
#   B = A + V1 (V_marker, benign fixture-table migration, always succeeds)
#         + V2 (CREATE OR REPLACE FUNCTION public.auth_status() to RAISE —
#           itself a SUCCESSFUL migration; the box is genuinely at-target when
#           the park fires).
#   C = B + V3 (a NEW, higher-version migration restoring auth_status() to its
#         original body). V1/V2 stay byte-identical between B and C.
#
# REV 2 CORRECTION (credited to this file's own map-before-build trace): Rev 1
# sketched "C = B with the app change reverted" as an in-place edit to V2 (mirror
# the "working" spec's own C-construction: same version, new bytes). That is
# ILLEGAL here — V2 SUCCEEDED, so it is an already-applied, immutable migration;
# on a release-channel box (these harness VMs: CADDY_DEPLOYMENT_MODE=standalone →
# UPGRADE_CHANNEL defaults "stable" → migrationChannelClass=channelRelease),
# migrate.go's content_hash mismatch handler for channelRelease BLESSES (re-stamps,
# never re-runs — migrate.go:1662-1685) an in-place edit, so auth_status would stay
# broken forever and step 5 below would wedge for an unrelated-looking reason. The
# fix ships as V3 instead — a brand-new version has no existing db.migration row,
# so it applies via the normal pending-migrations path, never touching
# content_hash/channel-bless at all. This is also the more faithful Albania shape:
# real fixes ship as new migrations, not edited history.
#
# WHY THE BREAK LANDS PAST WARMUP, NOT AT IT (mechanic trace, cli/internal/upgrade/
# exec.go): d.healthCheck first calls waitForRestReady, which polls PostgREST's
# ADMIN /ready endpoint (REST_ADMIN_BIND_ADDRESS) — this only needs the connection
# pool + schema cache loaded, and does NOT execute any function body, so it stays
# green even with auth_status broken. THEN healthCheck POSTs to /rpc/auth_status
# (healthURL, a DIFFERENT bind: REST_BIND_ADDRESS). Once V2 lands, every call to
# that RPC 500s (5 retries × 5s interval, ~20-25s) → healthCheck returns an error →
# parkForDeterministicFailure (service.go:5087) fires. It FIRST checks the observed
# state (verifyUpgradeObservedStateEx) — ObservedCannotReachNew would route to a
# ROLLBACK instead — but since V1+V2 both genuinely COMMITTED (no crash, no SQL
# error), the observed state reads positively at-target, so this parks, never
# rolls back. Matches doc-029's "B-class at-target park" exactly.
#
# THE PARKED-SKIP MARKER (doc-029 Rev 2, mechanic-trace-verified — read before
# touching the extra-restart assertion below): TWO lines fire on every restart of
# a parked row, not one. RecoveryBudgetGuard (service.go:5814) is class-agnostic —
# it checks upgradeParkedReason() unconditionally for ANY service-held forward-
# recovery flag and, if parked, logs "is PARKED — skipping boot migrate" (service.
# go:5876) before resumePostSwap ever runs. That line is NOT the marker this arc
# asserts (it fires for D-class parks too, and under 145 it is otherwise a no-op
# comment on an already-no-op boot-migrate step). The marker for an AT-TARGET park
# is resumePostSwap's OWN check (service.go:6238-6246), which logs "resumePostSwap:
# upgrade %d is PARKED (%s) — skipping automatic resume" (service.go:6242) — this
# is the line the fabricated scenario's D-class equivalent never had to
# distinguish (there, the guard's own line WAS the semantically-correct marker,
# since that class parks INSIDE the guard, before resumePostSwap ever runs).
#
# STATBUS-147 — THE DAEMON STAYS ALIVE ACROSS A RE-PARK (this arc is the ticket's
# standing oracle). `./sb install`'s crash-recovery (runCrashRecovery) quiesces
# the daemon unit FIRST (stopRestartUpgradeUnit) and used to restart it ONLY via
# a closure gated on `recovered==true` — set true only after svc.RecoverFromFlag
# returned with NO error. That gate predates the park regime: on a re-park (this
# arc's construction guarantees it — B is still broken), RecoverFromFlag returns
# the park error, and the pre-147 code left the unit INACTIVE until an operator
# manually started it. STATBUS-147's fix (cli/cmd/install_upgrade.go's
# shouldRestartAfterFailedRecovery): after a failed recovery, re-read the row's
# park state; PARKED → restart the unit anyway (parked-skip makes every future
# boot alive-idle by construction, and the daemon is the only delivery channel
# for the eventual fix release — schedule → NOTIFY → daemon claim needs it up);
# any OTHER failure keeps the conservative no-restart arm. install's own non-zero
# exit is unchanged either way (the attempt did fail) — only the unit's aliveness
# changes. This arc asserts the unit is ACTIVE immediately after the re-park,
# proving the fix rather than working around its absence.
#
# Real path throughout (the 118 constructor: real branches + CI images via
# arc-helpers.sh's arc_prepare_box for A, register+schedule for B, arc_to for C).
# arc_to is NOT used for B: its wait loop only recognizes completed/failed/
# rolled_back as terminal, and a parked row stays in_progress forever — same
# reasoning the oom/ceiling arcs already documented for their own midpoint-kill
# needs. B's register/schedule steps are replicated inline; the wait loop below
# polls recovery_parked_at IS NOT NULL instead.
#
# Inputs (env): BASE_SHA, B_FULL/B_BRANCH/B_SHORT, C_FULL/C_BRANCH (40-hex/branch
#   names from construct_upgrade_target SPEC=healthpark), V_VERSION/V_VERSION_2/
#   V_VERSION_3, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-health-park}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-1200}"
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
UPGRADE_UNIT="statbus-upgrade@statbus.service"
CALLBACK_LOG="/tmp/health-park-callback-log.txt"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${B_SHORT:?B_SHORT required}"
: "${C_FULL:?C_FULL required}"
: "${C_BRANCH:?C_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"
: "${V_VERSION_2:?V_VERSION_2 required}"
: "${V_VERSION_3:?V_VERSION_3 required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

# _dump_health_park_failure_diagnostics — STATBUS-148 AC#4 harness rider: on
# ANY non-zero exit, pull B's own upgrade progress log (the per-upgrade file
# named by public.upgrade.log_relative_file_path — where healthCheck's own
# "Health check attempt N/M failed" lines land) + the daemon journal, to
# STDERR, BEFORE cleanup_vm reaps the VM. The wave-1 autopsy of this exact arc
# had ZERO "Health check attempt" lines in the captured log — only a code
# trace (not the run) settled what actually happened — because nothing had
# ever pulled B's own progress log at all. One capture here makes any future
# red self-sufficient without needing a kept VM. Best-effort throughout
# (|| true) — a diagnostics failure must never mask the real assertion error
# that triggered this trap.
_dump_health_park_failure_diagnostics() {
    echo "" >&2
    echo "══════════ STATBUS-148 AC#4: failure diagnostics (B's progress log + daemon journal) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_health_park_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-health-park  (STATBUS-145 doc-029 Rev 2 — B-class at-target park, real path)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# ── row readers — TRANSPORT-AWARE (a psql failure reads as "unknown", never a
# state verdict; mirrors the oom/ceiling arcs' own row_state/row_error shape). ──
row_cols_for() {
    local sha="$1"
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, recovery_attempts, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason,'') FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r' || echo "?|?|?|(db-down)"
}
daemon_pid() {
    VM_EXEC bash -c 'pgrep -f "sb upgrade service" 2>/dev/null | head -1' 2>/dev/null | tr -d ' \r\n'
}
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

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ─────────────────────────────────────────────────────────────────────────
# Configure the park-callback (siren) via .env.config ONLY (STATBUS-131 AC#3 —
# survives every `sb config generate` from here on). Callback script transferred
# as a FILE (never inline through VM_EXEC — the sudo -i re-quoting layer silently
# eats bare $VARNAME references; see the retiring fabricated scenario's r13
# autopsy for the two bugs this exact pattern fixes).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── writing the park-callback script (transferred as a FILE) ──"
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/sh
echo "\$STATBUS_EVENT \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/health-park-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    'mv /tmp/health-park-callback.sh /home/statbus/health-park-callback.sh && chown statbus:statbus /home/statbus/health-park-callback.sh && chmod 0755 /home/statbus/health-park-callback.sh'
echo "  ✓ /home/statbus/health-park-callback.sh installed (chmod 0755)"

VM_EXEC bash -c "rm -f $CALLBACK_LOG"
# Same trailing-newline guard the fabricated scenario needed: .env.config's last
# written line has no trailing \n, so a naive >> glues onto it.
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/health-park-callback.sh\n" >> .env.config'
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env" || { echo "✗ UPGRADE_CALLBACK did not land in .env after config generate" >&2; exit 1; }
echo "  ✓ UPGRADE_CALLBACK configured (survives config generate — runCallback reads .env fresh at fire time, no unit restart needed for this alone)"

# ─────────────────────────────────────────────────────────────────────────
# Register + schedule B — real Albania path (register+schedule; the daemon
# claims and runs executeUpgrade on its own). Mirrors arc_to's own register/
# schedule steps verbatim (arc-helpers.sh); NOT calling arc_to itself because
# its wait loop only recognizes completed/failed/rolled_back as terminal — a
# parked row stays in_progress forever.
# ─────────────────────────────────────────────────────────────────────────
echo ""
dump_daemon_state "before B"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
echo "── register B ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
dump_signing_diagnostics "$B_FULL"
echo "── schedule B (DB trigger → daemon claims + runs executeUpgrade) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ─────────────────────────────────────────────────────────────────────────
# Wait for the PARK (recovery_parked_at IS NOT NULL). This single register+
# schedule dispatch runs claim → checkout → exit-42 handoff restart → resume →
# applyPostSwap (V1+V2 apply at 3.5) → services up → health leg fails past
# warmup → park, ALL within one continuous sequence — no kill/restart needed
# from this arc (unlike oom/ceiling, which inject an external SIGKILL; this
# class parks entirely on its own from a genuinely healthy-until-now box).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for park (recovery_parked_at IS NOT NULL), budget ${PARK_WAIT_BUDGET_S}s ──"
PARK_START=$(date +%s)
while true; do
    ELAPSED=$(( $(date +%s) - PARK_START ))
    ROW=$(row_cols_for "$B_FULL")
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "  ✓ B parked (t+${ELAPSED}s): $ROW"
        break
    fi
    # A DIFFERENT terminal reached first means this construction did not park —
    # fail fast rather than let the loop run out the whole budget.
    CUR_STATE=$(echo "$ROW" | cut -d'|' -f1)
    case "$CUR_STATE" in
        completed|failed|rolled_back)
            echo "✗ B reached terminal '$CUR_STATE' instead of parking — the health-break construction did not deterministically fail (or something else diverged)" >&2
            exit 1
            ;;
    esac
    if [ "$ELAPSED" -ge "$PARK_WAIT_BUDGET_S" ]; then
        echo "✗ B did not park within ${PARK_WAIT_BUDGET_S}s (last: $ROW)" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# ASSERT PARK SUBSTRATE (doc-029 Rev 2 step 3 — the r19 spec, carried over)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── assert 1: row state + reason (health-past-warmup, names B's short SHA) ──"
ROW=$(row_cols_for "$B_FULL")
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_REASON=$(echo "$ROW" | cut -d'|' -f4)
echo "  state=$ROW_STATE attempts=$ROW_ATTEMPTS reason=$ROW_REASON"
[ "$ROW_STATE" = "in_progress" ] || { echo "✗ expected state='in_progress' while parked, got '$ROW_STATE'" >&2; exit 1; }
echo "$ROW_REASON" | grep -qE "HEALTHCHECK_REST_DOWN: the application cannot serve at ${B_SHORT} past warmup" || {
    echo "✗ recovery_parked_reason does not match the health-past-warmup pattern for ${B_SHORT}" >&2
    echo "  actual: $ROW_REASON" >&2
    exit 1
}
echo "  ✓ reason matches health-past-warmup, names ${B_SHORT}"

echo ""
echo "── midpoint anti-vacuity: V1+V2 genuinely applied (the box is genuinely at-target) ──"
[ "$(migration_row_count)" = "1" ] || { echo "✗ V1 (V_VERSION=$V_VERSION) not recorded exactly once in db.migration" >&2; exit 1; }
V2ROWS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = ${V_VERSION_2};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR")
[ "$V2ROWS" = "1" ] || { echo "✗ V2 (V_VERSION_2=$V_VERSION_2, the health-break migration) not recorded exactly once in db.migration (got $V2ROWS)" >&2; exit 1; }
FIXTURE_COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_healthpark_fixture WHERE id = 1 AND note = 'healthpark';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
[ "$FIXTURE_COUNT" = "1" ] || { echo "✗ public.upgrade_arc_healthpark_fixture missing its row (count=$FIXTURE_COUNT) — V1 did not fully execute" >&2; exit 1; }
echo "  ✓ V1 (fixture) + V2 (health-break) both recorded in db.migration; fixture row present"

echo ""
echo "── assert 2: unit alive-idle, NRestarts BOUNDED and FROZEN across a settle window ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
NR_BEFORE=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
echo "  NRestarts (pre-settle) = $NR_BEFORE"
[[ "$NR_BEFORE" =~ ^[0-9]+$ ]] || { echo "✗ could not parse NRestarts (got '$NR_BEFORE')" >&2; exit 1; }
# Bound, never pin (anti-assertion, doc-029): only the planned exit-42 handoff
# restart should have happened before this first, on-its-own park (unlike the
# oom/ceiling arcs' external kills, nothing else restarts this process). Small
# headroom margin, not the multi-kill bound the retiring D-class scenario used.
[ "$NR_BEFORE" -le 3 ] || { echo "✗ NRestarts=$NR_BEFORE exceeds the bound of 3 — unexpected restart activity before the first park" >&2; exit 1; }
sleep 30
NR_AFTER=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
[ "$NR_AFTER" = "$NR_BEFORE" ] || { echo "✗ NRestarts changed during the settle window ($NR_BEFORE → $NR_AFTER) — the unit is still crash-looping, not alive-idle" >&2; exit 1; }
echo "  ✓ NRestarts bounded ($NR_BEFORE) and frozen across the 30s settle window"

echo ""
echo "── assert 3: siren fired exactly once ──"
CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^parked " || { echo "✗ callback line does not carry STATBUS_EVENT=parked" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_EVENT=parked callback fired"

echo ""
echo "── assert 4: flag file still present (parked row keeps it) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null 2>&1 || { echo "✗ expected flag file present while parked" >&2; exit 1; }
echo "  ✓ flag present"

echo ""
echo "── assert 5: never rolled_back ──"
[ "$ROW_STATE" != "rolled_back" ] || { echo "✗ row state is 'rolled_back' — at-target exhaust must PARK, never roll back (F1)" >&2; exit 1; }
echo "  ✓ state was never rolled_back"

# ─────────────────────────────────────────────────────────────────────────
# Two EXTRA restarts after park: assert each logs resumePostSwap's OWN
# parked-skip line (service.go:6242), NOT RecoveryBudgetGuard's boot-migrate
# line (service.go:5876 — that ALSO fires, class-agnostically, but is not the
# marker for an at-target park; see the header note). No attempts bump, no
# re-siren.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── two extra restarts after park: assert the resumePostSwap parked-skip line, no attempts bump, no re-siren ──"
for i in 1 2; do
    echo "  extra restart #$i..."
    ATTEMPTS_BEFORE=$(row_cols_for "$B_FULL" | cut -d'|' -f2)
    PRE_RESTART_PID=$(daemon_pid)
    VM_EXEC systemctl --user restart "$UPGRADE_UNIT" 2>/dev/null || true
    wait_for_restart "$RESTART_WAIT_BUDGET_S" "$PRE_RESTART_PID"
    sleep 5
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 80 2>/dev/null" || echo "")
    echo "$JOURNAL_TAIL" | grep -q "is PARKED.*skipping automatic resume" || {
        echo "✗ extra restart #$i: journal does not show resumePostSwap's parked-skip line" >&2
        echo "$JOURNAL_TAIL" | tail -30 >&2
        exit 1
    }
    echo "  ✓ extra restart #$i logged the resumePostSwap parked-skip line"
    ATTEMPTS_AFTER=$(row_cols_for "$B_FULL" | cut -d'|' -f2)
    [ "$ATTEMPTS_AFTER" = "$ATTEMPTS_BEFORE" ] || { echo "✗ extra restart #$i: recovery_attempts changed ($ATTEMPTS_BEFORE → $ATTEMPTS_AFTER) — a parked-skip must NOT consume an attempt" >&2; exit 1; }
    echo "  ✓ extra restart #$i: recovery_attempts unchanged ($ATTEMPTS_AFTER)"
done
CALLBACK_COUNT_AFTER=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_AFTER" = "1" ] || { echo "✗ callback fired again across the extra restarts (count=$CALLBACK_COUNT_AFTER, expected still 1)" >&2; exit 1; }
echo "  ✓ siren still fired exactly once across both extra restarts"

# ─────────────────────────────────────────────────────────────────────────
# Un-park arm 1 (install): ONE fresh attempt with reset budget. B is STILL
# broken (V2's auth_status still RAISEs — nothing in this arm touches the
# migrations), so the fresh attempt's health leg fails past warmup again →
# RE-PARK with a fresh reason and a SECOND siren (doc-029 step 4).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── un-park arm 1: ./sb install (deliberate operator trigger) — B is still broken, expect a FRESH re-park ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install (un-park attempt) exit: $INSTALL_RC"
# NOT exit 0 here (unlike a happy-path un-park): the fresh attempt itself
# re-parks, so RecoverFromFlag returns the park error and install's crash
# recovery propagates it — cobra's default error path maps that to exit 1.
[ "$INSTALL_RC" -ne 0 ] || { echo "✗ ./sb install exited 0 on the un-park attempt — expected a non-zero exit (the fresh attempt should have re-parked, B is still broken)" >&2; exit 1; }

grep -qE "UN-PARKED upgrade id=[0-9]+" "$INSTALL_OUT" || { echo "✗ expected the 'UN-PARKED upgrade id=N' line in ./sb install's output" >&2; exit 1; }
echo "  ✓ install logged the UN-PARKED line"
rm -f "$INSTALL_OUT"

echo ""
echo "── assert re-park: fresh reason, recovery_attempts==1 (exactly one fresh attempt), SECOND siren ──"
ROW=$(row_cols_for "$B_FULL")
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_PARKED=$(echo "$ROW" | cut -d'|' -f3)
ROW_REASON=$(echo "$ROW" | cut -d'|' -f4)
echo "  post-unpark row: $ROW"
[ "$ROW_PARKED" = "t" ] || { echo "✗ expected recovery_parked_at IS NOT NULL after the fresh attempt re-parks, got parked=$ROW_PARKED" >&2; exit 1; }
[ "$ROW_ATTEMPTS" = "1" ] || { echo "✗ expected recovery_attempts==1 after the fresh un-parked attempt (UnparkByID resets to 0, then the fresh consult increments to 1), got $ROW_ATTEMPTS" >&2; exit 1; }
echo "$ROW_REASON" | grep -qE "HEALTHCHECK_REST_DOWN: the application cannot serve at ${B_SHORT} past warmup" || { echo "✗ re-park reason does not match the health-past-warmup pattern: $ROW_REASON" >&2; exit 1; }
echo "  ✓ recovery_attempts==1, still parked, reason matches health-past-warmup"
CALLBACK_COUNT_2=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_2" = "2" ] || { echo "✗ expected exactly 2 callback lines after the re-park (fires-once-PER-EVENT), got $CALLBACK_COUNT_2" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG" >&2 || true; exit 1; }
echo "  ✓ SECOND siren fired (fires-once-per-park-EVENT contract exercised live)"
[ "$ROW_STATE" != "rolled_back" ] || { echo "✗ row state is 'rolled_back' after re-park — at-target exhaust must PARK, never roll back" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────
# STATBUS-147: assert the daemon unit is ACTIVE immediately after the re-park —
# no arc intervention. Pre-147, this arc had to explicitly vm_start_unit here
# (the re-park left the unit stopped); the fix (cli/cmd/install_upgrade.go's
# shouldRestartAfterFailedRecovery) restarts it as part of the product's own
# crash-recovery path, so this arc is now the product assertion, not a
# workaround — and, not incidentally, the precondition step 5 needs: a stopped
# daemon could never claim a newly-scheduled C.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── STATBUS-147: assert the upgrade daemon unit is ACTIVE after the re-park (parked-skip made this safe; the daemon must stay reachable to claim the fix release) ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
echo "  ✓ daemon unit active post-re-park — ready to claim a newly-scheduled C"

# ─────────────────────────────────────────────────────────────────────────
# Step 5 (doc-029 Rev 2, DISCOVERY LEG — dual oracle): register + schedule C
# while B's row sits parked with its flag on disk. The parked-B-row × new-C-
# upgrade interaction (flag on disk, flock free, writeUpgradeFlag's acquire
# against it; the parked row's supersession) is STATICALLY UNDETERMINED — the
# run is the oracle. C's own row (a SEPARATE row, keyed by C_FULL) is what
# arc_to polls; B's row is left to observe, not to hard-assert a specific
# terminal shape for (doc-029: "ANY wedge here is a product finding of the
# highest value, not an arc failure — report it, don't route around it").
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── step 5 (DISCOVERY): register + schedule C while B's row sits parked ──"
echo "  [OBSERVE] B's row just before scheduling C:"
VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_parked_at IS NOT NULL AS parked, recovery_attempts FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql" || true
echo "  [OBSERVE] flag file present: $(VM_EXEC bash -c 'ls -la ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo (absent)')"

arc_to "$C_FULL" "$C_BRANCH" "C (fix release, while B row sits parked with its flag on disk)" completed

echo ""
echo "── post-C-completion observation: B's row final shape (informational — not hard-asserted, per doc-029) ──"
VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_parked_at IS NOT NULL AS parked, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql" || true

echo ""
echo "── assert C's delta {V3} genuinely applied and fixed auth_status: health passes, data intact, no orphan flag ──"
V3ROWS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = ${V_VERSION_3};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR")
[ "$V3ROWS" = "1" ] || { echo "✗ V3 (V_VERSION_3=$V_VERSION_3, the fix migration) not recorded exactly once in db.migration (got $V3ROWS)" >&2; exit 1; }
echo "  ✓ V3 recorded in db.migration — auth_status restored"

assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"

echo ""
echo "PASS: postswap-health-park (a real B-class at-target park — health past warmup, first occurrence, never same-step-twice — proved the full park substrate: alive-idle, NRestarts bounded+frozen, siren exactly once per park-event across an install-driven re-park [daemon unit stays ACTIVE post-re-park, STATBUS-147], resumePostSwap's own parked-skip line across two extra restarts, never rolled_back — then a genuine fix release [C, a NEW migration V3] arrived at the parked box and completed, restoring health with data intact)"
