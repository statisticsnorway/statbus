#!/bin/bash
# Arc: postswap-severed-proxy-refusal  (STATBUS-143 AC#4)
#
# REBUILT ON REAL-PATH CONSTRUCTION (architect carve-out ruling, 2026-07-12):
# same rebuild rationale as postswap-stopped-proxy-recovery-arc.sh (its
# sibling — read that file's header for the full construction argument). A
# crashed upgrade is real-path producible via the existing kill-family
# machinery (real register/schedule → inject.KillHere at the real post-swap
# container-restart site); the proxy state (REMOVED, not merely stopped) is
# then pure environment manipulation on top of that real crash — the same
# class as corrupting git objects or filling disk. fabricate_resume_state
# gains no new caller.
#
# THE SHAPE THIS PROVES: unchanged claim — a crashed upgrade whose proxy
# container is MISSING (removed) must produce an ACTIONABLE NAMED REFUSAL,
# never a silent identical connection-refused loop with no way out — and,
# once the operator takes the refusal's own advertised remedy, recovery must
# converge. This is the ticket's NORTH STAR verbatim: "a crashed upgrade must
# never become a dead end the operator's canonical action (run install
# again) cannot escape."
#
# Fix shipped 06cf8415f: proxyContainerMissing (exec.go) distinguishes
# MISSING (docker compose ps -a has NO record — severed route) from STOPPED
# (record exists, not running — the sibling arc's case). StartDBForRecovery
# refuses to auto-recreate a missing proxy (`up -d proxy` under the
# operator's binary can image-mismatch the flag target — the rc.66 → rc.67
# lesson) and instead returns newProxyRouteMissingError(): a category-3
# refusal naming the state and the manual remedy (`docker compose up -d
# proxy`, with the version caveat).
#
# STATE-ARRIVAL SHAPE (the only part this rebuild changed)
#   1-5. Identical to the sibling arc: arc_prepare_box → register B → daemon-
#        down schedule → arc_install_dispatch_with_inject
#        killed-by-system-during-container-restart → confirm RED (flag
#        present, row in_progress, ALL containers incl. proxy genuinely up —
#        step 11 completed before the kill site).
#   6. ENVIRONMENT MANIPULATION (this arc's own variable): `docker compose
#      rm -f -s proxy` — stop-then-remove, leaving ZERO record for the
#      service (proxyContainerMissing's exact "missing" shape).
#
# From here down, every assertion is UNCHANGED from the original build:
# three `./sb install` attempts — (1) actionable refusal, non-zero exit, no
# corruption; (2) the SAME refusal reproduced (a stable, non-escalating
# signal); (3) after the operator's own advertised remedy, exit 0 and
# convergence to completed with data intact.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.
#
# Hetzner-runnability: BUILD-ONLY at authoring time — the VM run is the
# oracle (mechanic-buildable per STATBUS-143 comment #3; queued behind the
# 154/wave-8 closure).

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-severed-proxy-refusal}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
TAKEOVER_BUDGET_S="${TAKEOVER_BUDGET_S:-1200}"
INJECT_CLASS="killed-by-system-during-container-restart"

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

# _dump_severed_proxy_failure_diagnostics — STATBUS-155 rider, same shape as
# the sibling arc's, extended with `docker compose ps -a` for the proxy's
# exact record state.
_dump_severed_proxy_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + daemon journal + row state + container ps) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "── container state (docker compose ps -a) ──" >&2
    VM_EXEC bash -c "cd ~/statbus && docker compose ps -a" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_severed_proxy_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-severed-proxy-refusal  (STATBUS-143 AC#4 — real kill + real removal → actionable refusal, then escape)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

proxy_present() {
    VM_EXEC bash -c "cd ~/statbus && docker compose ps -a --format '{{.Service}}' | grep -qx proxy && echo yes || echo no" 2>/dev/null | tr -d ' \r\n'
}
row_state() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '${B_FULL}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"
}

# run_install <out-file> — attempts ./sb install, never fails the arc itself
# on a non-zero exit (the refusal legs EXPECT non-zero); returns the real
# exit code via echo so callers can branch. (Unchanged from the original build.)
run_install() {
    local out_file="$1"
    local rc=0
    set +e
    timeout "${TAKEOVER_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
        "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
        > "$out_file" 2>&1
    rc=$?
    set -e
    echo "$rc"
}

# ── A: install + prepare; register B; schedule daemon-down; dispatch with the REAL post-swap kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS"

echo ""
echo "── verifying RED state (flag Resuming; row in_progress; DB + ALL containers, incl. proxy, genuinely up) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
[ "$(row_state)" = "in_progress" ] || { echo "✗ expected row in_progress after the kill, got '$(row_state)'" >&2; exit 1; }
[ "$(proxy_present)" = "yes" ] || { echo "✗ precondition: proxy must be present post-kill (step 11 completed before the kill site)" >&2; exit 1; }
echo "  ✓ RED confirmed: flag present, row in_progress, proxy genuinely present (real crash, real containers)"

echo ""
echo "── ENVIRONMENT MANIPULATION: severing the proxy route (docker compose rm -f -s proxy — ZERO record, the missing case) ──"
VM_EXEC bash -c "cd ~/statbus && docker compose rm -f -s proxy"
[ "$(proxy_present)" = "no" ] || { echo "✗ proxy still present after rm -f -s — the severed-route precondition did not land" >&2; exit 1; }
echo "  ✓ proxy container removed entirely (docker compose ps -a has no record)"

# ─────────────────────────────────────────────────────────────────────────
# From here down: UNCHANGED from the original build — three recovery
# attempts + every assertion.
# ─────────────────────────────────────────────────────────────────────────

echo ""
echo "── ./sb install attempt 1 (expect: DB-not-reachable → start-fallback finds NO proxy → actionable refusal, non-zero exit) ──"
OUT1=$(mktemp)
RC1=$(run_install "$OUT1")
cat "$OUT1"
echo "  attempt 1 exit: $RC1"
[ "$RC1" -ne 0 ] || { echo "✗ expected non-zero exit — a severed proxy route cannot recover without operator action" >&2; exit 1; }

grep -q "DB not reachable, attempting \`docker compose start db\`" "$OUT1" || {
    echo "✗ expected the start-fallback attempt line before the refusal" >&2; exit 1; }
grep -q "the db's connection route — the proxy container — does not exist" "$OUT1" || {
    echo "✗ expected the STATBUS-143 category-3 named refusal (proxy-route-missing) text" >&2; exit 1; }
grep -q "docker compose up -d proxy" "$OUT1" || {
    echo "✗ expected the refusal to name the operator's manual remedy" >&2; exit 1; }
grep -qE "CADDY_DB_BIND_ADDRESS|proxy" "$OUT1" || {
    echo "✗ expected the refusal to name the route (CADDY_DB_BIND_ADDRESS/proxy)" >&2; exit 1; }
echo "  ✓ actionable named refusal fired: names the missing-route state, the CADDY_DB_BIND route, and the operator remedy"

echo ""
echo "── assert: the refusal did NOT half-complete or corrupt anything ──"
[ "$(row_state)" = "in_progress" ] || { echo "✗ expected row to STAY in_progress after a refusal (no half-completion)" >&2; exit 1; }
echo "  ✓ row still in_progress"
[ "$(VM_EXEC bash -c 'test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no' 2>/dev/null | tr -d ' \r\n')" = "yes" ] || {
    echo "✗ expected the flag to STAY present after a refusal (recovery never completed)" >&2; exit 1;
}
echo "  ✓ flag still present"
if grep -qE "auto-restor|Restoring database|rolled back to the previous version" "$OUT1"; then
    echo "✗ a refusal must NEVER trigger a restore — restore/rollback markers found in the output" >&2; exit 1
fi
echo "  ✓ no restore/rollback markers — the refusal is a pure stop, not a destructive guess"
rm -f "$OUT1"

echo ""
echo "── ./sb install attempt 2 (same severed state, unresolved — expect the SAME actionable refusal, not degradation) ──"
OUT2=$(mktemp)
RC2=$(run_install "$OUT2")
cat "$OUT2"
echo "  attempt 2 exit: $RC2"
[ "$RC2" -ne 0 ] || { echo "✗ expected non-zero exit again — the route is still severed" >&2; exit 1; }
grep -q "the db's connection route — the proxy container — does not exist" "$OUT2" || {
    echo "✗ expected the SAME actionable refusal to reappear on a second attempt (a stable signal, not an opaque or different error)" >&2; exit 1; }
echo "  ✓ same actionable refusal reproduced — a stable, non-escalating signal on retry"
rm -f "$OUT2"

echo ""
echo "── operator remedy: docker compose up -d proxy (the refusal's own advertised manual option) ──"
VM_EXEC bash -c "cd ~/statbus && docker compose up -d proxy"
[ "$(proxy_present)" = "yes" ] || { echo "✗ proxy still not present after the remedy" >&2; exit 1; }
echo "  ✓ proxy recreated"

echo ""
echo "── ./sb install attempt 3 (route restored — expect: exit 0, forward resume, completed) ──"
OUT3=$(mktemp)
RC3=$(run_install "$OUT3")
cat "$OUT3"
echo "  attempt 3 exit: $RC3"
[ "$RC3" -eq 0 ] || { echo "✗ expected exit 0 once the proxy route is restored — this is the NORTH STAR: never an unrecoverable dead end" >&2; exit 1; }
rm -f "$OUT3"

FINAL_STATE=$(row_state)
[ "$FINAL_STATE" = "completed" ] || { echo "✗ expected state='completed' after the operator's remedy + re-run, got '$FINAL_STATE'" >&2; exit 1; }
echo "  ✓ row completed — the dead end is escaped by the operator's canonical action"

assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_active "$VM_NAME" "statbus-upgrade@statbus.service" "active"

echo ""
echo "PASS: postswap-severed-proxy-refusal (STATBUS-143 AC#4 — real register/schedule/kill at the post-swap container-restart site, THEN a genuinely removed proxy: two attempts each produced the SAME actionable named refusal (never a corrupt/half-complete state, never a restore), and once the operator ran the refusal's own advertised remedy, a third install converged to completed with data intact — the NORTH STAR's never-a-dead-end contract holds)"
