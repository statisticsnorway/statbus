#!/bin/bash
# Scenario: 5-install-stage-a-killed-migrate
#
# Validates: cleanOrphanSessions Phase 1 (statistical_* psql/migrate-sql subprocess
# sweep) firing in its REAL trigger context — alongside the advisory-lock holder a
# killed migrate also leaves. Fix 5b forward-recovery then completes the migration.
#
# ── WHY THIS SCENARIO WAS RE-DESIGNED (STATBUS-029, architect 2026-06-15) ──
# The prior version synthesized ONLY a bare `./sb psql -c "INSERT statistical_history
# … pg_sleep"` (app='psql', NO advisory lock) and asserted recovery killed it. That
# was MIS-MODELED and RED-by-design:
#   • checkSessionsClean (the GATE for cleanOrphanSessions) flags a statistical_*
#     psql/migrate-sql ONLY when query_start is > 5 minutes old (install.go), so a
#     FRESH one is invisible → cleanOrphanSessions never even runs.
#   • A bare-psql, no-advisory, fresh statistical_* backend is SQL-indistinguishable
#     from a LIVE manual/external client. The gate CORRECTLY declines to force-kill
#     it on sight (un-aging the gate would over-kill live clients — a regression).
#   So the old assertion demanded an unsafe kill the product intentionally avoids.
#
# A REALISTIC killed-migrate orphan is NOT a lone bare psql. acquireAdvisoryLock
# (cli/internal/migrate/migrate.go) holds the migrate_up advisory lock on a Go conn,
# and the migration's SQL runs in psql SUBPROCESSES. When the owning process dies,
# it leaves BOTH: (a) an idle advisory-lock holder, and (b) a statistical_* psql
# subprocess. The advisory holder is what TRIGGERS the gate; Phase 1 then sweeps the
# subprocess. THIS scenario synthesizes that complete fingerprint and asserts
# recovery cleans BOTH.
#
# ADVISORY HOLDER SHAPE — empty application_name (NOT a `statbus-migrate-<pid>` tag):
#   The gate's advisory_holders subquery counts only EMPTY-app holders, so an
#   empty-app holder deterministically triggers cleanup on CURRENT code → this
#   scenario is GREEN. The empty-app holder is itself a real shape — the rune PID-9962
#   pre-Fix-6a killed-migrate orphan (the same shape 5-install-stage-d covers in
#   isolation; here it co-occurs with the subprocess that Phase 1 must sweep).
#   A TAGGED `statbus-migrate-<deadpid>` holder is NOT counted by the gate — that is
#   the genuine fresh-orphan detection gap filed as STATBUS-055 (PID-liveness-aware
#   gate detection), to be proven RED→GREEN under its own fix. This scenario stays
#   GREEN-on-current-code; it does not double as the 055 RED.
#
# Setup: install fresh. Synthesize the empty-app advisory holder + a statistical_*
# psql subprocess (both orphaned via the docker-exec-survives-host-SIGKILL path).
# Capture each one's backend PID. Re-run install → cleanOrphanSessions fires (gate
# saw the advisory holder) → Phase 2 reaps the holder + Phase 1 sweeps the subprocess.
# Assert BOTH specific backend PIDs are gone, install completes, health passes.
#
# Usage:
#   ./test/install-recovery/scenarios/5-install-stage-a-killed-migrate.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-stage-a-killed-migrate}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-stage-a-killed-migrate"
echo "  Validates: cleanOrphanSessions Phase 1 subprocess sweep (in its real"
echo "  advisory-holder trigger context) + Phase 2 holder reap; Fix 5b recovery"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Initial install — fresh, healthy.
echo ""
echo "── initial install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3a. Synthesize the advisory-lock holder (empty app_name) — the killed migrate's
#     main connection. This is what TRIGGERS the gate (checkSessionsClean's
#     advisory_holders subquery) so cleanOrphanSessions runs at all.
echo ""
simulate_advisory_zombie_empty_app "$VM_NAME"

# Capture THIS holder's backend PID now, while it is the only empty-app advisory
# holder. (The install's own boot-migrate also holds migrate_up with an empty
# app_name during step 12, so a broad post-install count would false-positive on
# it — assert the SPECIFIC captured PID, mirroring 5-install-stage-d.)
HOLDER_PID=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT a.pid FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND COALESCE(a.application_name, '') = '' AND a.pid <> pg_backend_pid() ORDER BY a.backend_start DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "")
echo "  captured advisory-holder backend PID: ${HOLDER_PID:-<none>}"

# 3b. Synthesize the statistical_* psql subprocess — the migration SQL the killed
#     migrate was running. Phase 1 (un-aged statistical_history clause) must sweep it
#     once the gate (3a) triggers cleanup. SIGKILL the host client; the docker-exec
#     in-container backend orphans.
echo ""
echo "── synthesizing statistical_* psql subprocess orphan ──"
# ssh-STDIN transport (see simulate_pool_exhaustion): VM_EXEC's printf %q collapses
# this multi-line if/then (dash $'...\n...') → "syntax error near unexpected token 'then'".
# Riding the script over stdin preserves the newlines.
_orphan_wedge=$(mktemp)
cat > "$_orphan_wedge" <<'WEDGE'
./sb psql -c "INSERT INTO public.statistical_history SELECT * FROM public.statistical_history WHERE pg_sleep(600) IS NULL OR true;" >/dev/null 2>&1 &
sleep 3
PSQL_PID=$(pgrep -f "psql.*statistical_history" | head -1)
if [ -n "$PSQL_PID" ]; then
    kill -9 "$PSQL_PID" 2>/dev/null || true
    echo "  killed host psql client PID=$PSQL_PID — in-DB backend should orphan"
else
    echo "  warning: no psql subprocess to kill" >&2
fi
sleep 2
WEDGE
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash -c 'cd ~/statbus && bash'" < "$_orphan_wedge"
rm -f "$_orphan_wedge"

# Capture the orphaned subprocess's BACKEND pid (app='psql', running the INSERT).
SUBPROC_PID=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid FROM pg_stat_activity WHERE application_name = 'psql' AND query ILIKE '%INSERT INTO public.statistical_history%' AND pid <> pg_backend_pid() ORDER BY backend_start DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "")
echo "  captured statistical_* subprocess backend PID: ${SUBPROC_PID:-<none>}"

if [ -z "$HOLDER_PID" ] && [ -z "$SUBPROC_PID" ]; then
    echo "✗ neither orphan engaged (TCP keepalives may have reaped them) — cannot exercise the cleanup; re-run / tune the wedge" >&2
    exit 1
fi

# 4. Run install — the advisory holder trips checkSessionsClean → cleanOrphanSessions
#    runs → Phase 2 reaps the holder, Phase 1 sweeps the subprocess.
echo ""
echo "── re-run install (cleanOrphanSessions: Phase 2 reaps holder, Phase 1 sweeps subprocess) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 5. Recovery-completes assertions (KEPT from the original).
assert_step9_completed "$VM_NAME"
assert_step_upgrade_service_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

# 6. Assert BOTH synthetic orphans are gone — by their captured PIDs (NOT broad
#    counts: the install's own boot-migrate legitimately holds migrate_up empty-app
#    and runs statistical_* DDL during step 12).
echo ""
echo "── verifying both orphans cleaned (by captured PID) ──"
fail=0
for pair in "advisory-holder:$HOLDER_PID:Phase 2 PID-liveness/empty-app reap" \
            "statistical_* subprocess:$SUBPROC_PID:Phase 1 un-aged statistical_history sweep"; do
    label="${pair%%:*}"; rest="${pair#*:}"; pid="${rest%%:*}"; phase="${rest#*:}"
    if [ -z "$pid" ]; then
        echo "  ⚠ $label: no PID captured (wedge didn't engage) — skipping its check"
        continue
    fi
    after=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE pid = $pid;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$after" = "0" ]; then
        echo "  ✓ $label PID $pid terminated post-install ($phase)"
    else
        echo "  ✗ $label PID $pid still present post-install (count=$after) — $phase did not reap it" >&2
        fail=1
    fi
done
if [ "$fail" != "0" ]; then
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid, datname, application_name, state, backend_start, query_start, left(query,80) AS query FROM pg_stat_activity WHERE pid IN (${HOLDER_PID:-0}, ${SUBPROC_PID:-0});\" | ./sb psql" >&2 || true
    exit 1
fi

echo ""
echo "PASS: 5-install-stage-a-killed-migrate"
echo "  (a realistic killed-migrate orphan — empty-app advisory holder + statistical_*"
echo "   psql subprocess — was fully reaped by recovery: the holder tripped the gate,"
echo "   Phase 2 reaped it, Phase 1 swept the subprocess; install completed, health passed.)"
