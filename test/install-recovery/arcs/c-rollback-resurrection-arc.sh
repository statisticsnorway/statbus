#!/bin/bash
# Arc: c-rollback-resurrection  (STATBUS-071 coverage map — the row AFTER
# postswap-health-park; architect-ruled 2026-07-15, STATBUS-160 package).
#
# THE STORY (a fix release fails and rolls back onto the displaced version):
#   A install → B (healthpark lineage) parks AT-TARGET on the health leg → the
#   harness restores only auth_status's canonical body → C is scheduled → C
#   DISPLACES the parked B at claim (B → superseded,
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
# ledger honestly does NOT claim B completed (C failed; the box runs a healthy B
# whose synthetic park-only fault was neutralized before C's snapshot). The map's
# "the refuse names the re-dispatch
# remedy" = the terminal-resurrection TRIGGER's RAISE; the real path never triggers
# it (the doors are closed), so this arc observes it via a GUARD-PROBE (below).
#
# WHY B MUST BE HEALTHY BEFORE C (rc.22 fixture correction): C's rollback restores
# C's own pre-upgrade snapshot, which is post-B/V2. Leaving V2's synthetic
# auth_status RAISE in that snapshot makes the required source functional-health
# gate fail, so C truthfully lands failed rather than rolled_back. The fault exists
# only to create B's park. After that park is proved, this arc restores the shipped
# body without touching B's row or V1/V2 ledger and proves HTTP 200 before C claims.
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
# STATBUS-425 M3a: budget for arc_wait_unit_active after C's rolled_back terminal
# write — one RestartSec=30 auto-restart cycle + boot + margin, mirroring the
# identical budget postswap-health-park-arc.sh/un-park-to-completion-arc.sh
# already use for the SAME auto-restart-hold-off class of wait.
UNIT_ACTIVE_WAIT_BUDGET_S="${UNIT_ACTIVE_WAIT_BUDGET_S:-90}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${C_FULL:?C_FULL required}"
: "${C_BRANCH:?C_BRANCH required}"
: "${B_SHORT:?B_SHORT required - the park-reason regex names B short SHA}"
# V2/V3 arrive via the run-arc job env (deterministic from BASE_SHA's migrations);
# require them here so a manual invocation fails fast, not mid-arc (set -u).
: "${V_VERSION_2:?V_VERSION_2 required - anti-vacuity check for B at target reads it}"
: "${V_VERSION_3:?V_VERSION_3 required - not-applied assertion for C reads it}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"
source "$LIB_DIR/arc-state-assertions.sh"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
C_ARC_PID=""
C_ARC_LOG=""
C_ORIGINAL_LOG=""

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
    # The run-2 unexplained-heal probes, duplicated here so a red at ANY site (not
    # just the health assert) captures the end-state function/ledger/backup evidence.
    _crollback_instrumentation "failure diagnostics" >&2 || true
    if [ -n "$C_ORIGINAL_LOG" ]; then
        echo "── original C claim log (retained across the retry's new row pointer) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/$C_ORIGINAL_LOG" >&2 || true
    fi
    echo "══════════ end failure diagnostics ══════════" >&2
}

_cleanup_crollback_arc() {
    local rc=$?
    if [ -n "$C_ARC_PID" ]; then
        kill "$C_ARC_PID" 2>/dev/null || true
        wait "$C_ARC_PID" 2>/dev/null || true
    fi
    if [ -n "$C_ARC_LOG" ]; then cat "$C_ARC_LOG" || true; fi
    if [ "$rc" -ne 0 ]; then _dump_crollback_failure_diagnostics; fi
    cleanup_vm "$VM_NAME" "$rc"
    exit "$rc"
}
trap _cleanup_crollback_arc EXIT

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
# db_container_identity — "<container-id> <image-tag> <created-timestamp>" for the
# db service, via `docker inspect` (never `docker ps`, whose CreatedAt column
# has second, not nanosecond, resolution — too coarse to prove a container that
# lived only tens of seconds was never replaced). Compared VERBATIM across the
# wait window below: any change in ANY field is a recreate, whether or not the
# image tag itself also changed (a same-tag recreate would still be a real
# resurrection of the mechanism this arc proves is absent). Empty/failure reads
# as "(unreadable)", never a false match against a real prior value.
db_container_identity() {
    # STATBUS-425 M3a (found live: this function returned empty on its first
    # real run - "cd ~/statbus" under VM_ROOT_EXEC resolves against ROOT's
    # home (/root), not the statbus checkout, because VM_ROOT_EXEC runs as
    # root (lxc exec ... -- bash -c), unlike VM_EXEC's sudo -u statbus. Every
    # other root-context caller in this codebase uses the absolute
    # /home/statbus/statbus path for exactly this reason (lxd-backend.sh's
    # own FRESH-checkout guards, sb-swap steps, etc.) - use it here too.
    VM_ROOT_EXEC bash -c 'cd /home/statbus/statbus && docker compose ps -q db 2>/dev/null | xargs -r docker inspect --format "{{.Id}} {{.Config.Image}} {{.Created}}" 2>/dev/null' 2>/dev/null | tr -d '\r' || true
}

apply_sql_file_with_migration_write_access() {
    local sql_file="$1"
    # B is parked inside the database-wide read-only upgrade window. Ordinary
    # `./sb psql` is intentionally non-exempt, so use the same libpq startup
    # option and in-container placement as migrate's write runners. The override
    # is scoped to this fixture-repair subprocess; external sessions stay frozen.
    VM_SCRIPT_INLINE apply-sql-with-migration-write-access "$sql_file" <<'APPLY_SQL'
#!/bin/bash
set -euo pipefail
sql_file="$1"
cd ~/statbus
admin_user=$(./sb dotenv -f .env get POSTGRES_ADMIN_USER)
app_db=$(./sb dotenv -f .env get POSTGRES_APP_DB)
docker compose exec -T -e "PGOPTIONS=-c default_transaction_read_only=off" -w /statbus db \
    psql -X -U "$admin_user" -d "$app_db" -v ON_ERROR_STOP=1 < "$sql_file"
APPLY_SQL
}

assert_direct_auth_status_healthy() {
    local phase="$1"
    # REST remains loopback-only on the slot-derived +3 port in standalone.
    local rest_port="${HARNESS_REST_PORT:-3013}"
    local auth_out auth_code auth_body
    auth_out=$(VM_EXEC bash -c "curl -s -m 5 -w '\n__HTTP__%{http_code}' -X POST http://127.0.0.1:${rest_port}/rpc/auth_status -H 'Content-Type: application/json' -d '{}'" 2>/dev/null || echo "__HTTP__000")
    auth_code=$(echo "$auth_out" | grep -oE '__HTTP__[0-9]+' | grep -oE '[0-9]+$' | tail -1 || true)
    auth_body=$(echo "$auth_out" | sed 's/__HTTP__[0-9]*$//')
    [ "$auth_code" = "200" ] || { echo "✗ auth_status (direct rest :${rest_port}) returned HTTP '${auth_code:-<none>}' during $phase, expected 200. Body: $auth_body" >&2; exit 1; }
    echo "  ✓ auth_status (direct rest :${rest_port}) → HTTP 200 ($phase)"
}

# _crollback_instrumentation LABEL — best-effort failure probes for the live RPC,
# function body, migration ledger, and C snapshot. They never gate the scenario;
# the explicit HTTP 200 assertions above and below C are the health oracles.
_crollback_instrumentation() {
    local _label="$1"
    local _rest_port="${HARNESS_REST_PORT:-3013}"  # slot=test REST binding, independent of standalone HTTPS :443
    echo ""
    echo "══════════ INSTRUMENTATION (${_label}) — run-2 unexplained-heal probes ══════════"
    # (a) DIRECT to the loopback REST port, bypassing the HTTPS proxy path —
    #     discriminates proxy-vs-db (is the heal in the proxy route or the DB?).
    echo "── probe (a): direct POST rest:${_rest_port}/rpc/auth_status (bypasses the proxy) ──"
    VM_EXEC bash -c "curl -s -m 5 -w '\n    HTTP %{http_code}\n' -X POST http://127.0.0.1:${_rest_port}/rpc/auth_status -H 'Content-Type: application/json' -d '{}'" 2>/dev/null | sed 's/^/    /' || echo "    (probe a failed)"
    # (b) LIVE function body: is the on-disk auth_status the broken fixture or a
    #     healed body, at probe time? (the smoking gun if it differs from probe a.)
    echo "── probe (b): live auth_status body (md5 + is-broken-fixture) via psql ──"
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT md5(prosrc) AS prosrc_md5, (prosrc LIKE '%auth_status intentionally broken%') AS is_broken_fixture FROM pg_proc WHERE proname = 'auth_status';\" | ./sb psql -x" 2>/dev/null | sed 's/^/    /' || echo "    (probe b failed)"
    # (c) db.migration max via a FRESH psql connection (no rest surface exposes the
    #     db schema — the ruling's sanctioned fallback) — rules out split-brain reads.
    echo "── probe (c): db.migration max via a fresh psql connection ──"
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT max(version) AS migration_max FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | sed 's/^/    migration_max=/' || echo "    (probe c failed)"
    # (d) fingerprint C's backup dir (the restore SOURCE) — find|sort|md5sum chain,
    #     answering DID THE RESTORE SOURCE CONTAIN these bytes (vs the live volume).
    echo "── probe (d): fingerprint of C's backup dir (the restore source) ──"
    local _bpath
    _bpath=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(backup_path,'') FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    echo "    C backup_path=${_bpath:-<none>}"
    if [ -n "$_bpath" ]; then
        VM_EXEC bash -c "if [ -e '$_bpath' ]; then echo -n '    backup fingerprint (find|sort|md5sum): '; find '$_bpath' -type f 2>/dev/null | sort | xargs md5sum 2>/dev/null | md5sum | awk '{print \$1}'; echo \"    file count: \$(find '$_bpath' -type f 2>/dev/null | wc -l)\"; else echo '    (backup path does not exist on disk)'; fi" 2>/dev/null || echo "    (probe d failed)"
    fi
    echo "══════════ end INSTRUMENTATION (${_label}) ══════════"
}

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
# Preserve the real source-era definition before V2 installs its synthetic park
# fault. Restoring this captured definition after B parks avoids duplicating a
# large function body in the harness and guarantees C snapshots a healthy B.
AUTH_STATUS_DEFINITION_PATH=tmp/crollback-auth-status-before-b.sql
VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -q -t -A > '$AUTH_STATUS_DEFINITION_PATH'" <<'CAPTURE_AUTH_STATUS_SQL'
SELECT pg_get_functiondef('public.auth_status()'::regprocedure);
CAPTURE_AUTH_STATUS_SQL
VM_EXEC bash -c "cd ~/statbus && test -s '$AUTH_STATUS_DEFINITION_PATH'" || { echo "✗ failed to capture auth_status before B's synthetic fault" >&2; exit 1; }
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
B_FAILURE_CODE=$(psql_scalar "SELECT COALESCE(failure_code::text,'') FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;")
[[ "$B_ROW_ID" =~ ^[0-9]+$ ]] || { echo "✗ could not read B's row id (got '$B_ROW_ID')" >&2; exit 1; }
[ "$B_PARK_STATE" = "in_progress" ] || { echo "✗ expected B state='in_progress' while parked, got '$B_PARK_STATE'" >&2; exit 1; }
arc_health_park_fields_match "$B_FAILURE_CODE" "$B_PARK_REASON" "$B_SHORT" || { echo "✗ B's typed health failure/prose mismatch: failure_code='$B_FAILURE_CODE' reason='$B_PARK_REASON' expected target ${B_SHORT} past warmup" >&2; exit 1; }
# Anti-vacuity: V1+V2 genuinely applied → B is genuinely AT-TARGET (the whole
# premise: a delta-carrying-but-at-target box, so the later replacement's rollback
# lands the box back on a real B state, not a no-op).
B_DBMAX=$(psql_scalar "SELECT max(version) FROM db.migration;")
[ "$B_DBMAX" = "${V_VERSION_2}" ] || { echo "✗ B is not at-target: db.migration max=$B_DBMAX, expected V2=${V_VERSION_2} (V1+V2 both applied)" >&2; exit 1; }
echo "  B parked (id=$B_ROW_ID), failure_code=$B_FAILURE_CODE, health reason names ${B_SHORT}, db.migration max=$B_DBMAX (V2)"
echo "  ✓ B at-target park landed (V1+V2 applied)"

# V2's auth_status replacement is a synthetic fault whose only scope is proving
# B's initial park. C snapshots the live B database, so restore the exact captured
# source body now while leaving B's parked row and V1/V2 ledger untouched.
echo ""
echo "── neutralize B's synthetic auth_status fault before C snapshots B ──"
B_ROW_BEFORE_NEUTRALIZE=$(row_cols_for "$B_FULL")
apply_sql_file_with_migration_write_access "$AUTH_STATUS_DEFINITION_PATH"
B_ROW_AFTER_NEUTRALIZE=$(row_cols_for "$B_FULL")
[ "$B_ROW_AFTER_NEUTRALIZE" = "$B_ROW_BEFORE_NEUTRALIZE" ] || { echo "✗ restoring auth_status changed B's parked row: before='$B_ROW_BEFORE_NEUTRALIZE' after='$B_ROW_AFTER_NEUTRALIZE'" >&2; exit 1; }
B_DBMAX_AFTER_NEUTRALIZE=$(psql_scalar "SELECT max(version) FROM db.migration;")
[ "$B_DBMAX_AFTER_NEUTRALIZE" = "$B_DBMAX" ] || { echo "✗ restoring auth_status changed the migration ledger: before=$B_DBMAX after=$B_DBMAX_AFTER_NEUTRALIZE" >&2; exit 1; }
assert_direct_auth_status_healthy "after park-only fixture cleanup, before C"
echo "  ✓ B row and V1/V2 ledger unchanged; C will snapshot a healthy B source"

# ── C: the ONE original register/schedule/terminal operation. Hold only its
# genuine daemon-owned Git call after claim/log stamping, before the canonical
# marker or source capture. All other Git calls delegate untouched. A missed
# window fails this arc, never falls back to the old rollback-only proof.
C_WINDOW=tmp/crollback-claim-window
VM_SCRIPT_INLINE crollback-arm-claim "$C_FULL" "$UPGRADE_UNIT" "$C_WINDOW" <<'ARM_C_CLAIM'
#!/bin/bash
set -euo pipefail
target=$1 unit=$2 window="$HOME/statbus/$3"
systemctl --user stop "$unit"
mkdir "$window"
mkdir "$window/bin"
unit_path=$(systemctl --user show "$unit" --property=Environment --value | tr ' ' '\n' | sed -n 's/^PATH=//p')
[ -n "$unit_path" ]
PATH="$unit_path" command -v git > "$window/real-git"
printf '%s\n' "$target" > "$window/target"
printf '%s\n' "$unit" > "$window/unit"
cat > "$window/bin/git" <<'CLAIM_GIT'
#!/bin/bash
set -euo pipefail
window=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -eq 6 ] && [ "$1" = -c ] && [ "$2" = log.showSignature=false ] &&
    [ "$3" = log ] && [ "$4" = -1 ] && [ "$5" = --pretty=%h ] &&
    [ "$6" = "$(cat "$window/target")" ] && [ "$PWD" = "$HOME/statbus" ]; then
    owner=$(systemctl --user show "$(cat "$window/unit")" --property=MainPID --value)
    if [ "$PPID" = "$owner" ] && mkdir "$window/claimed" 2>/dev/null; then
        printf '%s %s\n' "$$" "$PPID" > "$window/reached"
        exec sleep 600
    fi
fi
exec "$(cat "$window/real-git")" "$@"
CLAIM_GIT
chmod 755 "$window/bin/git"
dropin="$HOME/.config/systemd/user/$unit.d"
mkdir -p "$dropin"
cat > "$dropin/crollback-claim.conf" <<DROPIN
[Service]
Environment="PATH=$window/bin:$unit_path"
Restart=no
DROPIN
systemctl --user daemon-reload
ARM_C_CLAIM
vm_start_unit "$UPGRADE_UNIT"
C_ARC_LOG=$(mktemp)
(
    trap - EXIT
    arc_to "$C_FULL" "$C_BRANCH" "C (replacement that DISPLACES B then FAILS post-swap)" rolled_back
) > "$C_ARC_LOG" 2>&1 &
C_ARC_PID=$!
C_WINDOW_START=$(date +%s)
while ! VM_EXEC bash -c "test -s ~/statbus/$C_WINDOW/reached"; do
    kill -0 "$C_ARC_PID" 2>/dev/null || { echo "✗ original C operation exited without reaching the claim window" >&2; exit 1; }
    [ "$(( $(date +%s) - C_WINDOW_START ))" -lt "$UPGRADE_BUDGET_S" ] || { echo "✗ C claim window missed within ${UPGRADE_BUDGET_S}s" >&2; exit 1; }
    sleep 1
done
read -r C_HELD_PID C_OWNER_PID < <(VM_EXEC bash -c "cat ~/statbus/$C_WINDOW/reached")
[[ "$C_HELD_PID" =~ ^[1-9][0-9]*$ && "$C_OWNER_PID" =~ ^[1-9][0-9]*$ ]] || { echo "✗ invalid owned claim-window PIDs" >&2; exit 1; }
VM_EXEC bash -c "test \"\$(systemctl --user show '$UPGRADE_UNIT' --property=MainPID --value)\" = '$C_OWNER_PID' && kill -0 '$C_HELD_PID' && cd ~/statbus && cmp -s /proc/$C_OWNER_PID/exe ./sb && /proc/$C_OWNER_PID/exe --version | grep -F '(commit $B_SHORT)' && test ! -e tmp/upgrade-in-progress.json"
[ "$(box_head)" = "$B_FULL" ] || { echo "✗ tree is not B at C's pre-marker claim" >&2; exit 1; }
C_CUT_SQL="SELECT id || '|' || extract(epoch from started_at)::text || '|' || claim_token::text || '|' || log_relative_file_path FROM public.upgrade WHERE commit_sha = '$C_FULL' AND state = 'in_progress' AND tree_convergence_required AND started_at IS NOT NULL AND claim_token IS NOT NULL AND COALESCE(backup_path,'') = '' AND recovery_parked_at IS NULL;"
C_CUT=$(psql_scalar "$C_CUT_SQL")
IFS='|' read -r C_ROW_ID C_STARTED_EPOCH C_CLAIM_TOKEN C_ORIGINAL_LOG <<< "$C_CUT"
[[ "$C_ROW_ID" =~ ^[1-9][0-9]*$ && "$C_STARTED_EPOCH" =~ ^[0-9]+(\.[0-9]+)?$ && "$C_CLAIM_TOKEN" =~ ^[0-9a-f-]{36}$ && "$C_ORIGINAL_LOG" =~ ^[A-Za-z0-9_.-]+\.log$ ]] || { echo "✗ C has no genuine claimed, logged, snapshot-free convergence obligation: $C_CUT" >&2; exit 1; }
C_CLAIM_AUDIT_ID=$(psql_scalar "SELECT max(id) FROM public.upgrade_state_log WHERE upgrade_id = $C_ROW_ID AND old_state = 'scheduled' AND new_state = 'in_progress' AND logged_at >= to_timestamp($C_STARTED_EPOCH);")
[[ "$C_CLAIM_AUDIT_ID" =~ ^[1-9][0-9]*$ ]] || { echo "✗ C's claim has no durable state audit" >&2; exit 1; }
B_DISPLACED_SQL="SELECT count(*) FROM public.upgrade AS u WHERE u.id = $B_ROW_ID AND u.state = 'superseded' AND u.recovery_parked_at IS NULL AND u.error LIKE '%displaced by the claim of upgrade id=$C_ROW_ID%' AND (SELECT count(*) FROM public.upgrade_state_log AS l WHERE l.upgrade_id = u.id AND l.old_state = 'in_progress' AND l.new_state = 'superseded' AND l.old_parked_at IS NOT NULL AND l.new_parked_at IS NULL) = 1;"
[ "$(psql_scalar "$B_DISPLACED_SQL")" = 1 ] || { echo "✗ C did not genuinely displace B's park before the cut" >&2; exit 1; }
echo "  ✓ genuine C=$C_FULL pre-marker claim: $C_CUT; audit=$C_CLAIM_AUDIT_ID; B displaced"
VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/$C_ORIGINAL_LOG"

# Kill the CURRENT unit owner, then confirm its held Git subprocess is gone too.
# Never disarm on a missed kill. Restart=no keeps post-crash evidence immutable.
arc_kill_confirmed "$VM_NAME" daemon-mainpid || exit 1
C_KILL_START=$(date +%s)
while true; do
    C_HELD_STATE=$(VM_EXEC bash -c "if kill -0 '$C_HELD_PID' 2>/dev/null; then echo alive; else echo gone; fi")
    [ "$C_HELD_STATE" = gone ] && break
    [ "$C_HELD_STATE" = alive ] || { echo "✗ held Git subprocess death is unreadable: $C_HELD_STATE" >&2; exit 1; }
    [ "$(( $(date +%s) - C_KILL_START ))" -lt 30 ] || { echo "✗ held Git subprocess $C_HELD_PID survived the daemon SIGKILL" >&2; exit 1; }
    sleep 1
done
VM_EXEC bash -c "test \"\$(systemctl --user show '$UPGRADE_UNIT' --property=MainPID --value)\" = 0 && ! kill -0 '$C_OWNER_PID' 2>/dev/null"
[ "$(psql_scalar "$C_CUT_SQL")" = "$C_CUT" ] && [ "$(psql_scalar "$B_DISPLACED_SQL")" = 1 ] || { echo "✗ claim/displacement evidence changed before ordinary recovery" >&2; exit 1; }
VM_EXEC bash -c "test ! -e ~/statbus/tmp/upgrade-in-progress.json"

# A genuinely nonrunning serving tier makes recovery's Compose repair observable,
# even when the original park happened to leave B already serving. No second hold.
VM_SCRIPT_INLINE crollback-stop-serving-app <<'STOP_C_SERVING_APP'
#!/bin/bash
set -euo pipefail
cd ~/statbus && app=$(docker compose ps -a -q app) && test -n "$app" && docker compose stop app && test "$(docker inspect --format "{{.State.Running}}" "$app")" = false
STOP_C_SERVING_APP
VM_SCRIPT_INLINE crollback-disarm-claim "$UPGRADE_UNIT" "$C_WINDOW" <<'DISARM_C_CLAIM'
#!/bin/bash
set -euo pipefail
unit=$1 window="$HOME/statbus/$2"
rm "$window/bin/git" "$HOME/.config/systemd/user/$unit.d/crollback-claim.conf"
systemctl --user daemon-reload
test "$(systemctl --user show "$unit" --property=Restart --value)" = always
systemctl --user reset-failed "$unit"
DISARM_C_CLAIM
vm_start_unit "$UPGRADE_UNIT"
wait "$C_ARC_PID"
C_ARC_PID=""
cat "$C_ARC_LOG"
C_ARC_LOG=""

# The original log, not the retry's overwritten row pointer, proves this precise
# flagless route completed convergence. Its durable audit survives immediate retry.
VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/$C_ORIGINAL_LOG; grep -F \"Recovering the displaced park's serving tier against the checked-out tree before retrying source capture ...\" ~/statbus/tmp/upgrade-logs/$C_ORIGINAL_LOG && grep -F \"Recovering the displaced park's serving tier against the checked-out tree ... converged and returned to scheduled retry\" ~/statbus/tmp/upgrade-logs/$C_ORIGINAL_LOG"
C_RETRY_AUDIT=$(psql_scalar "SELECT count(*) FROM public.upgrade_state_log AS reschedule JOIN public.upgrade_state_log AS retry ON retry.upgrade_id = reschedule.upgrade_id AND retry.id > reschedule.id AND retry.old_state = 'scheduled' AND retry.new_state = 'in_progress' WHERE reschedule.upgrade_id = $C_ROW_ID AND reschedule.id > $C_CLAIM_AUDIT_ID AND reschedule.old_state = 'in_progress' AND reschedule.new_state = 'scheduled' AND reschedule.old_log_relative_file_path = '$C_ORIGINAL_LOG';")
[ "$C_RETRY_AUDIT" = 1 ] || { echo "✗ original C claim did not converge through exactly one audited scheduled retry (got '$C_RETRY_AUDIT')" >&2; exit 1; }
[ "$(psql_scalar "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = $C_ROW_ID AND new_state = 'completed';")" = 0 ] || { echo "✗ C was falsely completed instead of recovering its convergence obligation" >&2; exit 1; }
echo "  ✓ original C log and durable claim → scheduled → claim audit prove flagless convergence recovery"

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
#
# STATBUS-425 M3a (rc.16 arc run 36468921894; reproduced live on LXD, watched
# directly with a 3s-resolution docker-inspect poll across 3 separate real
# runs, not inferred): arc_to's own terminal-state loop returns the INSTANT
# the ledger writes rolled_back, but that write happens WHILE the rollback
# pass is still mid-flight — its own process exit and the systemd
# RestartSec=30 auto-restart it triggers land tens of seconds LATER. That
# restart's pre-READY=1 init runs EnsureDBUp (cli/internal/upgrade/
# service.go, Service.Run: strictly before sdNotify("READY=1")), which can
# recreate the db container from whatever compose model the prior swap left
# on disk — AFTER the ledger has already told the operator "rolled back,
# running normally". Read live (evidence in the progress log): the
# container's own .Created timestamp landed ~12-40s after rolled_back_at
# across three separate rc.16 runs.
#
# THE DISCRIMINATOR IS NOT "does the box eventually settle correctly" — on
# EVERY LXD run observed, including rc.16 ones, it did: the daemon's own
# restart-and-recreate is itself convergent, so a check taken after waiting
# long enough always sees a healthy box on the right commit, on BOTH
# backends, defect or no defect (a verdict that depends on which side of a
# timing window a run's OWN query lands is not a discriminating check,
# AGENTS.md: no flaky tests). THE DISCRIMINATOR IS THE HISTORICAL FACT of
# whether the container was ever recreated AFTER rolled_back_at was
# written — a fixed instant already on the ledger, compared against the
# container's own immutable .Created timestamp, both real timestamps, no
# live race to lose: wait for the daemon to settle (arc_wait_unit_active;
# ALSO still needed so the comparison itself reads a stable, non-mid-
# transition container), then compare two facts that already happened.
echo ""
# STATBUS-425 M3b review round R1: capture rolled_back_at BEFORE the wait and
# pass it to arc_wait_unit_active, so the wait discriminates the POST-rollback
# boot (ExecMainStartTimestamp after this instant) from the OLD daemon
# process, which the unit still reports 'active' for in the window between
# its own rolled_back write and its later os.Exit(75) — is-active alone
# cannot tell those two apart; see arc_wait_unit_active's own header comment.
# STATBUS-425 M3b (found live: the FIRST real run through this wait hung
# indefinitely): capture as EPOCH SECONDS via extract(epoch from ...), never
# the raw timestamptz text — psql_scalar's own `tr -d ' \r\n'` (every arc
# script's copy) strips the space between the date and time components of a
# raw timestamp string ('2026-09-29 11:32:07...' -> '2026-09-2911:32:07...'),
# which arc_wait_unit_active would then fail to parse. A plain integer has
# no space to strip.
ROLLED_BACK_AT_EPOCH=$(psql_scalar "SELECT extract(epoch from rolled_back_at) FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;")
[[ "$ROLLED_BACK_AT_EPOCH" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "✗ rolled_back_at is not yet set for C, or did not read as a number (got '$ROLLED_BACK_AT_EPOCH') — arc_to should have already confirmed the 'rolled_back' terminal before this point" >&2; exit 1; }
echo "── waiting out the daemon's post-rollback restart cycle (budget ${UNIT_ACTIVE_WAIT_BUDGET_S}s) before reading box state ──"
arc_wait_unit_active "$UNIT_ACTIVE_WAIT_BUDGET_S" "$ARC_UPGRADE_UNIT" "$ROLLED_BACK_AT_EPOCH" || exit 1
# Capture the db container's identity now (settled state) and again after a
# short further settle window: if EnsureDBUp were somehow STILL in flight (or
# fires a SECOND time on a later heartbeat tick), this catches it as a
# genuine assertion failure rather than reading a container mid-replacement.
# Mirrors postswap-health-park-arc.sh's own "before/after a settle window,
# must match" NRestarts pattern (STATBUS-425 M3a; same false-vacuity class).
DB_ID_SETTLED=$(db_container_identity)
[ -n "$DB_ID_SETTLED" ] || { echo "✗ could not read db container identity after the settle wait (docker inspect empty/failed)" >&2; exit 1; }
sleep 15
DB_ID_RECHECK=$(db_container_identity)
[ "$DB_ID_RECHECK" = "$DB_ID_SETTLED" ] || { echo "✗ db container identity changed during the post-settle recheck window: before='$DB_ID_SETTLED' after='$DB_ID_RECHECK' — a recreate is STILL happening after the unit reported active" >&2; exit 1; }
echo "  ✓ db container identity stable across the settle+recheck window: $DB_ID_SETTLED"
# ── THE mechanism-level assertion: the db container must NOT have been
#    created after the ledger declared rolled_back. Both timestamps are
#    real, already-written facts (Postgres now() at the UPDATE; Docker's own
#    immutable .Created at container-create time) - comparing them inside
#    Postgres itself (::timestamptz, not bash date arithmetic) sidesteps any
#    local-vs-remote clock or format mismatch, and is itself a HISTORICAL
#    fact-check, not a live race: it is true or false regardless of when
#    this script happens to run it. ──
DB_CREATED_AT=$(printf '%s' "$DB_ID_SETTLED" | awk '{print $3}')
[ -n "$DB_CREATED_AT" ] || { echo "✗ could not parse db container .Created from identity: $DB_ID_SETTLED" >&2; exit 1; }
RECREATED_AFTER_ROLLBACK=$(psql_scalar "SELECT (rolled_back_at IS NOT NULL AND '${DB_CREATED_AT}'::timestamptz > rolled_back_at) FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;")
case "$RECREATED_AFTER_ROLLBACK" in
    f) echo "  ✓ db container .Created ($DB_CREATED_AT) is NOT after rolled_back_at — the database was never recreated post-rollback" ;;
    t)
        ROLLED_BACK_AT=$(psql_scalar "SELECT rolled_back_at FROM public.upgrade WHERE commit_sha = '$C_FULL' ORDER BY id DESC LIMIT 1;")
        echo "✗ db container .Created ($DB_CREATED_AT) is AFTER rolled_back_at ($ROLLED_BACK_AT) — the database was recreated from the TARGET compose model after the ledger already declared rolled_back (STATBUS-425 rc.16 class: EnsureDBUp's config-hash drift recreate on the next daemon boot)" >&2
        exit 1
        ;;
    *) echo "✗ could not evaluate the recreate-after-rollback check (got '$RECREATED_AFTER_ROLLBACK')" >&2; exit 1 ;;
esac
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
# The db container's running image must name B's own short SHA (the SOURCE
# model), never C's — a resurrection that raced the read would show C's tag
# (or a container the settled-identity check above already would have
# caught changing). This is the DIRECT, mechanism-level form of "box's DB is
# on B": not inferred from db.migration's version ledger, but read from the
# container Docker itself is actually running.
DB_IMAGE_TAG=$(printf '%s' "$DB_ID_SETTLED" | awk '{print $2}')
case "$DB_IMAGE_TAG" in
    *":${B_SHORT}") echo "  ✓ db container image tag names B's own short SHA (${B_SHORT}): $DB_IMAGE_TAG" ;;
    *) echo "✗ db container image tag does not name B's short SHA (${B_SHORT}): got '$DB_IMAGE_TAG' (identity: $DB_ID_SETTLED) — the container is not genuinely on the source model" >&2; exit 1 ;;
esac
echo "  ✓ C rolled_back; box's DB at B's V2 (${V_VERSION_2}), C's V3 not applied, git HEAD == B"

# ── operator runs `./sb install` — StateNothingScheduled: config refresh, no row
#    authored, no upsert of B. Must exit 0 on the healthy restored B source. ──
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
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ ./sb install exited $INSTALL_RC — expected 0 for config refresh on the healthy restored B source" >&2; exit 1; }
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

# C restored the healthy B snapshot prepared above. The mandatory rollback health
# gate and this independent direct probe must agree that the running source is
# serve-capable after `./sb install`; no terminal row is resurrected to say so.
echo ""
echo "── source app health remains green after C rollback and install ──"
assert_direct_auth_status_healthy "after C rolled back and install refused resurrection"
[ "$(psql_scalar 'SELECT count(*) FROM public.upgrade WHERE tree_convergence_required;')" = 0 ] || { echo "✗ durable convergence obligation was not cleared" >&2; exit 1; }
VM_SCRIPT_INLINE crollback-confirm-source-daemon "$UPGRADE_UNIT" "$B_SHORT" <<'CONFIRM_SOURCE_DAEMON'
set -euo pipefail
cd ~/statbus
test ! -e tmp/upgrade-in-progress.json
daemon=$(systemctl --user show "$1" --property=MainPID --value)
test "$daemon" -gt 0
cmp -s /proc/$daemon/exe ./sb
/proc/$daemon/exe --version | grep -F "(commit $2)"
CONFIRM_SOURCE_DAEMON
# Read the responding app artifact, not .env tags or the checkout's identity.
APP_SITE_DOMAIN="${HARNESS_SITE_DOMAIN:-statbus-test.local}"
VM_EXEC curl -fksS --max-time 10 --resolve "$APP_SITE_DOMAIN:443:127.0.0.1" -H 'Cache-Control: no-store' "https://$APP_SITE_DOMAIN/_statbus-build.json" |
    python3 -c 'import json,sys; actual=json.load(sys.stdin).get("commit_sha"); expected=sys.argv[1]; print("responding app commit_sha=" + str(actual)); sys.exit(0 if actual == expected else 1)' "$B_FULL"

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
UPDATE public.upgrade SET state = 'completed' WHERE id = ${B_ROW_ID};  -- HARNESS-SANCTIONED-LEDGER-WRITE (GUARD-PROBE above; must be REFUSED by the trigger, STATBUS-071 P6)
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
echo "PASS: c-rollback-resurrection — replacement C displaced the parked at-target B (superseded, story intact), then FAILED post-swap and rolled back onto B (C rolled_back; box's DB at B's V2, git HEAD==B). The park-only auth_status fault was neutralized without changing B's row or V1/V2 ledger, so C snapshotted and restored a healthy B source. The operator's ./sb install exited 0 and resurrected B through NO door: B stayed superseded, C stayed rolled_back, the state log shows zero terminal→completed, and the box observably runs healthy B with no completed-B ledger row. The GUARD-PROBE confirmed the terminal-resurrection trigger refuses the forbidden write naming the re-dispatch remedy, leaving B's row byte-unchanged. Data intact throughout. (STATBUS-160 non-resurrection proven end-to-end.)"
