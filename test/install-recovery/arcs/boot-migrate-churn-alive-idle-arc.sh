#!/bin/bash
# Arc: boot-migrate-churn-alive-idle  (STATBUS-071 P4 — the REAL-PATH successor to
# scenario 4-rollback-abort-churn-then-alive-idle, STATBUS-144 AC#3).
#
# WHAT THIS PROVES (144 AC#3, on a REAL path): a FLAGLESS boot whose boot-migrate hits a
# deterministic-failing migration exits 20, and the 144 guard (bootMigrateIsDeterministic,
# service.go:44) logs "BOOT MIGRATE FAILED DETERMINISTICALLY" ONCE and stays ALIVE-IDLE —
# never the pre-144 exit → systemd-Restart=always → StartLimit death. The scenario this
# replaces FABRICATED that state (fabricate_resume_state + a hand-built ABORT + a hand-
# dropped floor-bound migration). Here every line of machinery that runs is REAL; only the
# INPUT STATE is manipulated, in the blessed genre.
#
# THE CHURN CLASS + WHY THIS CONSTRUCTION (architect ruling, STATBUS-071 P4): the target is
# the boot-migrate-EXIT-20 churn — NOT the death-budget park. The failing lineage's own V
# sits ABOVE DaemonSchemaFloor (V_VERSION = _latest+1), so boot-migrate (`--to floor`) never
# attempts it; a real mid-rollback crash alone therefore cannot reproduce the scenario's
# boot-migrate churn. The real producer of the churn state, per the 144 record's documented
# genre, is "flag loss + a broken ≤-floor migration on disk around a real upgrade crash".
# This arc constructs exactly that from real operations plus TWO INPUT-STATE manipulations,
# each labeled below with the real class it stands in for:
#
#   MANIPULATION 1 — FLAG TRUNCATION (blessed genre; same precedent as the flagless-selfheal
#     arc). After the real crash the service-held flag is on disk; truncating it to invalid
#     JSON reproduces a real crash-during-flag-write / tmpfs-loss — the r19-ruling flagless
#     producer. The REAL corrupt-flag reader (recoverFromFlag: json.Unmarshal fail →
#     "FLAG_CORRUPT: … removing" → os.Remove, row untouched) then removes it, producing the
#     [in_progress row + NO flag] flagless state for real.
#
#   MANIPULATION 2 — MIGRATION FILE-DROP (blessed INPUT-state genre). A deterministically-
#     failing migration (SELECT 1/0) is placed at a genuinely-free version AT OR BELOW the
#     checkout's own DaemonSchemaFloor. This is "the broken migration on disk" AC#3 talks
#     about — the thing a flagless boot-migrate will attempt and fail on. Its version is
#     computed AT RUN TIME from the checked-out tree (never hardcoded — the tree advances and
#     a fixed version would silently stop being ≤ floor). Everything the daemon then DOES with
#     it — the boot-migrate attempt, the exit-20 classification, the 144 alive-idle handler —
#     is real product code.
#
# REAL MACHINERY (nothing fabricated): install A (arc_prepare_box) → real register+schedule
# of the failing-lineage B → a real ./sb install dispatch runs executeUpgrade inline: migrate
# hits V_fail (RAISE EXCEPTION) → newSbUpgradingFailure → observed Behind → d.rollback →
# restoreGitState/Binary/Database restore the box to A → the C9 inject fires at the REAL
# mid-rollback instant (killed-by-system-during-builtin-rollback, service.go:7632, exit 137),
# leaving the service-held flag on disk with the row still in_progress and the tree restored
# to A. Then the two input manipulations, then the daemon recovery boot drives the flagless
# boot-migrate churn for real.
#
# SET-DIFFERENCE vs 4-rollback-abort-churn-then-alive-idle (every scenario assert mapped):
#   scenario assert 1 (unit alive-idle, not StartLimit-dead)  → assert A below
#   scenario assert 2 (NRestarts bounded, no churn loop)      → assert B below (+ no-churn watch)
#   scenario assert 3 (row not self-healed to completed)      → assert C below (row stays non-
#       completed; VALUE differs — mid-rollback-kill leaves in_progress, the scenario's ABORT
#       leaves 'failed' — but the PROPERTY, no false self-heal to completed on a genuinely-
#       behind box, is identical and asserted)
#   scenario assert 4 (broken migration never recorded)       → assert D below
#   scenario assert 5 (the loud BOOT MIGRATE FAILED banner)   → assert E below
#   scenario assert 6 (app/db/rest/worker keep serving)       → assert F below
#   (the scenario's ABORT-terminal ROLLBACK_FAILED_GIT_CORRUPT half is NOT re-proven here —
#    it is a different construction, arc-covered elsewhere; this arc proves only the churn.)
#
# Inputs (env): BASE_SHA, B_FULL (40-hex, failing lineage), B_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-boot-migrate-churn-alive-idle}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
# Watch AFTER the settle window for a churn that must NOT happen — long enough to catch a
# StartLimit-class loop (RestartSec=30s × several cycles) if the 144 guard regressed.
NO_CHURN_WATCH_S="${NO_CHURN_WATCH_S:-90}"

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

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FLAG_PATH="tmp/upgrade-in-progress.json"

_dump_churn_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (row + journal + flag + migrations) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 5;\" | ./sb psql -x" >&2 || true
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || true
    VM_EXEC bash -c "ls -la ~/statbus/$FLAG_PATH 2>&1; echo '--- flag bytes ---'; wc -c ~/statbus/$FLAG_PATH 2>/dev/null" >&2 || true
    VM_EXEC bash -c "ls ~/statbus/migrations/ | tail -8" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_churn_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: boot-migrate-churn-alive-idle  (real crash + real flag-loss + a ≤-floor broken migration → flagless boot-migrate exit-20 → 144 guard → alive-idle)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  V=${V_VERSION}"
echo "════════════════════════════════════════════════════════════════"

row_state()    { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_present() { VM_EXEC bash -c "test -f ~/statbus/$FLAG_PATH && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
migration_recorded() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = $1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n'; }
# ARM-scoped journal (the paid-for lesson — the persistent unit journal matches prior boots'
# markers; anchor at the VM clock captured before the recovery boot).
arm_since()   { VM_EXEC bash -c "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null | tr -d '\r'; }
journal_has() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -qF \"$1\" && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
journal_count() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -cF \"$1\" || true" 2>/dev/null | tr -d ' \r\n' || echo "0"; }

# ── A: install + prepare; snapshot ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── real dispatch on the failing lineage, killed at the REAL mid-rollback instant ──
echo ""
echo "── register B (failing lineage, daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
arc_schedule_daemon_down "$B_FULL"

echo ""
echo "── dispatch B with the C9 mid-rollback kill (migrate fails → d.rollback → :7632) ──"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ dispatch exit was $ARC_DISPATCH_RC, expected 137 — the C9 mid-rollback kill did not fire (failing migrate must route newSbUpgradingFailure → Behind → d.rollback → :7632)" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ no flag file after the C9 kill — the mid-rollback crash must leave a service-held flag" >&2; exit 1; }
# The C9 kill lands MID-d.rollback — the DB volume restore may be in flight,
# so the DB container can be legitimately down/restarting at probe time (run
# 30308821408 read '(db-down/?)' exactly here). DB-down is a tolerated tick,
# never a verdict (the deploy-poll genre): await reachability with a bounded
# budget, THEN assert. Once readable the row must be in_progress either way —
# the kill preceded the rollback's terminal write, and a restored volume
# carries the pre-migrate backup's in_progress row.
ROW_READ_BUDGET_S="${ROW_READ_BUDGET_S:-120}"
_row=""
_row_deadline=$(( $(date +%s) + ROW_READ_BUDGET_S ))
while :; do
    _row="$(row_state)"
    [ "$_row" != "(db-down/?)" ] && break
    if [ "$(date +%s)" -ge "$_row_deadline" ]; then
        echo "✗ DB unreachable for ${ROW_READ_BUDGET_S}s after the mid-rollback kill — cannot read the row to validate the construction" >&2
        exit 1
    fi
    echo "  … DB not yet reachable after the mid-rollback kill (volume restore in flight) — tolerated tick"
    sleep 5
done
[ "$_row" = "in_progress" ] || { echo "✗ row is not 'in_progress' after the mid-rollback kill (got '$_row') — the rollback's terminal write must not have landed" >&2; exit 1; }
echo "  ✓ real mid-rollback crash: exit 137, flag present, row in_progress, tree restored to A"

# ── MANIPULATION 2: file-drop a deterministically-failing ≤-floor migration ──
echo ""
echo "── computing a genuinely-free migration slot AT OR BELOW the checkout's own DaemonSchemaFloor (dynamic, from the restored-A tree) ──"
GAP_OUT=$(VM_SCRIPT_INLINE compute-floor-gap << 'SCRIPT'
#!/bin/bash
set -euo pipefail
cd ~/statbus
FLOOR=$(grep -oE 'DaemonSchemaFloor int64 = [0-9]+' cli/internal/migrate/daemon_floor.go | grep -oE '[0-9]+$')
[ -n "$FLOOR" ] || { echo "FATAL: could not extract DaemonSchemaFloor" >&2; exit 1; }
mapfile -t VERSIONS < <(ls migrations/*.up.sql migrations/*.up.psql 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{14}' | sort -rn | awk -v floor="$FLOOR" '$1<=floor' | uniq)
V_TOP="${VERSIONS[0]:-}"; V_SECOND="${VERSIONS[1]:-}"
[ -n "$V_TOP" ] && [ -n "$V_SECOND" ] || { echo "FATAL: fewer than two real migrations at or below the floor ($FLOOR)" >&2; exit 1; }
INJECT_VERSION=$((V_SECOND + 1))
[ "$INJECT_VERSION" -lt "$V_TOP" ] || { echo "FATAL: no free slot between V_SECOND=$V_SECOND and V_TOP=$V_TOP" >&2; exit 1; }
echo "FLOOR=$FLOOR"; echo "V_TOP=$V_TOP"; echo "V_SECOND=$V_SECOND"; echo "INJECT_VERSION=$INJECT_VERSION"
SCRIPT
)
echo "$GAP_OUT"
FLOOR=$(echo "$GAP_OUT" | grep '^FLOOR=' | cut -d= -f2)
INJECT_VERSION=$(echo "$GAP_OUT" | grep '^INJECT_VERSION=' | cut -d= -f2)
[ -n "$FLOOR" ] && [ -n "$INJECT_VERSION" ] || { echo "✗ compute-floor-gap did not produce FLOOR + INJECT_VERSION" >&2; exit 1; }
BROKEN_MIGRATION="${INJECT_VERSION}_boot_migrate_churn_deterministic_fail.up.sql"
VM_EXEC bash -c "cd ~/statbus && printf 'SELECT 1/0;\n' > migrations/$BROKEN_MIGRATION"
VM_EXEC bash -c "test -f ~/statbus/migrations/$BROKEN_MIGRATION" || { echo "✗ the ≤-floor broken migration did not land" >&2; exit 1; }
echo "  ✓ file-drop: migrations/$BROKEN_MIGRATION (version=$INJECT_VERSION ≤ floor=$FLOOR, genuinely pending)"

# ── MANIPULATION 1: truncate the flag → invalid JSON (real crash-during-flag-write shape) ──
echo ""
echo "── truncating the flag file (a real partial write the corrupt-flag reader must reject) ──"
VM_EXEC bash -c "truncate -s 24 ~/statbus/$FLAG_PATH"
VM_EXEC bash -c "cd ~/statbus && python3 -c 'import json; json.load(open(\"$FLAG_PATH\"))' 2>/dev/null" && { echo "✗ the truncated flag is still valid JSON — corruption not achieved" >&2; exit 1; } || true
echo "  ✓ flag truncated to invalid JSON"

# ── daemon recovery boot: corrupt-flag reader removes the flag → flagless boot-migrate hits
#    the broken ≤-floor migration → exit 20 → the 144 guard → alive-idle ──
echo ""
echo "── starting the daemon (recovery boot): corrupt-flag reader → flagless boot-migrate → exit-20 → 144 alive-idle ──"
SINCE=$(arm_since)
vm_start_unit "$UPGRADE_UNIT"

echo ""
echo "── assert the REAL corrupt-flag reader fired (the flagless genesis) ──"
CORRUPT_WAIT=$(date +%s)
while true; do
    [ "$(journal_has "FLAG_CORRUPT: upgrade flag file unreadable" "$SINCE")" = "yes" ] && { echo "  ✓ journal: FLAG_CORRUPT … removing (recoverFromFlag rejected + removed the truncated flag)"; break; }
    [ $(( $(date +%s) - CORRUPT_WAIT )) -lt 180 ] || { echo "✗ the corrupt-flag reader never fired within 180s" >&2; exit 1; }
    sleep 3
done

echo ""
echo "── waiting for the unit to settle after the recovery boot (budget ${RESTART_WAIT_BUDGET_S}s) ──"
SETTLE_START=$(date +%s)
while true; do
    STATE=$(VM_EXEC bash -c "systemctl --user is-active '$UPGRADE_UNIT' 2>/dev/null || true" 2>/dev/null | tr -d ' \r\n')
    [ "$STATE" = "active" ] && { echo "  ✓ unit active (settled after $(( $(date +%s) - SETTLE_START ))s)"; break; }
    if [ $(( $(date +%s) - SETTLE_START )) -ge "$RESTART_WAIT_BUDGET_S" ]; then
        echo "✗ unit did not settle to 'active' within ${RESTART_WAIT_BUDGET_S}s (last: $STATE) — if it is churning through StartLimit this IS the regression AC#3 guards against" >&2
        VM_EXEC systemctl --user status "$UPGRADE_UNIT" --no-pager >&2 || true
        exit 1
    fi
    sleep 3
done

echo ""
echo "── watching ${NO_CHURN_WATCH_S}s for the ABSENCE of further churn (the load-bearing negative) ──"
sleep "$NO_CHURN_WATCH_S"

echo ""
echo "── assert A (scenario#1): unit alive-idle, NOT StartLimit-dead ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"

echo ""
echo "── assert B (scenario#2): NRestarts bounded + frozen (no churn loop) ──"
NR_BEFORE=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
[[ "$NR_BEFORE" =~ ^[0-9]+$ ]] || { echo "✗ could not parse NRestarts (got '$NR_BEFORE')" >&2; exit 1; }
# Bound, never pin: the flagless boot-migrate exit-20 is handled IN-PROCESS (log-once +
# continue), so the recovery boot itself adds NO restart; anything above 2 means the
# boot-migrate is churning the daemon — the StartLimit pathology 144 fixed.
[ "$NR_BEFORE" -le 2 ] || { echo "✗ NRestarts=$NR_BEFORE exceeds the bound of 2 — the ≤-floor migration IS churning the daemon" >&2; exit 1; }
sleep 30
NR_AFTER=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
[ "$NR_AFTER" = "$NR_BEFORE" ] || { echo "✗ NRestarts changed during the settle window ($NR_BEFORE → $NR_AFTER) — still crash-looping, not alive-idle" >&2; exit 1; }
echo "  ✓ NRestarts bounded ($NR_BEFORE) and frozen across the 30s settle window"

echo ""
echo "── assert C (scenario#3): row did NOT self-heal to 'completed' (genuinely-behind box) ──"
STILL_STATE=$(row_state)
[ "$STILL_STATE" != "completed" ] || { echo "✗ row self-healed to 'completed' — the box is genuinely behind (the ≤-floor migration never applied); a self-heal here is the false-convergence 039/192 forbids" >&2; exit 1; }
echo "  ✓ row is '$STILL_STATE' (non-completed, honest) — no false self-heal (scenario's 'failed' value differs; the no-false-completed PROPERTY holds)"

echo ""
echo "── assert D (scenario#4): the broken ≤-floor migration is never recorded as applied ──"
[ "$(migration_recorded "$INJECT_VERSION")" = "0" ] || { echo "✗ the broken ≤-floor migration ($INJECT_VERSION) must never be recorded — it fails on every attempt" >&2; exit 1; }
echo "  ✓ the broken migration never recorded (boot-migrate refuses the run on it, every boot)"

echo ""
echo "── assert E (scenario#5): the loud one-time 'BOOT MIGRATE FAILED DETERMINISTICALLY' banner in the arm window ──"
BANNER_COUNT=$(journal_count "BOOT MIGRATE FAILED DETERMINISTICALLY" "$SINCE")
[ "${BANNER_COUNT:-0}" -ge 1 ] || { echo "✗ expected the 'BOOT MIGRATE FAILED DETERMINISTICALLY' banner in the recovery-boot journal — the operator must be told loudly while staying alive" >&2; exit 1; }
echo "  ✓ loud diagnostic banner present ($BANNER_COUNT in the arm window — the exit-20 144 handler fired)"

echo ""
echo "── assert F (scenario#6): app/db/rest/worker keep serving (the daemon's own trouble does not take the stack down) ──"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo ""
echo "PASS: boot-migrate-churn-alive-idle — a REAL failing-lineage dispatch crashed at the REAL mid-rollback instant (C9, exit 137); the flag was truncated (real corrupt-flag reader removed it → flagless) and a deterministically-failing ≤-floor migration was file-dropped; the daemon's flagless boot-migrate hit it, exited 20, and the STATBUS-144 guard logged the loud banner ONCE and stayed ALIVE-IDLE — unit active through a ${NO_CHURN_WATCH_S}s watch, NRestarts bounded+frozen, row correctly not self-healed, the broken migration never recorded, app/db/rest/worker serving throughout — never the pre-144 StartLimit death. Real-path successor to scenario 4-rollback-abort-churn-then-alive-idle; on GREEN + the set-difference above, that scenario deletes and fabricate_resume_state's caller count drops to 1."
