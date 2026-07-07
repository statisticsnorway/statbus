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
# MECHANICS VERIFIED AGAINST SHIPPED CODE (mechanic, 2026-07-07) — read this
# before touching the midpoint-wait budget or NRestarts bound: the "mind the
# trap" instruction asked to confirm the marker/ceiling live on the
# applyPostSwap path for a NORMAL (non-recovery) dispatch, not the
# boot-migrate-up path — verified, with a load-bearing nuance:
#
#   1. `MigrateUpTimeout` is the SAME package var used at BOTH migrate call
#      sites: boot-migrate-up (service.go:~1934, Run()'s own unconditional
#      post-exit-42-handoff step, BEFORE recoverFromFlag — confirmed by the
#      postswap-migration-oom-arc's own trace: this is where a FRESH,
#      non-crash upgrade's pending migrations actually run) AND applyPostSwap's
#      own migrate call (service.go:~5416, normally a no-op fallback). Arming
#      STATBUS_MIGRATE_UP_TIMEOUT governs BOTH sites identically — there is no
#      way to make the ceiling apply to only one of them.
#   2. CONSEQUENCE (the nuance): on a normal dispatch, boot-migrate-up hits
#      the SAME 20s ceiling FIRST. Its own timeout handling does NOT print the
#      named marker — it calls terminateMigrateOrphan (silently reaps the
#      orphaned backend) then, because a service-held flag is present (a real
#      in-flight upgrade), FALLS THROUGH to recoverFromFlag in the SAME
#      process (service.go's STATBUS-017 defer: "deferring to recoverFromFlag
#      for snapshot restore") — flag.Phase is still "post_swap" at this
#      instant, so recoverFromFlag's PostSwap branch fires resumePostSwap ->
#      applyPostSwap, same boot, no restart yet. applyPostSwap's OWN migrate
#      call now finds V_sleep still pending (nothing committed) and
#      genuinely re-attempts it FROM THE TOP — hitting the SAME 20s ceiling
#      AGAIN. THIS second attempt is where the named marker actually prints,
#      followed by its own terminateMigrateOrphan + observed-state Behind ->
#      in-process d.rollback() -> rolled_back.
#   3. NET EFFECT: total wall-clock to the marker is ~2x the ceiling (~40s
#      with a 20s ceiling: one silent 20s attempt inside boot-migrate-up, one
#      marked 20s attempt inside applyPostSwap), all within ONE continuous
#      process/boot — the planned exit-42 handoff is still the ONLY restart
#      before this point. rollback() itself then unconditionally os.Exit(75)
#      at the end (the existing rc.67 trifecta, true of every rollback()
#      call in the codebase) — a SECOND, planned, terminal restart. NRestarts
#      bound below is therefore 2 (handoff + rollback's own terminal exit),
#      not 1 — "the daemon survives the in-process rollback" is true in the
#      sense that nothing CRASHES it; the terminal exit(75) is rollback()'s
#      own designed conclusion, identical to what failing-arc.sh's V_fail
#      produces (that arc does not assert NRestarts at all; this file adds
#      the assertion explicitly, per the ruling's ask, with this bound).
#   This does NOT put V_sleep through boot-migrate-up INSTEAD of applyPostSwap
#   — it goes through BOTH, boot-migrate-up first (silently) then
#   applyPostSwap (where the marker lives) — so the premise the ruling relies
#   on (the marker fires, in-process, failing-arc shape) holds. Flagging the
#   two-attempt wall-clock nuance rather than improvising past it silently.
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

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

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
        echo "  [OBSERVE] V_sleep not seen active within ${MIDPOINT_WAIT_BUDGET_S}s — the ceiling (${CEILING_TIMEOUT}) may already have fired inside boot-migrate-up's silent first attempt before this poll started; continuing to the marker watch regardless"
        break
    fi
    sleep 1
done

# ─────────────────────────────────────────────────────────────────────────
# THE MARKER (load-bearing, per the ruling — NOT best-effort: the ceiling is
# an internal, deterministic mechanism with no external timing race). Per
# the MECHANICS note, this fires on applyPostSwap's SECOND attempt (after
# boot-migrate-up's own silent first ceiling hit), roughly 2x the ceiling
# after schedule.
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
