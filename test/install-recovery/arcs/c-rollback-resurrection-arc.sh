#!/bin/bash
# Arc: c-rollback-resurrection  (STATBUS-071 coverage map — the row AFTER
# postswap-health-park; architect-ruled 2026-07-15, STATBUS-160 package).
#
# THE STORY (a fix release fails and rolls back onto the displaced version):
#   A install → B (healthpark lineage) parks AT-TARGET on the health leg → C (a
#   fix release) is scheduled → C DISPLACES the parked B at claim (B → superseded,
#   STATBUS-159) → C swaps in and its migration V3 RAISES → the daemon ROLLS C back
#   onto B → C terminal 'rolled_back', the box left running B → the operator runs
#   `./sb install`.
# The leg PROVES: `./sb install` does NOT resurrect the superseded B through any
# door (the deleted reconciler, the narrowed install upsert, the terminal-
# resurrection DB trigger). B stays superseded, C stays rolled_back, the state log
# shows NO terminal→completed transition, install exits 0, and the truth is still
# told: the box observably runs B while the ledger carries no completed-B row.
#
# THE DOCTRINE (architect ruling on STATBUS-160, 2026-07-12): 'completed' means
# THIS VERSION VERIFIABLY SERVES — only serve-proven writers may write it. The
# running-but-unrecorded version is an OBSERVED FACT, NEVER A LEDGER EDIT. So the
# ledger honestly does NOT claim B completed (C was B's fix; C failed; the box runs
# broken B and the remedy is re-dispatching a real fix — the standing healthpark
# story, proven by run 29171998401). The map's "the refuse names the re-dispatch
# remedy" = the terminal-resurrection TRIGGER's RAISE; the real path never triggers
# it (the doors are closed), so this arc observes it via a GUARD-PROBE (below).
#
# WHY BROKEN-B IS THE INTENDED END STATE, VERIFIED NO-RED (architect, 2026-07-15):
# the healthpark break is an app-function RAISE inside auth_status — read by the
# UPGRADE health gate, NOT by install. `./sb install`'s only health gate is
# checkServicesDone (cli/cmd/install.go:846), which reads the DB CONTAINER's docker
# health; postgres is healthy under the healthpark lineage, so install exits 0 on
# broken-B — refreshing config and papering over NOTHING (it neither fails on nor
# falsely blesses the broken app). App health stays red as the honest truth.
#
# THE GUARD-PROBE (architect-sanctioned genre, 2026-07-15): "try the locked handle,
# assert it's locked" is NOT fabrication — the state (B superseded, C rolled_back)
# arose via the REAL path end to end; the probe ATTEMPTS the forbidden terminal→
# completed write and is REFUSED; nothing downstream consumes probe-produced state
# (none is produced). Same genre as the house pg_regress constraint tests (attempt
# the duplicate, expect ERROR). THREE CONDITIONS, all honored below: (1) it runs
# AFTER every real-path assert; (2) it asserts BOTH halves — the RAISE names the
# re-dispatch remedy AND B's row is byte-unchanged after; (3) it is labeled
# GUARD-PROBE, visually distinct from the real-path narrative.
#
# Lineage: crollback (construct_upgrade_target) — B byte-identical to healthpark's
# B (V1 benign + V2 breaks auth_status), C = B + a NEW FAILING V3 (RAISES).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, C_FULL, C_BRANCH, B_SHORT.
# VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-c-rollback-resurrection}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-600}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-1200}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${C_FULL:?C_FULL required}"
: "${C_BRANCH:?C_BRANCH required}"
: "${B_SHORT:?B_SHORT required - the park-reason regex names B short SHA}"
# V2/V3 arrive via the run-arc job env (deterministic from BASE_SHA's migrations);
# require them here so a manual invocation fails fast, not mid-arc (set -u).
: "${V_VERSION_2:?V_VERSION_2 required - B's at-target anti-vacuity reads it}"
: "${V_VERSION_3:?V_VERSION_3 required - C's not-applied assert reads it}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

UPGRADE_UNIT="statbus-upgrade@statbus.service"

# _dump_crollback_failure_diagnostics — on ANY non-zero exit, pull the B+C rows +
# the daemon journal + both state-logs + git HEAD to STDERR before cleanup reaps
# the VM. Best-effort (mirrors the park-family arcs' STATBUS-155 rider).
_dump_crollback_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B+C rows + journal + state-logs + HEAD) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, commit_sha, recovery_parked_at IS NOT NULL AS parked, recovery_attempts, error FROM public.upgrade WHERE commit_sha IN ('${B_FULL:-}','${C_FULL:-}') ORDER BY id;\" | ./sb psql -x" >&2 || true
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── B's state-log ──" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT logged_at, old_state, new_state, (new_parked_at IS NOT NULL) AS now_parked, application_name FROM public.upgrade_state_log WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1) ORDER BY id;\" | ./sb psql -x" >&2 || true
    echo "── git HEAD + db.migration max ──" >&2
    VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD 2>/dev/null; echo 'SELECT max(version) FROM db.migration;' | ./sb psql -t -A" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_crollback_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: c-rollback-resurrection  (C fails → rolls back onto B → install must NOT resurrect B)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# Transport-aware row reader: id|state|parked|reason (psql failure → "?", never a
# state verdict).
row_cols_for() {
    local sha="$1"
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason,'') FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r' || echo "?|?|?|(db-down)"
}
# Scalar psql reader (psql failure → "?" → a loud miss, never a false pass).
psql_scalar() { VM_EXEC bash -c "cd ~/statbus && echo \"$1\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
# git HEAD on the box — the observed running version (what the box actually runs).
box_head() { VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── B: register + schedule → B parks AT-TARGET on the health leg. Mirrors the
#    proven postswap-health-park B-park (NOT arc_to, whose wait loop treats a
#    parked in_progress row as never-terminal). The park SUBSTRATE (siren, alive-
#    idle, parked-skip) is proven by postswap-health-park; here the park is the
#    MEANS to a displaceable B, so the assert stays tight: parked + health reason
#    naming B + V1/V2 applied (anti-vacuity that B is genuinely at-target). ──
echo ""
dump_daemon_state "before B"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
echo "── register B ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
dump_signing_diagnostics "$B_FULL"
echo "── schedule B (daemon claims + runs executeUpgrade → parks on the health leg) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B's park (recovery_parked_at IS NOT NULL), budget ${PARK_WAIT_BUDGET_S}s ──"
PARK_START=$(date +%s)
while true; do
    ELAPSED=$(( $(date +%s) - PARK_START ))
    ROW=$(row_cols_for "$B_FULL")
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "  ✓ B parked (t+${ELAPSED}s): $ROW"
        break
    fi
    CUR_STATE=$(echo "$ROW" | cut -d'|' -f2)
    case "$CUR_STATE" in
        completed|failed|rolled_back)
            echo "✗ B reached terminal '$CUR_STATE' instead of parking — the health-break construction did not park" >&2
            exit 1
            ;;
    esac
    if [ "$ELAPSED" -ge "$PARK_WAIT_BUDGET_S" ]; then
        echo "✗ B did not park within ${PARK_WAIT_BUDGET_S}s (last: $ROW)" >&2
        exit 1
    fi
    sleep 5
done

echo ""
echo "── assert B park: in_progress + parked, health-past-warmup reason names ${B_SHORT}, V1+V2 applied ──"
ROW=$(row_cols_for "$B_FULL")
B_ROW_ID=$(echo "$ROW" | cut -d'|' -f1)
B_PARK_STATE=$(echo "$ROW" | cut -d'|' -f2)
B_PARK_REASON=$(echo "$ROW" | cut -d'|' -f4)
[[ "$B_ROW_ID" =~ ^[0-9]+$ ]] || { echo "✗ could not read B's row id (got '$B_ROW_ID')" >&2; exit 1; }
[ "$B_PARK_STATE" = "in_progress" ] || { echo "✗ expected B state='in_progress' while parked, got '$B_PARK_STATE'" >&2; exit 1; }
echo "$B_PARK_REASON" | grep -qE "HEALTHCHECK_REST_DOWN: the application cannot serve at ${B_SHORT} past warmup" || { echo "✗ B's park reason is not the health-past-warmup reason naming ${B_SHORT}: $B_PARK_REASON" >&2; exit 1; }
# Anti-vacuity: V1+V2 genuinely applied → B is genuinely AT-TARGET (the whole
# premise: a delta-carrying-but-at-target box, so the later fix release's rollback
# lands the box back on a real B state, not a no-op).
B_DBMAX=$(psql_scalar "SELECT max(version) FROM db.migration;")
[ "$B_DBMAX" = "${V_VERSION_2}" ] || { echo "✗ B is not at-target: db.migration max=$B_DBMAX, expected V2=${V_VERSION_2} (V1+V2 both applied)" >&2; exit 1; }
echo "  B parked (id=$B_ROW_ID), health reason names ${B_SHORT}, db.migration max=$B_DBMAX (V2)"
echo "  ✓ B at-target park landed (V1+V2 applied)"

# ── C: register + schedule while B sits parked. C displaces B at claim (STATBUS-159
#    → B superseded), swaps in, V3 RAISES, the daemon rolls C back onto B. arc_to
#    drives C to its ruled terminal 'rolled_back'. ──
arc_to "$C_FULL" "$C_BRANCH" "C (fix release that DISPLACES B then FAILS post-swap)" rolled_back

# ── assert the displacement (reuses the postswap-health-park STATBUS-159 oracle):
#    B superseded, park marker cleared, park narrative + displacement note in error,
#    the 154 state-log records exactly one in_progress→superseded (parked→NULL). ──
echo ""
echo "── assert STATBUS-159 displacement: B superseded with its story intact ──"
B_STATE=$(psql_scalar "SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[ "$B_STATE" = "superseded" ] || { echo "✗ B did not land 'superseded' after C's claim displaced it (got '$B_STATE')" >&2; exit 1; }
B_PARKED=$(psql_scalar "SELECT (recovery_parked_at IS NOT NULL) FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[ "$B_PARKED" = "f" ] || { echo "✗ B's recovery_parked_at was not cleared by the displacement (parked='$B_PARKED')" >&2; exit 1; }
B_ERR_PARK=$(psql_scalar "SELECT (error LIKE '%parked on deterministic forward failure%')::int FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[ "$B_ERR_PARK" = "1" ] || { echo "✗ B's park narrative was NOT preserved in error after displacement (LIKE match='$B_ERR_PARK')" >&2; exit 1; }
B_ERR_DISP=$(psql_scalar "SELECT (error LIKE '%displaced by %claim%')::int FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[ "$B_ERR_DISP" = "1" ] || { echo "✗ B's error is missing the displacement note (LIKE match='$B_ERR_DISP')" >&2; exit 1; }
DISP_LOG=$(psql_scalar "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1) AND old_state = 'in_progress' AND new_state = 'superseded' AND old_parked_at IS NOT NULL AND new_parked_at IS NULL;")
[ "$DISP_LOG" = "1" ] || { echo "✗ the 154 state-log does not show exactly one displacement transition for B (got '$DISP_LOG')" >&2; exit 1; }
echo "  ✓ B superseded, park marker cleared, park narrative + displacement note in error, one 154 displacement row"

# ── assert C rolled back onto B: C 'rolled_back' (arc_to already ruled it), and the
#    box is on B — db.migration max is B's V2, NOT C's V3 (C's V3 rolled back), and
#    git HEAD reconciled to B. ──
echo ""
echo "── assert C rolled back onto B: C rolled_back, box's DB + tree back on B ──"
C_STATE=$(psql_scalar "SELECT state FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;")
[ "$C_STATE" = "rolled_back" ] || { echo "✗ C is not 'rolled_back' (got '$C_STATE')" >&2; exit 1; }
V3_APPLIED=$(psql_scalar "SELECT count(*) FROM db.migration WHERE version = ${V_VERSION_3};")
[ "$V3_APPLIED" = "0" ] || { echo "✗ C's failing V3 (${V_VERSION_3}) is recorded in db.migration (count=$V3_APPLIED) — it must have rolled back, not applied" >&2; exit 1; }
DBMAX_AFTER_C=$(psql_scalar "SELECT max(version) FROM db.migration;")
[ "$DBMAX_AFTER_C" = "${V_VERSION_2}" ] || { echo "✗ db.migration max is $DBMAX_AFTER_C, expected B's V2=${V_VERSION_2} — the box's DB is not on B" >&2; exit 1; }
HEAD_AFTER_C=$(box_head)
[ "$HEAD_AFTER_C" = "$B_FULL" ] || { echo "✗ git HEAD is $HEAD_AFTER_C, expected B ($B_FULL) — the rollback did not reconcile the tree to B" >&2; exit 1; }
echo "  ✓ C rolled_back; box's DB at B's V2 (${V_VERSION_2}), C's V3 not applied, git HEAD == B"

# ── operator runs `./sb install` — StateNothingScheduled: config refresh, no row
#    authored, no upsert of B. Must exit 0 (postgres healthy; broken auth_status is
#    invisible to install's docker-health gate). ──
echo ""
echo "── operator runs ./sb install (StateNothingScheduled; must NOT resurrect B, exit 0) ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
rm -f "$INSTALL_OUT"
echo "  ./sb install exit: $INSTALL_RC"
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ ./sb install exited $INSTALL_RC — expected 0 (config refresh on a docker-healthy box; it must not fail on the broken app)" >&2; exit 1; }
echo "  ✓ install exited 0 (papered over nothing, resurrected nothing)"

# ── REAL-PATH END-STATE ASSERTS (all before the guard-probe). ──
echo ""
echo "── real-path end state: B still superseded, C still rolled_back, no terminal→completed, truth still told ──"
# Door check: B stays superseded through install (no reconciler / no upsert resurrected it).
B_STATE_FINAL=$(psql_scalar "SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[ "$B_STATE_FINAL" = "superseded" ] || { echo "✗ B is no longer 'superseded' after install (got '$B_STATE_FINAL') — a door resurrected it" >&2; exit 1; }
C_STATE_FINAL=$(psql_scalar "SELECT state FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;")
[ "$C_STATE_FINAL" = "rolled_back" ] || { echo "✗ C is no longer 'rolled_back' after install (got '$C_STATE_FINAL')" >&2; exit 1; }
# NO terminal→completed transition anywhere on B's row (the state-log audits every write).
TERM_TO_COMPLETED=$(psql_scalar "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1) AND old_state IN ('superseded','failed','rolled_back','skipped','dismissed') AND new_state = 'completed';")
[ "$TERM_TO_COMPLETED" = "0" ] || { echo "✗ B's state-log shows $TERM_TO_COMPLETED terminal→completed transition(s) — a resurrection landed" >&2; exit 1; }
# POSITIVE HALF (the 160 story's truth-is-told): the box observably runs B while the
# ledger carries NO completed-B row. (Observed-version = git HEAD, the ground truth
# of what runs; the ledger deliberately does not record it — an observation, never a
# ledger edit.)
HEAD_FINAL=$(box_head)
[ "$HEAD_FINAL" = "$B_FULL" ] || { echo "✗ observed running version (git HEAD=$HEAD_FINAL) is not B ($B_FULL) after install" >&2; exit 1; }
COMPLETED_B=$(psql_scalar "SELECT count(*) FROM public.upgrade WHERE commit_sha = '$B_FULL' AND state = 'completed';")
[ "$COMPLETED_B" = "0" ] || { echo "✗ the ledger carries $COMPLETED_B completed-B row(s) — B running must remain an OBSERVED fact, never a ledger 'completed'" >&2; exit 1; }
echo "  ✓ B superseded, C rolled_back, zero terminal→completed; box runs B (HEAD==B) with NO completed-B ledger row"

# App health still RED — the honest truth. The healthpark break is in auth_status
# (an app RPC), invisible to install's docker-health gate. PostgREST root (/rest/)
# is up, but /rest/rpc/auth_status 500s under B's V2. That red IS the state (C was
# the fix; C failed; the remedy is a real re-dispatched fix), not a defect.
echo ""
echo "── app health still red (auth_status 500s under broken B — the honest truth) ──"
AUTH_CODE=$(VM_EXEC bash -c "curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:${HEALTH_PORT:-3010}/rest/rpc/auth_status -H 'Content-Type: application/json' -d '{}'" 2>/dev/null | tr -d ' \r\n' || echo "000")
[ "$AUTH_CODE" = "500" ] || { echo "✗ /rest/rpc/auth_status returned $AUTH_CODE, expected 500 — broken-B is the intended honest end state (auth_status must still RAISE)" >&2; exit 1; }
echo "  ✓ auth_status 500s — the box honestly runs broken B; the remedy is a real re-dispatched fix"

# Data intact throughout.
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
echo "  ✓ data intact across the whole leg"

# ─────────────────────────────────────────────────────────────────────────
# GUARD-PROBE (architect-sanctioned; runs AFTER every real-path assert above).
# Try the locked handle: attempt the forbidden terminal→completed write on B's
# superseded row. Assert BOTH halves: (1) the trigger RAISEs, naming the
# re-dispatch remedy; (2) B's row is BYTE-UNCHANGED after the refused write
# (still superseded, story intact). Nothing downstream consumes probe state —
# the write is refused, so none is produced.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── GUARD-PROBE: attempt superseded→completed on B (must be refused, row untouched) ──"
# Capture B's row fingerprint BEFORE the probe (state + parked + a hash of error).
B_FP_BEFORE=$(psql_scalar "SELECT state || '|' || (recovery_parked_at IS NOT NULL)::text || '|' || md5(COALESCE(error,'')) FROM public.upgrade WHERE id = $B_ROW_ID;")
PROBE_OUT=$(mktemp)
cat > /tmp/crollback-guard-probe.sql <<PROBESQL
\set ON_ERROR_STOP off
UPDATE public.upgrade SET state = 'completed' WHERE id = ${B_ROW_ID};
PROBESQL
scp -O "${SSH_OPTS[@]}" /tmp/crollback-guard-probe.sql statbus@"$(hcloud server ip "$VM_NAME")":/tmp/crollback-guard-probe.sql >/dev/null
rm -f /tmp/crollback-guard-probe.sql
VM_EXEC bash -c "cd ~/statbus && ./sb psql < /tmp/crollback-guard-probe.sql" > "$PROBE_OUT" 2>&1 || true
echo "  guard-probe output:"; sed 's/^/    /' "$PROBE_OUT"
# Half 1: the trigger RAISEd, naming the re-dispatch remedy.
grep -q "terminal rows are not resurrectable" "$PROBE_OUT" || { echo "✗ GUARD-PROBE: the trigger did not RAISE the terminal-resurrection refusal" >&2; rm -f "$PROBE_OUT"; exit 1; }
grep -q "re-dispatch via ./sb upgrade schedule" "$PROBE_OUT" || { echo "✗ GUARD-PROBE: the refusal does not name the re-dispatch remedy" >&2; rm -f "$PROBE_OUT"; exit 1; }
rm -f "$PROBE_OUT"
# Half 2: B's row is byte-unchanged (the refused write touched nothing).
B_FP_AFTER=$(psql_scalar "SELECT state || '|' || (recovery_parked_at IS NOT NULL)::text || '|' || md5(COALESCE(error,'')) FROM public.upgrade WHERE id = $B_ROW_ID;")
[ "$B_FP_AFTER" = "$B_FP_BEFORE" ] || { echo "✗ GUARD-PROBE: B's row changed after the refused write (before='$B_FP_BEFORE' after='$B_FP_AFTER') — the refusal must leave it byte-unchanged" >&2; exit 1; }
echo "  ✓ GUARD-PROBE: trigger refused naming re-dispatch; B's row byte-unchanged (still superseded, story intact)"

echo ""
echo "PASS: c-rollback-resurrection — a real fix release C displaced the parked at-target B (superseded, story intact), then FAILED post-swap and rolled back onto B (C rolled_back; box's DB at B's V2, git HEAD==B). The operator's ./sb install exited 0 and resurrected B through NO door: B stayed superseded, C stayed rolled_back, the state log shows zero terminal→completed, and the truth is still told — the box observably runs B with no completed-B ledger row while app health honestly stays red. The GUARD-PROBE confirmed the terminal-resurrection trigger refuses the forbidden write naming the re-dispatch remedy, leaving B's row byte-unchanged. Data intact throughout. (STATBUS-160 non-resurrection proven end-to-end; arm the fix by re-dispatching a real C2 — the standing healthpark completion story, run 29171998401.)"
