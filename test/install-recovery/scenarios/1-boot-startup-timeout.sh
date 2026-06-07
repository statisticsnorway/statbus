#!/bin/bash
# Scenario: 1-boot-startup-timeout  (C11 / Layer 1 — TimeoutStartSec fires)
#
# Class:                 service-startup-slower-than-systemd-unit-timeout
# Class kind:            Stall
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   The upgrade-service's startup pipeline (syncConfigToSystemInfo →
#   cleanStaleMaintenance → checkMissedUpgrades → LISTEN setup) runs
#   BEFORE sdNotify("READY=1"). systemd holds the unit in the
#   `activating` phase during this window, enforcing TimeoutStartSec
#   (declared as 120 s in ops/statbus-upgrade.service per commit
#   f43b2bfd1). If the pipeline blows past that budget, systemd
#   SIGTERMs the unit; NRestarts increments; after StartLimitBurst
#   (=10) cycles within 600 s, the unit goes to permanent failure
#   and `./sb install` is the operator's recovery lever.
#
#   Design choice (a) — keep TimeoutStartSec static, no activating-
#   phase extender. The earlier sdNotifyExtendTimeout helper that
#   pushed TimeoutStartSec forward during activating phase has been
#   DELETED (commit e6df084b7) — Race B forensics showed the helper
#   couples watchdog + start budgets in subtly wrong ways. The C11
#   contract is now: static 120 s budget; if startup is slower,
#   the unit fails; operator runs `./sb install` (dispatches the
#   same code inline, bypassing the supervised unit's TimeoutStartSec).
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.4 — keeps the
#      install side simple; this scenario is about the service unit's
#      timeout shape, not the upgrade path).
#   2. Write a systemd drop-in override pinning the C11 env vars on
#      the upgrade-service unit:
#        STATBUS_INJECT_AT=service-startup-slower-than-systemd-unit-timeout
#        STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=/tmp/stall-release-c11
#      and TimeoutStopSec=5s so the SIGTERM-to-SIGKILL escalation
#      stays inside the test budget (the default 15 min would push
#      each restart cycle to ~16 min).
#   3. Create the release file in the VM, so the stall is held.
#   4. Restart the unit. Service.Run enters the startup pipeline,
#      hits inject.StallHere AFTER the advisory lock, BEFORE
#      READY=1.
#   5. systemd's TimeoutStartSec=120 s expires; SIGTERM fires.
#      With TimeoutStopSec=5 s the process is SIGKILLed at ~125 s.
#      systemd marks the unit failed; Restart=always + RestartSec=30
#      will trigger another start in 30 s.
#   6. Verify RED: NRestarts incremented; unit's Result reflects
#      a start timeout.
#   7. Stop the unit. Remove the drop-in override + release file.
#      systemctl daemon-reload.
#   8. Start the unit. Verify it reaches `active` cleanly (READY=1
#      sent within budget).
#   9. Assert NRestarts grew by ≤ 2 (the single timeout-driven
#      restart fits inside the StartLimitBurst budget).
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; everything
#   else is harness orchestration.
#
# Usage:
#   INSTALL_VERSION=v2026.05.4 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/1-boot-startup-timeout.sh \
#     statbus-recovery-1-boot-startup-timeout

set -euo pipefail

VM_NAME="${1:-statbus-recovery-1-boot-startup-timeout}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.4}"
TIMEOUT_OBSERVE_S="${TIMEOUT_OBSERVE_S:-150}"   # TimeoutStartSec=120 + TimeoutStopSec=5 + slack

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release"
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d"
DROPIN_FILE="$DROPIN_DIR/inject.conf"

trap '
    rc=$?
    # Best-effort cleanup so a failed scenario does not leave a wedged
    # systemd state on the VM (cleanup_vm destroys the VM anyway, but
    # belt + braces in case KEEP_VM=1 is set for debugging).
    VM_EXEC bash -c "
        systemctl --user stop statbus-upgrade@statbus.service 2>/dev/null || true
        rm -f $DROPIN_FILE 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        rm -f $RELEASE_FILE 2>/dev/null || true
        systemctl --user start statbus-upgrade@statbus.service 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 1-boot-startup-timeout  (C11 / Layer 1 — TimeoutStartSec)"
echo "  Install version: $INSTALL_VERSION (no upgrade needed)"
echo "  Stall budget: ${TIMEOUT_OBSERVE_S}s (TimeoutStartSec=120 + TimeoutStopSec=5 + slack)"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Baseline NRestarts before triggering the timeout.
NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# Verify the unit is in active state before we wedge it. Any prior
# failure or transient state would skew the NRestarts delta.
UNIT_STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE" != "active" ]; then
    echo "✗ upgrade-service unit not active before trigger (state=$UNIT_STATE)" >&2
    exit 1
fi
echo "  ✓ upgrade-service active"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — install the drop-in override + release file
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── installing C11 drop-in override + release file ──"
# Heredoc inside `VM_EXEC bash -c "..."` loses newlines: printf %q converts
# them to \n inside $'...' ANSI-C quoting, so the remote bash sees everything
# on one line and the <<EOF delimiter merges with the body.  Write a complete
# script locally (heredoc works fine on the local machine), scp it, and run it.
# Pattern matches 3-postswap-archivebackup-watchdog (line ~162).
_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d"
DROPIN_FILE="\$DROPIN_DIR/inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=service-startup-slower-than-systemd-unit-timeout
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
# Shorten the SIGTERM-to-SIGKILL grace so each restart cycle fits the
# test budget. Production TimeoutStopSec=15min lets the rollback() defer
# chain finish a slow pg_restore; this drop-in is harness-only.
TimeoutStopSec=5s
DROPIN_EOF
touch $RELEASE_FILE
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin_script"
scp -O "${SSH_OPTS[@]}" "$_dropin_script" root@"$VM_IP":/tmp/harness-install-dropin.sh
rm -f "$_dropin_script"
VM_EXEC bash /tmp/harness-install-dropin.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-install-dropin.sh" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — restart the unit with the stall active; observe timeout
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── restarting upgrade-service with C11 stall active ──"
# systemctl restart blocks until the unit reaches active OR fails; we
# don't want either (the start is going to TIME OUT, which would
# normally return non-zero from `restart`). Use --no-block to fire-
# and-forget, then poll.
VM_EXEC bash -c "systemctl --user --no-block restart statbus-upgrade@statbus.service"

echo "  unit restart requested; waiting ${TIMEOUT_OBSERVE_S}s for TimeoutStartSec=120s to fire"
START_TS=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$TIMEOUT_OBSERVE_S" ]; then
        break
    fi
    # Surface intermediate state every 30s.
    if [ $((elapsed % 30)) -eq 0 ]; then
        STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
        SUBSTATE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=SubState --value 2>/dev/null | tr -d ' \r\n' || echo "?")
        echo "    [t+${elapsed}s] state=$STATE substate=$SUBSTATE"
    fi
    sleep 5
done

# Read post-timeout state.
NRESTARTS_AFTER_TIMEOUT=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESULT=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=Result --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  post-timeout: NRestarts=$NRESTARTS_AFTER_TIMEOUT Result=$RESULT"

# Load-bearing: NRestarts MUST have grown. If it didn't, either
# TimeoutStartSec is not 120 (drift!), or the inject site never
# fired (typo in the env var, code path skipped), or the stall did
# not hold (release file missing).
RESTART_DELTA=$((NRESTARTS_AFTER_TIMEOUT - NRESTARTS_BASELINE))
if [ "$RESTART_DELTA" -lt 1 ]; then
    echo "✗ NRestarts did not grow during the timeout window (delta=$RESTART_DELTA)" >&2
    echo "  Possible causes: TimeoutStartSec not 120; inject site not fired; release file missing." >&2
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@statbus.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ NRestarts incremented by $RESTART_DELTA — TimeoutStartSec fired as expected"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — recovery: remove drop-in + release file, start the unit
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── recovery: removing C11 drop-in + release file ──"
VM_EXEC bash -c "
    systemctl --user stop statbus-upgrade@statbus.service 2>/dev/null || true
    rm -f $DROPIN_FILE
    systemctl --user daemon-reload
    rm -f $RELEASE_FILE
"

echo "── restarting upgrade-service without injection ──"
VM_EXEC bash -c "systemctl --user start statbus-upgrade@statbus.service"
sleep 5

UNIT_STATE_AFTER=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE_AFTER" != "active" ]; then
    echo "✗ unit did not reach active after recovery (state=$UNIT_STATE_AFTER)" >&2
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@statbus.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ unit active after recovery"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Load-bearing: NRestarts MUST stay bounded across the whole
# scenario. We allow up to 2 (1 from the timeout itself; 1 of
# headroom for systemd transient quirks). Anything higher means
# the unit was thrashing and StartLimitBurst is closer than we
# thought.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── bounded-restart check ──"
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
FINAL_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$FINAL_DELTA"

if [ "$FINAL_DELTA" -gt 2 ]; then
    echo "✗ NRestarts grew by $FINAL_DELTA (>2) — startup-timeout is producing more restarts than expected" >&2
    exit 1
fi
echo "  ✓ restart counter bounded"

# Health check passes — Caddy + app + worker + rest reachable.
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 1-boot-startup-timeout (TimeoutStartSec=120s fired as expected; recovery cleared the wedge with bounded restarts)"
