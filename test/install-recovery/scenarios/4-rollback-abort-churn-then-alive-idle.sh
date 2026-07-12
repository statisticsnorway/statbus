#!/bin/bash
# Scenario: 4-rollback-abort-churn-then-alive-idle  (STATBUS-144 AC#3)
#
# THE SHAPE THIS PROVES: this is 4-rollback-abort-write-lands.sh WITHOUT its
# cleanup step, updated for two things that changed since that scenario's
# header first sketched this variant (STATBUS-144's own note, comment #3):
#
#   (1) STATBUS-138 (shared migration validity predicate): the failing
#       migration must be VALID-named (already true here — same far-future
#       14-digit-timestamp construction the base scenario uses, NOT an
#       invalid-version file; that class is now silently skipped-with-warn
#       and can never reach a churn at all).
#   (2) STATBUS-145 (floor-bounded boot-migrate): boot-migrate now runs
#       `--to DaemonSchemaFloor`, NOT to HEAD. The base scenario's far-future
#       migration (20990101000000-class, used ONLY to drive a ground-truth
#       Behind read and route recoverFromFlag into the ABORT branch) sits
#       WAY above the floor — boot-migrate's pending filter
#       (`m.Version > migrateTo -> skip`) NEVER attempts it, at any restart
#       count. Simply "not deleting" that file (the base header's original
#       plan) would NOT reproduce a churn today — it would just leave the
#       ABORT's own flagless self-heal to converge to 'completed', identical
#       to the base scenario's own end state. STATBUS-144's own comment #3
#       flags exactly this: "the inject must sit AT OR BELOW the daemon
#       floor to hit the boot path."
#
# INTERIM: deleted, TOGETHER WITH its base scenario 4-rollback-abort-write-lands.sh
# (which this variant inherits its ABORT construction from verbatim), when the
# restore-broke re-attempt arc goes green (same pattern as the r19 park
# scenario). Architect-ruled (STATBUS-071): this variant is a remaining
# fabricate_resume_state caller alongside 3-postswap-rune-wedge and its own
# base scenario; the base scenario's abort-row construction produces exactly
# the state that arc's re-attempt will build for real — one construction,
# three oracles now (this variant's alive-idle proof included) — so BOTH
# members of this family stay until that arc proves out.
#
# So this variant injects a SECOND, SEPARATE deterministically-failing
# migration whose version is AT OR BELOW the floor and GENUINELY PENDING —
# the actual "broken migration on disk" AC#3 talks about, the one every
# subsequent flagless boot-migrate will attempt and fail on. Its version is
# computed AT RUN TIME from the checked-out tree's own DaemonSchemaFloor
# constant and its own migrations/ directory (never hardcoded — the tree
# advances daily and a fixed version would silently stop being "at or below
# the floor" the moment a real migration lands past it). See
# compute-floor-gap.sh below for the exact derivation.
#
# EXPECTED BEHAVIOR (STATBUS-144, shipped 46f979a3a): the ABORT concludes in
# ONE pass exactly as the base scenario proves (state='failed',
# ROLLBACK_FAILED_GIT_CORRUPT, flag removed — that property is NOT re-proven
# here, it is inherited verbatim from the same construction). The next
# FLAGLESS boot's boot-migrate then hits the floor-bound broken migration and
# fails DETERMINISTICALLY (exit 20) — but instead of the pre-144 exit +
# systemd-restart-to-StartLimit-death churn, the daemon logs the loud
# "BOOT MIGRATE FAILED DETERMINISTICALLY" banner ONCE and CONTINUES into its
# main loop alive-idle: NO further process exit, NO further restart, the row
# STAYS 'failed' (the self-heal never fires — the box is genuinely not at
# target, the migration never applied), and the daemon keeps serving its
# normal duties (discovery, backup ticker) while app/db/rest/worker keep
# serving traffic.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/4-rollback-abort-churn-then-alive-idle.sh \
#     statbus-recovery-4-rollback-abort-churn-then-alive-idle

set -euo pipefail

VM_NAME="${1:-statbus-recovery-4-rollback-abort-churn-then-alive-idle}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
CONCLUDE_WAIT_BUDGET_S="${CONCLUDE_WAIT_BUDGET_S:-300}"
# How long to watch AFTER the settle window for a churn that must NOT
# happen — long enough to catch a StartLimit-class loop (RestartSec=30s ×
# several cycles) if the fix regressed, short enough not to waste VM time.
NO_CHURN_WATCH_S="${NO_CHURN_WATCH_S:-90}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 4-rollback-abort-churn-then-alive-idle  (STATBUS-144 AC#3 — abort-aftermath: alive-idle, not StartLimit death)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

UPGRADE_UNIT="statbus-upgrade@statbus.service"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_state_and_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'; }
migration_recorded() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = $1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n'; }

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

echo ""
echo "── staging HEAD + checking out the working tree ──"
upload_sb_to_vm "$VM_NAME"
VM_EXEC bash -c "cd ~/statbus && git fetch --depth 1 origin $HEAD_SHA 2>/dev/null || true; git -c advice.detachedHead=false checkout $HEAD_SHA"
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"

# ─────────────────────────────────────────────────────────────────────────
# compute-floor-gap — find a genuinely-free migration-version slot AT OR
# BELOW the checked-out tree's own DaemonSchemaFloor, computed on the VM
# from the ACTUAL tree (never hardcoded — see the header note). Prints
# FLOOR / V_TOP / V_SECOND / INJECT_VERSION as KEY=VALUE lines.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── computing a floor-bound migration-version slot (dynamic, from the checked-out tree) ──"
GAP_OUT=$(VM_SCRIPT_INLINE compute-floor-gap << 'SCRIPT'
#!/bin/bash
set -euo pipefail
cd ~/statbus
FLOOR=$(grep -oE 'DaemonSchemaFloor int64 = [0-9]+' cli/internal/migrate/daemon_floor.go | grep -oE '[0-9]+$')
if [ -z "$FLOOR" ]; then
    echo "FATAL: could not extract DaemonSchemaFloor from daemon_floor.go" >&2
    exit 1
fi
mapfile -t VERSIONS < <(ls migrations/*.up.sql migrations/*.up.psql 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{14}' | sort -rn | awk -v floor="$FLOOR" '$1<=floor' | uniq)
V_TOP="${VERSIONS[0]:-}"
V_SECOND="${VERSIONS[1]:-}"
if [ -z "$V_TOP" ] || [ -z "$V_SECOND" ]; then
    echo "FATAL: could not find two real migrations at or below the floor ($FLOOR)" >&2
    exit 1
fi
INJECT_VERSION=$((V_SECOND + 1))
if [ "$INJECT_VERSION" -ge "$V_TOP" ]; then
    echo "FATAL: no free slot between V_SECOND=$V_SECOND and V_TOP=$V_TOP (adjacent-by-1s collision)" >&2
    exit 1
fi
echo "FLOOR=$FLOOR"
echo "V_TOP=$V_TOP"
echo "V_SECOND=$V_SECOND"
echo "INJECT_VERSION=$INJECT_VERSION"
SCRIPT
)
echo "$GAP_OUT"
FLOOR=$(echo "$GAP_OUT" | grep '^FLOOR=' | cut -d= -f2)
V_TOP=$(echo "$GAP_OUT" | grep '^V_TOP=' | cut -d= -f2)
V_SECOND=$(echo "$GAP_OUT" | grep '^V_SECOND=' | cut -d= -f2)
INJECT_VERSION=$(echo "$GAP_OUT" | grep '^INJECT_VERSION=' | cut -d= -f2)
[ -n "$FLOOR" ] && [ -n "$V_TOP" ] && [ -n "$V_SECOND" ] && [ -n "$INJECT_VERSION" ] || {
    echo "✗ compute-floor-gap did not produce all four values" >&2; exit 1;
}
echo "  ✓ floor=$FLOOR, real tip=$V_TOP, injecting a broken migration at $INJECT_VERSION (between $V_SECOND and $V_TOP)"

echo ""
echo "── steady-state pre-apply, capped BELOW the real tip (leaves $V_TOP genuinely pending, freeing the slot for the injected migration) ──"
VM_EXEC bash -c "cd ~/statbus && timeout 600 ./sb migrate up --to $V_SECOND --verbose"

# ─────────────────────────────────────────────────────────────────────────
# The floor-bound broken migration — this is "the broken migration on disk"
# AC#3 talks about. It stays on disk for the ENTIRE scenario (no cleanup —
# that is the whole point of this variant). Its version sorts BEFORE
# $V_TOP, so it is the first pending file boot-migrate reaches and fails on;
# $V_TOP is never attempted while it remains broken (runUp stops at the
# first failure — same "the applier refuses the whole run on one bad file"
# semantics the base scenario's header documents).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── writing the floor-bound deterministically-failing migration (division by zero, valid version, GENUINELY pending ≤ floor) ──"
BROKEN_FLOOR_MIGRATION="${INJECT_VERSION}_churn_variant_floor_bound_deterministic_fail.up.sql"
VM_EXEC bash -c "cd ~/statbus && printf 'SELECT 1/0;\n' > migrations/$BROKEN_FLOOR_MIGRATION"
VM_EXEC bash -c "test -f ~/statbus/migrations/$BROKEN_FLOOR_MIGRATION" || { echo "✗ floor-bound migration did not land" >&2; exit 1; }
echo "  ✓ migrations/$BROKEN_FLOOR_MIGRATION written (version=$INJECT_VERSION ≤ floor=$FLOOR)"

# ─────────────────────────────────────────────────────────────────────────
# The far-future ground-truth-Behind driver — IDENTICAL construction to
# 4-rollback-abort-write-lands.sh (valid 14-digit far-future version, body
# fails deterministically). Its ONLY job is to make ground truth read Behind
# so recoverFromFlag's Resuming branch routes into rollback()'s ABORT
# branch. It sits WAY above the floor so it never interacts with boot-migrate
# — the two injected migrations are deliberately independent, each doing
# exactly one job.
# ─────────────────────────────────────────────────────────────────────────
GROUND_TRUTH_MIGRATION='20990101000000_churn_variant_ground_truth_behind_driver.up.sql'
echo ""
echo "── writing the ground-truth-Behind driver migration (far-future, same construction as the base scenario) ──"
VM_EXEC bash -c "cd ~/statbus && printf 'SELECT 1/0;\n' > migrations/$GROUND_TRUTH_MIGRATION"
VM_EXEC bash -c "test -f ~/statbus/migrations/$GROUND_TRUTH_MIGRATION" || { echo "✗ ground-truth-Behind migration did not land" >&2; exit 1; }
echo "  ✓ migrations/$GROUND_TRUTH_MIGRATION written"

echo ""
echo "── fabricating the in_progress row + service-held flag (dead pid), then patching phase to 'resuming' (identical to the base scenario) ──"
fabricate_resume_state "$VM_NAME" "$HEAD_SHA" >/dev/null
VM_EXEC bash -c "cd ~/statbus && sed -i 's/\"phase\":\"post_swap\"/\"phase\":\"resuming\"/' tmp/upgrade-in-progress.json"
VM_EXEC bash -c "grep -q '\"phase\":\"resuming\"' ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ phase patch to 'resuming' did not land" >&2
    exit 1
}
echo "  ✓ flag fabricated + patched: phase=resuming, commit_sha=$HEAD_SHA"

echo ""
echo "── restarting upgrade-service unit onto HEAD (this boot runs the ABORT branch — identical mechanism to the base scenario) ──"
vm_restart_unit "$UPGRADE_UNIT"
echo "  ✓ unit restart issued"

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
        echo "✗ row still '$FINAL_STATE' after ${CONCLUDE_WAIT_BUDGET_S}s — the ABORT branch did not conclude" >&2
        exit 1
    fi
    sleep 5
done

echo ""
echo "── confirming the ABORT terminal itself (inherited property, same assertion as the base scenario) ──"
EARLY_ROW=$(row_state_and_error)
EARLY_STATE=$(echo "$EARLY_ROW" | cut -d'|' -f1)
EARLY_ERROR=$(echo "$EARLY_ROW" | cut -d'|' -f2-)
[ "$EARLY_STATE" = "failed" ] || { echo "✗ expected the ABORT terminal 'failed' on the early read, got '$EARLY_STATE'" >&2; exit 1; }
echo "$EARLY_ERROR" | grep -E "ROLLBACK_FAILED_GIT_CORRUPT" >/dev/null || { echo "✗ early error does not match ROLLBACK_FAILED_GIT_CORRUPT: $EARLY_ERROR" >&2; exit 1; }
echo "  ✓ ABORT terminal landed correctly: state='failed', error matches ROLLBACK_FAILED_GIT_CORRUPT"

assert_flag_file_absent "$VM_NAME"
echo "  ✓ flag removed — the ABORT's own terminal write landed (STATBUS-136)"

# ─────────────────────────────────────────────────────────────────────────
# THE DIFFERENCE FROM THE BASE SCENARIO: no cleanup. The floor-bound broken
# migration is still on disk. Every subsequent flagless boot-migrate will
# hit it. Wait for the unit's own post-ABORT restart to settle, THEN watch
# for the ABSENCE of further churn — the load-bearing negative assertion.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for the unit to settle after its own post-ABORT restart (budget ${RESTART_WAIT_BUDGET_S}s) ──"
SETTLE_START=$(date +%s)
while :; do
    NOW=$(date +%s); ELAPSED=$((NOW - SETTLE_START))
    STATE=$(VM_EXEC systemctl --user is-active "$UPGRADE_UNIT" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$STATE" = "active" ] && { echo "  ✓ unit active (settled after ${ELAPSED}s)"; break; }
    if [ "$ELAPSED" -ge "$RESTART_WAIT_BUDGET_S" ]; then
        echo "✗ unit did not settle to 'active' within ${RESTART_WAIT_BUDGET_S}s (last state: $STATE) — if it is churning through StartLimit, this IS the regression AC#3 guards against" >&2
        VM_EXEC systemctl --user status "$UPGRADE_UNIT" --no-pager >&2 || true
        exit 1
    fi
    sleep 3
done

echo ""
echo "── watching ${NO_CHURN_WATCH_S}s for the ABSENCE of further churn (the load-bearing negative assertion) ──"
sleep "$NO_CHURN_WATCH_S"

echo ""
echo "── assert 1: unit alive-idle, NOT StartLimit-dead ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"

echo ""
echo "── assert 2: NRestarts bounded at 1 (the ABORT's own os.Exit(1) — the ONLY legitimate restart in this scenario's lifetime; anything higher means the floor-bound migration IS churning the daemon, the exact StartLimit-death pathology STATBUS-144 fixed) ──"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 1

echo ""
echo "── assert 3: row STAYS 'failed' — no flagless self-heal, because the box is genuinely NOT at target (the floor-bound migration never applied) ──"
STILL_STATE=$(row_state)
[ "$STILL_STATE" = "failed" ] || { echo "✗ expected state to STAY 'failed' (no self-heal — the box is genuinely behind), got '$STILL_STATE'" >&2; exit 1; }
echo "  ✓ row still 'failed' — correctly did NOT self-heal to completed"

echo ""
echo "── assert 4: neither the floor-bound broken migration nor the real migration behind it ($V_TOP) is recorded ──"
[ "$(migration_recorded "$INJECT_VERSION")" = "0" ] || { echo "✗ the floor-bound broken migration must never be recorded as applied" >&2; exit 1; }
[ "$(migration_recorded "$V_TOP")" = "0" ] || { echo "✗ $V_TOP must never be reached — the broken migration ahead of it stops the whole run" >&2; exit 1; }
echo "  ✓ neither migration applied — boot-migrate stopped exactly at the broken file, every restart, without ever advancing"

echo ""
echo "── assert 5: the loud one-time diagnostic banner appears in the unit's journal ──"
BANNER_COUNT=$(VM_EXEC bash -c "journalctl --user -u '$UPGRADE_UNIT' --no-pager 2>/dev/null | grep -c 'BOOT MIGRATE FAILED DETERMINISTICALLY' || true" | tr -d ' \r\n')
[ "${BANNER_COUNT:-0}" -ge 1 ] || { echo "✗ expected the 'BOOT MIGRATE FAILED DETERMINISTICALLY' banner in the unit journal — the operator must be told loudly, even while staying alive" >&2; exit 1; }
echo "  ✓ loud diagnostic banner present ($BANNER_COUNT occurrence(s) — exactly 1 expected under the settled NRestarts=1 bound)"

echo ""
echo "── assert 6: app/db/rest/worker keep serving (the daemon's own trouble does not take the stack down) ──"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo ""
echo "PASS: 4-rollback-abort-churn-then-alive-idle (STATBUS-144 AC#3 — the abort-aftermath state (row='failed', flag removed, a VALID-named floor-bound broken migration left on disk) leaves the daemon ALIVE-IDLE: NRestarts bounded at 1, unit active throughout a ${NO_CHURN_WATCH_S}s watch window, the loud diagnostic banner fired once, row correctly stayed 'failed' with no false self-heal, and app/db/rest/worker kept serving — never the pre-fix StartLimit death)"
