#!/bin/bash
# Arc: postswap-migration-ceiling  (STATBUS-095 piece 2 — recover from OUR OWN
# internal STATBUS_MIGRATE_UP_TIMEOUT ceiling killing a migration that runs
# past it, contrast with postswap-migration-oom's EXTERNAL kill).
#
# CONSTRUCTION RULING: STATBUS-095 comment #1, PIECE 2 (architect). The
# ceiling knob shipped in c500efc9d: STATBUS_MIGRATE_UP_TIMEOUT (Go duration,
# 5s floor, WARN on clamp), resolved ONCE at process start into the package
# var MigrateUpTimeout — so arming it requires a systemd dropin + unit
# RESTART (env is read at process start, not live), the same stall-dropin
# pattern arc-helpers.sh's arc_install_stall_dropin already uses for
# STATBUS_INJECT_AT. The named marker is EXACTLY:
#   migration exceeded the ceiling (%s) — killed; rolling back
# emitted at service.go's applyPostSwap migrate call (~line 5435) BEFORE the
# orphan-reap (terminateMigrateOrphan) + the observed-state-driven rollback.
#
# THIS IS A ROLLBACK STORY, unlike oom's forward-completion story: nothing
# external ever revives anything here — SIGKILL comes from OUR OWN ctx
# deadline, the migration's transaction dies uncommitted, and the ceiling's
# own in-process rollback IS the terminal. The failing-arc apparatus
# (baseline fingerprint, V-unrecorded, clean-slate match) applies verbatim.
#
# V_sleep migration: `SELECT pg_sleep(3600);`, bare (no BEGIN/END) — new
# `ceiling` SPEC in lib/upgrade-target.sh. Deliberately LONG despite the
# short ceiling: with STATBUS_MIGRATE_UP_TIMEOUT=20s armed, the SIGKILL lands
# at 20s regardless of how long the statement WOULD have slept — a long
# sleep costs nothing here (contrast oom, which has no internal ceiling and
# must keep its own sleep short so a revived box doesn't wait out the full
# duration for real).
#
# MECHANICS UNDER STATBUS-145 (minimal-boot-migrate) — read this before touching
# the midpoint-wait budget or NRestarts bound. The marker/ceiling live on the
# applyPostSwap path, and under 145 they fire EXACTLY ONCE:
#
#   1. STATBUS-145: boot-migrate-up now runs `migrate up --to DaemonSchemaFloor`
#      (service.go:~1934) — it catches the schema up ONLY to the daemon floor and
#      NEVER touches the above-floor delta. So V_sleep (the delta migration, above
#      the floor) does NOT run at boot-migrate. It runs EXACTLY ONCE at
#      applyPostSwap's own migrate call (service.go:~5466 — the SINGLE
#      delta-application site under 145), governed by the same `MigrateUpTimeout`
#      ceiling armed via STATBUS_MIGRATE_UP_TIMEOUT.
#   2. CONSEQUENCE (single-fire): V_sleep hits the 20s ceiling ONCE, inside
#      applyPostSwap. That timeout handler prints the named marker, calls
#      terminateMigrateOrphan (reaps the orphaned in-container backend), then —
#      the delta unrecorded → observed-state Behind — routes postSwapFailure ->
#      in-process d.rollback() -> rolled_back. There is NO silent boot-migrate
#      first fire: pre-145 the delta ALSO ran at boot-migrate, giving a ~2x-ceiling
#      double fire; 145 dissolves that. The single-fire leg below asserts EXACTLY
#      ONE marker in the journal.
#   3. NET EFFECT: total wall-clock to the marker is ~1x the ceiling (~20s with a
#      20s ceiling), all within ONE continuous process/boot — the planned exit-42
#      handoff is still the ONLY restart before this point. rollback() then
#      unconditionally os.Exit(75) at the end (the rc.67 trifecta, true of every
#      rollback() call) — a SECOND, planned, terminal restart. NRestarts bound
#      below is therefore still 2 (handoff + rollback's own terminal exit), not 1 —
#      the daemon is never CRASHED; the terminal exit(75) is rollback()'s own
#      designed conclusion, identical to failing-arc.sh's V_fail. This arc asserts
#      NRestarts explicitly with this bound.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. No C_FULL/C_BRANCH — single-phase arc. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-migration-ceiling}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-600}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
MIDPOINT_WAIT_BUDGET_S="${MIDPOINT_WAIT_BUDGET_S:-60}"
ORPHAN_GONE_BUDGET_S="${ORPHAN_GONE_BUDGET_S:-30}"
CEILING_TIMEOUT="${CEILING_TIMEOUT:-20s}"
UPGRADE_UNIT="statbus-upgrade@statbus.service"

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

# _dump_migration_ceiling_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_migration_ceiling_failure_diagnostics() {
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
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_migration_ceiling_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-migration-ceiling  (STATBUS-095 piece 2 — internal STATBUS_MIGRATE_UP_TIMEOUT=${CEILING_TIMEOUT} ceiling)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# row_state / row_error — same transport-aware shape as the oom arc's readers
# (harmless here too: the db is never externally touched by this arc, but a
# psql call can still transiently fail during the daemon's own restart).
row_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo ""; }

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# Baseline fingerprint (post-A + demo data) — THIS arc's terminal is
# rolled_back (unlike oom's completed), so the failing-arc apparatus applies
# verbatim: the rollback must restore this byte-for-byte.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ─────────────────────────────────────────────────────────────────────────
# ARM THE CEILING: systemd USER dropin (Environment=STATBUS_MIGRATE_UP_TIMEOUT)
# + unit RESTART — mirrors arc_install_stall_dropin's exact shape
# (arc-helpers.sh), simplified (no STATBUS_INJECT_AT / release file, just one
# env var). MUST run BEFORE scheduling B (same ordering rule as the stall
# dropin: the restart's own startup-scan must find nothing 'scheduled' yet,
# or STATBUS-098's on-startup claim could pre-claim it before this dropin's
# env is what the daemon is running with — register-only leaves B in
# 'registered', not yet claimable).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── installing STATBUS_MIGRATE_UP_TIMEOUT=${CEILING_TIMEOUT} dropin + restarting unit (arms env in the daemon process) ──"
VM_EXEC systemctl --user stop "$UPGRADE_UNIT" 2>/dev/null || true
DROPIN_SCRIPT=$(mktemp)
cat > "$DROPIN_SCRIPT" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UPGRADE_UNIT}.d"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_DIR/ceiling.conf" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_MIGRATE_UP_TIMEOUT=${CEILING_TIMEOUT}
DROPIN_EOF
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$DROPIN_SCRIPT"
upload_install_script_to_vm "$VM_NAME" "$DROPIN_SCRIPT" /tmp/arc-ceiling-dropin.sh
rm -f "$DROPIN_SCRIPT"
VM_EXEC bash /tmp/arc-ceiling-dropin.sh
vm_start_unit "$UPGRADE_UNIT"
echo "  ✓ dropin installed + unit restarted with STATBUS_MIGRATE_UP_TIMEOUT=${CEILING_TIMEOUT}"

echo ""
echo "── schedule B (DB trigger → daemon claims + runs executeUpgrade) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ─────────────────────────────────────────────────────────────────────────
# MIDPOINT (anti-vacuity): confirm V_sleep is genuinely running before
# trusting anything downstream. No external action needed here (unlike the
# oom arc) — the ceiling is entirely internal; this poll only proves the
# migration reached pg_stat_activity at least once before its own ceiling
# fires. Budget is short (60s default) since the ceiling itself is only 20s.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for V_sleep to be ACTIVE in pg_stat_activity (budget ${MIDPOINT_WAIT_BUDGET_S}s) ──"
MID_START=$(date +%s)
MIDPOINT_SEEN="no"
while :; do
    ELAPSED=$(( $(date +%s) - MID_START ))
    COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE 'SELECT pg_sleep(3600)%';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
    if [ "$COUNT" -ge 1 ] 2>/dev/null; then
        MIDPOINT_SEEN="yes"
        echo "  ✓ V_sleep active in pg_stat_activity after ${ELAPSED}s"
        break
    fi
    if [ "$ELAPSED" -ge "$MIDPOINT_WAIT_BUDGET_S" ]; then
        echo "  [OBSERVE] V_sleep not seen active within ${MIDPOINT_WAIT_BUDGET_S}s — under STATBUS-145 the delta runs once at applyPostSwap; the ceiling (${CEILING_TIMEOUT}) may already have fired before this poll started; continuing to the marker watch regardless"
        break
    fi
    sleep 1
done

# ─────────────────────────────────────────────────────────────────────────
# THE MARKER (load-bearing, per the ruling — NOT best-effort: the ceiling is
# an internal, deterministic mechanism with no external timing race). Per
# the STATBUS-145 MECHANICS note, this fires ONCE inside applyPostSwap's migrate
# (the single delta site; boot-migrate is floor-only), ~1x the ceiling after
# schedule. The single-fire leg below asserts exactly one marker.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── watching for the named ceiling marker (budget ${UPGRADE_BUDGET_S}s) ──"
MARKER_START=$(date +%s)
MARKER_SEEN="no"
while :; do
    ELAPSED=$(( $(date +%s) - MARKER_START ))
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" || echo "")
    if echo "$JOURNAL_TAIL" | grep -q "migration exceeded the ceiling (${CEILING_TIMEOUT}) — killed; rolling back"; then
        MARKER_SEEN="yes"
        echo "  ✓ named ceiling marker observed after ${ELAPSED}s: \"migration exceeded the ceiling (${CEILING_TIMEOUT}) — killed; rolling back\""
        break
    fi
    if [ "$ELAPSED" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ named ceiling marker not observed within ${UPGRADE_BUDGET_S}s" >&2
        echo "$JOURNAL_TAIL" | tail -40 >&2
        exit 1
    fi
    sleep 3
done

# ─────────────────────────────────────────────────────────────────────────
# ORPHAN GONE (the #14 leg, observed live per the ruling): terminateMigrateOrphan
# runs immediately after the marker print — the orphaned in-container psql
# backend (docker-exec doesn't forward the host-side SIGKILL) must actually
# disappear from pg_stat_activity within a short window.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── confirming the orphaned pg_sleep backend is gone (budget ${ORPHAN_GONE_BUDGET_S}s) ──"
ORPHAN_START=$(date +%s)
while :; do
    ELAPSED=$(( $(date +%s) - ORPHAN_START ))
    COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE query LIKE 'SELECT pg_sleep(3600)%';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$COUNT" = "0" ]; then
        echo "  ✓ orphaned pg_sleep backend gone after ${ELAPSED}s"
        break
    fi
    if [ "$ELAPSED" -ge "$ORPHAN_GONE_BUDGET_S" ]; then
        echo "✗ orphaned pg_sleep backend still present ${ORPHAN_GONE_BUDGET_S}s after the marker (count=$COUNT) — terminateMigrateOrphan did not reap it" >&2
        exit 1
    fi
    sleep 2
done

# ─────────────────────────────────────────────────────────────────────────
# TERMINAL: wait for the row to reach a terminal state.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for B to reach a terminal state (budget ${UPGRADE_BUDGET_S}s) ──"
TERM_START=$(date +%s)
FINAL_STATE=""
while :; do
    ELAPSED=$(( $(date +%s) - TERM_START ))
    if [ "$ELAPSED" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ B: no terminal state within ${UPGRADE_BUDGET_S}s" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(row_state)
    case "$STATE" in
        completed|failed|rolled_back) FINAL_STATE="$STATE"; echo "  B: state='$STATE' (t+${ELAPSED}s)"; break ;;
    esac
    sleep 3
done

echo ""
echo "── convergence checks (the box recovered from our own internal migration-ceiling kill) ──"
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — impossible on this route (V_sleep was SIGKILLed, never committed)" >&2; exit 1; }
[ "$FINAL_STATE" = "rolled_back" ] || { echo "✗ B reached '$FINAL_STATE', expected 'rolled_back'" >&2; VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true; exit 1; }
echo "  ✓ state='rolled_back'"
echo "  error: $(row_error)"

MROWS_B=$(migration_row_count)
[ "$MROWS_B" = "0" ] || { echo "✗ V_sleep left a ledger row (count=$MROWS_B, want 0) — rollback did not unrecord it" >&2; exit 1; }
echo "  ✓ V_sleep not recorded in db.migration (rolled back, transaction died uncommitted with its backend)"

# STATBUS-145 SINGLE-FIRE LEG: under the minimal-boot-migrate geometry the delta
# runs EXACTLY ONCE at the applyPostSwap step — boot-migrate now goes only `--to`
# the daemon floor and never touches the above-floor delta — so the ceiling fires
# EXACTLY ONCE, not the pre-145 ~2× (a silent boot-migrate first fire + the
# applyPostSwap second fire). Count the named marker across the WHOLE journal.
MARKER_COUNT=$(VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager 2>/dev/null | grep -c 'migration exceeded the ceiling (${CEILING_TIMEOUT}) — killed; rolling back' || true" 2>/dev/null | tr -d ' \r\n')
[ -n "$MARKER_COUNT" ] || MARKER_COUNT="?"
[ "$MARKER_COUNT" = "1" ] || { echo "✗ ceiling marker fired ${MARKER_COUNT}× (want exactly 1) — STATBUS-145 single-fire violated: the delta must run ONCE at applyPostSwap, never also at boot-migrate" >&2; exit 1; }
echo "  ✓ ceiling marker fired EXACTLY ONCE (STATBUS-145 single-fire — delta ran once at applyPostSwap, never at boot)"

assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: see MECHANICS point 3. Bound = 2 (the planned exit-42 handoff +
# rollback()'s own terminal os.Exit(75) — the SAME two-restart shape any
# in-process rollback produces, failing-arc's V_fail included; that arc just
# never asserts it explicitly). The daemon is never CRASHED by this arc —
# both restarts are the product's own designed conclusions. Anything beyond
# 2 is a finding.
OBSERVED_NRESTARTS=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] NRestarts = ${OBSERVED_NRESTARTS} (2 expected: exit-42 handoff + rollback's own terminal exit)"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2

echo ""
echo "  midpoint pg_sleep active seen: $MIDPOINT_SEEN; ceiling marker seen: $MARKER_SEEN"
echo "PASS: postswap-migration-ceiling (a real, long-running migration was SIGKILLed by our own STATBUS_MIGRATE_UP_TIMEOUT ceiling; the orphaned backend was reaped; the box rolled back autonomously to a byte-identical clean slate, data intact, healthy)"
