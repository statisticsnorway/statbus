#!/bin/bash
# Arc: postswap-stopped-proxy-recovery  (STATBUS-143 AC#2)
#
# REBUILT ON REAL-PATH CONSTRUCTION (architect carve-out ruling, 2026-07-12):
# a crashed upgrade is real-path producible — real register/schedule of a
# throwaway target → daemon claims → inject.KillHere at a real post-swap
# step, the SAME kill-family machinery postswap-container-restart-kill-arc.sh
# already proves (STATBUS_INJECT_AT=killed-by-system-during-container-restart,
# service.go: fires AFTER `docker compose up -d --no-build <step11 services>`
# returns ok — meaning ALL services INCLUDING the proxy have been started —
# but BEFORE step 12's health check confirms them). The proxy state (stopped)
# is then PURE ENVIRONMENT MANIPULATION layered on top of that real crash —
# same class as corrupting git objects or filling disk: the proxy genuinely
# IS stopped, not a fabricated resume-state row. Neither shape is
# dead-producer class, so fabricate_resume_state gains no new caller here
# (the earlier scenario-style draft that used it was withdrawn in favor of
# this construction).
#
# THE SHAPE THIS PROVES: same claim as before the rebuild — a crashed
# upgrade whose proxy container is STOPPED (not removed) must recover
# AUTONOMOUSLY. Before STATBUS-143's fix, EnsureDBReachable probed the DB via
# docker-exec straight into the db container — a DIFFERENT route than the
# real recovery connection (TCP through the Caddy layer4 proxy) — so a
# stopped proxy was invisible to the probe: it PASSED against a healthy
# container while the real connection would have refused, and the
# start-fallback (which only knew `compose start db`) never got a chance to
# resume the proxy too. Fix shipped 06cf8415f: EnsureDBReachable now dials
# the SAME route the connection uses (recoveryDSN(), TCP via
# CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT), so the probe correctly FAILS on a
# stopped proxy, and StartDBForRecovery's asymmetric-safe start now covers
# the whole route (`docker compose start db proxy` — starts existing
# containers only, never recreates).
#
# STATE-ARRIVAL SHAPE (the only part this rebuild changed)
#   1. arc_prepare_box: install A (BASE_SHA) → health → daemon active →
#      trust arc signer → demo data + snapshot.
#   2. register B (daemon up) → wait for docker_images_status='ready'.
#   3. arc_schedule_daemon_down B → persistent 'scheduled' row.
#   4. arc_install_dispatch_with_inject killed-by-system-during-container-restart
#      → ./sb install inline-dispatches B → the REAL post-swap kill fires
#      after step 11 (all services, including proxy, started) but before
#      step 12 (health) → RED: flag present (Phase=Resuming), row
#      in_progress, DB up, ALL containers genuinely running.
#   5. Confirm RED (flag + row in_progress) — same shape
#      postswap-container-restart-kill-arc.sh already proves.
#   6. ENVIRONMENT MANIPULATION (this arc's own variable): `docker compose
#      stop proxy` — the proxy is genuinely stopped, an existing container
#      merely not running (the legitimate mid-upgrade shape: a prior
#      in-flight upgrade can leave containers stopped).
#
# From here down, every assertion is UNCHANGED from the original build:
# recovery `./sb install` must show the STATBUS-143 start-fallback line,
# resume the proxy, converge to completed with zero restores, data intact,
# and a second install must read nothing-scheduled.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.
#
# Hetzner-runnability: BUILD-ONLY at authoring time — the VM run is the
# oracle (mechanic-buildable per STATBUS-143 comment #3; queued behind the
# 154/wave-8 closure).

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-stopped-proxy-recovery}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
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

# _dump_stopped_proxy_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-container-restart-kill-arc.sh's own diagnostics function), extended
# with `docker compose ps -a` so a red run shows the proxy's exact state
# without needing a kept VM.
_dump_stopped_proxy_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_stopped_proxy_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-stopped-proxy-recovery  (STATBUS-143 AC#2 — real kill + real stop → autonomous recovery)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

# PROBES OBSERVE, ASSERTS JUDGE (STATBUS-143 probe contract; README "Probe
# conventions"): a probe ALWAYS exits 0 and returns a nameable value ('(unknown)'
# on any transport/command hiccup), so it can never die inside $() under `set -e`
# one line before its own assertion. proxy_state races the resume's in-flight
# container restart, so the safe terminal is load-bearing here — its ABSENCE
# killed this arc (rc=1 at :140, the probe dying one line before its tripwire).
proxy_state() {
    VM_EXEC bash -c "cd ~/statbus && docker compose ps -a --format '{{.Service}} {{.State}}' | awk '\$1==\"proxy\"{print \$2}'" 2>/dev/null | tr -d ' \r\n' || echo '(unknown)'
}
row_cols() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, recovery_attempts, recovery_parked_at IS NOT NULL, rolled_back_at IS NOT NULL, error IS NOT NULL FROM public.upgrade WHERE commit_sha = '${B_FULL}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r' || echo '(unknown)'
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
ROW_STATE_RED=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '${B_FULL}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo '(unknown)')
[ "$ROW_STATE_RED" = "in_progress" ] || { echo "✗ expected row in_progress after the kill, got '$ROW_STATE_RED'" >&2; exit 1; }
# The inject fires DURING the resume's start-services (container restart), so the
# proxy reaching "running" is an EVENTUAL state — the resume's orphaned
# `docker compose up -d` must finish bringing it up. Poll (the safe probe makes
# this loop safe under `set -e`) until it settles or the budget expires. The
# precondition stays HARD: running within the budget, or refuse loudly naming the
# observed value — a settle-wait establishes the precondition honestly, it does
# NOT weaken it (STATBUS-143 ruling).
PROXY_SETTLE_BUDGET_S="${PROXY_SETTLE_BUDGET_S:-60}"
PROXY_BEFORE=""
_proxy_deadline=$((SECONDS + PROXY_SETTLE_BUDGET_S))
while :; do
    PROXY_BEFORE=$(proxy_state)
    [ "$PROXY_BEFORE" = "running" ] && break
    [ "$SECONDS" -lt "$_proxy_deadline" ] || break
    sleep 3
done
[ "$PROXY_BEFORE" = "running" ] || { echo "✗ precondition: proxy must be running within ${PROXY_SETTLE_BUDGET_S}s post-kill (step 11 completed before the kill site; the resume's container restart must settle) — got '$PROXY_BEFORE'" >&2; exit 1; }
echo "  ✓ RED confirmed: flag present, row in_progress, proxy genuinely running (real crash, real containers)"

echo ""
echo "── ENVIRONMENT MANIPULATION: stopping the proxy container (docker compose stop — existing, merely not running) ──"
VM_EXEC bash -c "cd ~/statbus && docker compose stop proxy"
PROXY_STOPPED=$(proxy_state)
case "$PROXY_STOPPED" in
    exited|"") echo "  ✓ proxy stopped: state=$PROXY_STOPPED" ;;
    *) echo "✗ expected the proxy to be stopped (state=exited), got '$PROXY_STOPPED'" >&2; exit 1 ;;
esac

# ─────────────────────────────────────────────────────────────────────────
# From here down: UNCHANGED from the original build — recovery dispatch +
# every assertion.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── ./sb install (recovery; expect: DB-not-reachable on the real route → start-fallback resumes db+proxy → forward resume → completed) ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${TAKEOVER_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install exit: $INSTALL_RC"
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ install did not exit 0 — a stopped-but-present proxy must recover autonomously" >&2; exit 1; }

echo ""
echo "── assert 1: the route-aware probe caught the stopped proxy (start-fallback line fired) ──"
grep -q "Detected install state: crashed-upgrade" "$INSTALL_OUT" || {
    echo "✗ expected 'Detected install state: crashed-upgrade' in the install output" >&2; exit 1; }
echo "  ✓ ladder detected crashed-upgrade"
grep -q "DB not reachable, attempting \`docker compose start db\`" "$INSTALL_OUT" || {
    echo "✗ expected the STATBUS-143 start-fallback line — without it the probe did NOT correctly fail on the stopped-proxy route (the pre-143 false-pass this fix kills)" >&2
    exit 1
}
echo "  ✓ EnsureDBReachable correctly failed on the real route (proxy stopped) and triggered the start-fallback"

echo ""
echo "── assert 2: the proxy is RUNNING again post-recovery (AC#2: start-existing extended to the proxy) ──"
PROXY_AFTER=$(proxy_state)
[ "$PROXY_AFTER" = "running" ] || { echo "✗ expected proxy running after recovery, got '$PROXY_AFTER' — StartDBForRecovery must resume the whole route, not just the db" >&2; exit 1; }
echo "  ✓ proxy running again ($PROXY_BEFORE → stopped → $PROXY_AFTER)"

echo ""
echo "── assert 3: row converged forward, zero restores ──"
ROW=$(row_cols)
echo "  terminal row: $ROW  (state|attempts|parked|rolled_back|error)"
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ROLLED=$(echo "$ROW" | cut -d'|' -f4)
[ "$ROW_STATE" = "completed" ] || { echo "✗ expected state='completed', got '$ROW_STATE'" >&2; exit 1; }
[ "$ROW_ROLLED" = "f" ] || { echo "✗ expected rolled_back_at IS NULL — a stopped-but-present proxy must never trigger a restore" >&2; exit 1; }
echo "  ✓ row: completed, never rolled back"

assert_flag_file_absent "$VM_NAME"
echo ""
echo "── assert 4: health + data intact ──"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_active "$VM_NAME" "statbus-upgrade@statbus.service" "active"
rm -f "$INSTALL_OUT"

echo ""
echo "── second ./sb install (idempotence coda: nothing-scheduled) ──"
INSTALL_OUT2=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT2" 2>&1
INSTALL_RC2=$?
set -e
echo "  second ./sb install exit: $INSTALL_RC2"
[ "$INSTALL_RC2" -eq 0 ] || { cat "$INSTALL_OUT2"; echo "✗ second install did not exit 0" >&2; exit 1; }
grep -q "Detected install state: nothing-scheduled" "$INSTALL_OUT2" || {
    cat "$INSTALL_OUT2"; echo "✗ expected 'Detected install state: nothing-scheduled' on the second install" >&2; exit 1;
}
echo "  ✓ second install detected nothing-scheduled"
rm -f "$INSTALL_OUT2"

echo ""
echo "PASS: postswap-stopped-proxy-recovery (STATBUS-143 AC#2 — real register/schedule/kill at the post-swap container-restart site, THEN a genuinely stopped proxy: the route-aware probe correctly detected the unreachable route, the asymmetric-safe start resumed db AND proxy, recovery converged to completed with zero restores, data intact, second install idempotent)"
