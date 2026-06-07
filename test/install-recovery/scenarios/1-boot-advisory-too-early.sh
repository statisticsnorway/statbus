#!/bin/bash
# Scenario: 1-boot-advisory-too-early  (C16 / Race E — advisory lock before DB ready)
#
# Class:                 advisory-lock-attempted-before-db-ready-after-container-restart
# Class kind:            External (KindExternal — no in-code inject site fires)
# Forensics tag:         Race E
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   When the DB container restarts, there's a brief window where the
#   container is up but PostgreSQL hasn't yet accepted connections.
#   If the supervised upgrade-service unit starts during that window
#   and tries to take its `pg_advisory_lock(migrate_up)` before the
#   DB is ready, the lock acquisition fails. The service exits with
#   the well-known "DB not ready" code (42 per the unit's
#   `RestartForceExitStatus=42`). systemd waits `RestartSec=30` then
#   restarts the unit; by then the DB is fully ready and the second
#   attempt succeeds. NRestarts increments by 1, the upgrade
#   (whatever's pending) proceeds normally.
#
#   Convergence: self-heals by systemd's restart policy. Load-bearing
#   is that NRestarts stays bounded (the cascade doesn't trip
#   StartLimitBurst=10).
#
# Scenario kind: external orchestration (no in-code inject site).
#   C16 is KindExternal — no `inject.X` call fires for this class.
#   The scenario orchestrates the race externally:
#     1. Stop the upgrade-service unit.
#     2. Restart the DB container via `docker compose restart db`.
#     3. Immediately (before DB is fully accepting connections) start
#        the upgrade-service unit. The unit's first start should
#        observe the "DB not ready" condition and exit 42.
#     4. Wait `RestartSec` + slack and confirm the unit reaches
#        `active` state on its automatic restart.
#     5. Assert NRestarts grew by ≤ 2 (one for the first-start exit,
#        possibly one of headroom for systemd quirks).
#
# Expected on current branch: GREEN — self-heals by design.
#
# Trigger logic:
#   1. Bootstrap + install at INSTALL_VERSION. Verify upgrade-service
#      unit is `active`.
#   2. Stop the unit cleanly.
#   3. `docker compose restart db` — restart the DB container.
#   4. Immediately `systemctl --user start statbus-upgrade@statbus.service`.
#      (The "immediately" timing is what produces the Race E window.
#      If we sleep longer, the DB is fully ready and the race
#      disappears — the test becomes a no-op.)
#   5. Sleep `WAIT_S` (default 90s) — covers RestartSec=30 + slack
#      so systemd can restart the unit after the first failure.
#   6. Assert: unit reaches `active` state; NRestarts delta ≤ 2.
#
# Hetzner-runnability:
#   READY. No injection site needed; the scenario orchestrates the
#   race externally and observes the self-heal. May be flaky on
#   slow Hetzner cx23 VMs where the "DB ready" window is wider —
#   tune RACE_WINDOW_DELAY_S below if needed (small sleeps after
#   docker restart push us into the race-free zone where the test
#   becomes a no-op).
#
# Usage:
#   INSTALL_VERSION=v2026.05.4 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/1-boot-advisory-too-early.sh \
#     statbus-recovery-1-boot-advisory-too-early

set -euo pipefail

VM_NAME="${1:-statbus-recovery-1-boot-advisory-too-early}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.4}"
WAIT_S="${WAIT_S:-90}"                              # RestartSec=30 + slack
RACE_WINDOW_DELAY_S="${RACE_WINDOW_DELAY_S:-0}"     # bump if Hetzner is too slow to hit the race

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 1-boot-advisory-too-early  (C16 / Race E — external orchestration)"
echo "  Install version: $INSTALL_VERSION"
echo "  Wait budget: ${WAIT_S}s  (RestartSec=30 + slack)"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

UNIT_STATE_BEFORE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE_BEFORE" != "active" ]; then
    echo "✗ upgrade-service unit not active before race trigger (state=$UNIT_STATE_BEFORE)" >&2
    exit 1
fi
echo "  ✓ upgrade-service active before race trigger"

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — orchestrate the race externally
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── orchestrating Race E: stop unit, restart DB container, immediately start unit ──"

# Step 1: Stop the unit cleanly so its current process exits.
VM_EXEC bash -c "systemctl --user stop statbus-upgrade@statbus.service"
sleep 2

# Step 2: Restart the DB container. This produces the "DB not yet
# accepting connections" window we're racing into.
VM_EXEC bash -c "cd ~/statbus && docker compose restart db"

# Step 3: Optional grace window — if Hetzner is too fast OR too slow,
# bump RACE_WINDOW_DELAY_S to land inside the race-window window.
if [ "$RACE_WINDOW_DELAY_S" -gt 0 ]; then
    echo "  sleeping RACE_WINDOW_DELAY_S=${RACE_WINDOW_DELAY_S}s before starting unit"
    sleep "$RACE_WINDOW_DELAY_S"
fi

# Step 4: Start the unit. With ZERO grace, this should hit the
# Race E window — DB container is up but not accepting connections yet.
echo "  starting upgrade-service unit (this is the race trigger)"
VM_EXEC bash -c "systemctl --user --no-block start statbus-upgrade@statbus.service"

# Step 5: Sleep to let systemd's automatic restart kick in.
echo "  waiting ${WAIT_S}s for unit's failure → automatic restart → active state"
sleep "$WAIT_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — observe self-heal outcome
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── observing post-race state ──"

UNIT_STATE_AFTER=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
NRESTARTS_AFTER=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESULT=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=Result --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  unit state: $UNIT_STATE_AFTER  Result: $RESULT  NRestarts: $NRESTARTS_AFTER"

RESTART_DELTA=$((NRESTARTS_AFTER - NRESTARTS_BASELINE))
echo "  NRestarts delta: $RESTART_DELTA (baseline=$NRESTARTS_BASELINE → after=$NRESTARTS_AFTER)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — assertions
#
# Load-bearing:
#   - unit MUST reach active state (self-heal)
#   - NRestarts delta ≤ 2 (the race triggers 1 restart; +1 headroom)
#
# If RESTART_DELTA == 0, the race window didn't trigger (DB was ready
# when the unit started). Not a regression, just a no-op for this run.
# Document it so the operator knows the race wasn't observed.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

if [ "$UNIT_STATE_AFTER" != "active" ]; then
    echo "✗ unit did not reach active state after race trigger (state=$UNIT_STATE_AFTER)" >&2
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@statbus.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ unit reached active state (self-healed)"

if [ "$RESTART_DELTA" -gt 2 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA (>2) — Race E self-heal is bounded by StartLimitBurst, not by recovery" >&2
    exit 1
fi

if [ "$RESTART_DELTA" = "0" ]; then
    echo ""
    echo "  NOTE: NRestarts unchanged — the race window was NOT triggered this run."
    echo "  (DB container likely came up fast enough that the unit's start landed in the ready-window.)"
    echo "  This scenario is non-deterministic for the race itself; bump RACE_WINDOW_DELAY_S=0 → small value"
    echo "  to widen the window if the race needs to be observed empirically. The self-heal path is still"
    echo "  asserted (NRestarts ≤ 2 + unit active)."
else
    echo "  ✓ Race E triggered (NRestarts delta=$RESTART_DELTA); self-heal converged within bounds"
fi

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 1-boot-advisory-too-early (Race E self-heal converged; NRestarts bounded; unit active)"
