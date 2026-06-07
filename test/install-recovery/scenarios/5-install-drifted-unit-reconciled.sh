#!/bin/bash
# Scenario: 5-install-drifted-unit-reconciled  (unit-reconcile)
#
# Class:                 systemd-unit-drift-not-reconciled-on-healthy-box
# Class kind:            Reconcile (idempotent install heals drifted config)
# Source forensics:      doc/recovery/upgrade-resume-structural-whole.md (piece #4)
#
# THE GAP THIS CLOSES:
#   The upgrade systemd unit is copied VERBATIM to
#   ~/.config/systemd/user/statbus-upgrade@.service (cmd/install.go copyFile —
#   byte copy; %h/%i/%u resolve at systemd runtime). checkServiceDone used to
#   gate ONLY on `systemctl --user is-active`, so a HEALTHY (active) box whose
#   on-disk unit had DRIFTED from the repo template was never rewritten — the
#   drift persisted indefinitely. That is exactly how rune ended up running a
#   stale unit (WatchdogUSec=infinity / TimeoutStartUSec=90) while the repo had
#   moved to 120/120: no upgrade/install ever re-armed it.
#
# EXPECTED PRINCIPLED BEHAVIOR (post-#4):
#   checkServiceDone now ALSO byte-compares the on-disk unit to the repo
#   template (unitFileMatchesRepo). Drift ⇒ not-done ⇒ runInstallService
#   rewrites the unit, runs daemon-reload, AND — because a rewritten unit is
#   inert until restarted (`enable --now` does not restart an already-running
#   unit) — RESTARTS the unit so the new WatchdogSec/TimeoutStartSec actually
#   arm. The restart is gated on drifted-AND-active-AND-not-insideActiveUpgrade
#   so healthy matching units are never churned.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION; assert healthy + unit active.
#   2. Simulate drift: overwrite the deployed unit with a 90/infinity variant
#      (mimics rune's stale config), daemon-reload + restart so the RUNNING
#      unit reflects the drifted file. Confirm the running unit now reports the
#      drifted timers (RED precondition).
#   3. Run `./sb install` (idempotent). #4 detects the drift, rewrites the unit
#      to the repo template, daemon-reload, restart.
#   4. Assert GREEN: the on-disk unit is byte-identical to the repo template
#      AND the RUNNING unit reports the repo timers (WatchdogUSec=120s,
#      TimeoutStartUSec=120s) — proving the rewrite was re-armed, not inert.
#
# Hetzner-runnability:
#   CI-ONLY (needs real systemd to observe WatchdogUSec/TimeoutStartUSec on the
#   running unit + to exercise the restart re-arm). The byte-compare half is
#   covered locally by the Go guards TestUnitFileMatchesRepo_* and the re-arm
#   wiring by TestRunInstallService_RestartsOnDriftToArmTimers.
#
# Usage:
#   INSTALL_VERSION=v2026.05.4 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/5-install-drifted-unit-reconciled.sh \
#     statbus-recovery-5-install-drifted-unit-reconciled

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-drifted-unit-reconciled}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.4}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

UNIT="statbus-upgrade@statbus.service"
UNIT_TEMPLATE_FILE="\$HOME/.config/systemd/user/statbus-upgrade@.service"

trap '
    rc=$?
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-drifted-unit-reconciled  (unit-reconcile)"
echo "  Install version: $INSTALL_VERSION"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

UNIT_STATE=$(VM_EXEC systemctl --user is-active "$UNIT" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE" != "active" ]; then
    echo "✗ unit not active after install (state=$UNIT_STATE)" >&2
    exit 1
fi
echo "  ✓ unit active, healthy"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — simulate drift: overwrite the on-disk unit with a 90/infinity
# variant (rune's stale shape) and restart so the RUNNING unit reflects it.
# We edit in place with sed so the unit stays otherwise valid (only the two
# timeout knobs change), then daemon-reload + restart.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── simulating unit drift (WatchdogSec→infinity, TimeoutStartSec→90) ──"
VM_EXEC bash -c "
    set -e
    U=$UNIT_TEMPLATE_FILE
    sed -i -E 's/^WatchdogSec=.*/WatchdogSec=infinity/; s/^TimeoutStartSec=.*/TimeoutStartSec=90/' \"\$U\"
    systemctl --user daemon-reload
    systemctl --user restart $UNIT
"
sleep 3

# RED precondition: the running unit now reports the drifted timers.
WD_DRIFT=$(VM_EXEC systemctl --user show "$UNIT" --property=WatchdogUSec --value 2>/dev/null | tr -d ' \r\n' || echo "?")
TS_DRIFT=$(VM_EXEC systemctl --user show "$UNIT" --property=TimeoutStartUSec --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  drifted running unit: WatchdogUSec=$WD_DRIFT TimeoutStartUSec=$TS_DRIFT"
# WatchdogUSec=infinity → systemd reports "infinity"; TimeoutStartUSec=90s → "1min 30s".
if [ "$WD_DRIFT" != "infinity" ]; then
    echo "✗ drift setup did not take effect (WatchdogUSec=$WD_DRIFT, expected infinity)" >&2
    exit 1
fi
echo "  ✓ RED precondition: running unit is on the drifted (90/infinity) config"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — idempotent ./sb install: #4 detects drift → rewrite → reload → restart
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── running idempotent ./sb install (expect #4 to reconcile the unit) ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — assertions (LOAD-BEARING)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── unit-reconcile checks (LOAD-BEARING) ──"

# (1) on-disk unit byte-identical to the repo template again.
DIFF_OUT=$(VM_EXEC bash -c "diff -q $UNIT_TEMPLATE_FILE ~/statbus/ops/statbus-upgrade.service >/dev/null 2>&1 && echo SAME || echo DIFF" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$DIFF_OUT" != "SAME" ]; then
    echo "✗ on-disk unit still differs from the repo template after install — #4 did not rewrite it" >&2
    VM_EXEC bash -c "diff $UNIT_TEMPLATE_FILE ~/statbus/ops/statbus-upgrade.service" >&2 || true
    exit 1
fi
echo "  ✓ on-disk unit byte-identical to repo template (rewritten)"

# (2) the RUNNING unit reports the repo timers — proving the rewrite was
# re-armed (restarted), not left inert.
WD_FIXED=$(VM_EXEC systemctl --user show "$UNIT" --property=WatchdogUSec --value 2>/dev/null | tr -d ' \r\n' || echo "?")
TS_FIXED=$(VM_EXEC systemctl --user show "$UNIT" --property=TimeoutStartUSec --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  reconciled running unit: WatchdogUSec=$WD_FIXED TimeoutStartUSec=$TS_FIXED"
# Repo is WatchdogSec=120 / TimeoutStartSec=120 → systemd reports "2min".
if [ "$WD_FIXED" = "infinity" ]; then
    echo "✗ running unit STILL has WatchdogUSec=infinity — the rewrite was not re-armed (no restart)." >&2
    echo "  A rewritten unit file is inert until daemon-reload + restart; #4 must restart a drifted+active unit." >&2
    exit 1
fi
case "$TS_FIXED" in
    *"2min"*|*"120s"*) : ;;
    *)
        echo "✗ running unit TimeoutStartUSec=$TS_FIXED, expected ~2min (repo 120s) — re-arm failed." >&2
        exit 1
        ;;
esac
echo "  ✓ running unit re-armed to repo timers (Watchdog≠infinity, TimeoutStart≈2min)"

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 5-install-drifted-unit-reconciled"
echo "  (a healthy box's drifted unit was detected by the byte-compare, rewritten to"
echo "   the repo template, and RESTARTED so the reconciled WatchdogSec/TimeoutStartSec"
echo "   actually armed — no more stale-timeout drift surviving on a running host)"
