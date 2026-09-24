#!/bin/bash
# Scenario: 5-install-proxy-never-started  (services step starts everything)
#
# Class:            services-step-db-only-check
# Class kind:       Reconcile (install brings up every service the mode needs)
# Source forensics: Finland first install, v2026.09.2:
#                   tmp/installer-message-audit.md B1 (and B5, B10)
#
# THE GAP THIS CLOSES:
#   Step 8 "Services" used to be done as soon as the db container was healthy.
#   After a first run that failed part-way (Apache held port 80), the proxy,
#   app and worker were never created, yet every rerun printed
#   "[8/17] Services OK". The migration step then died on a raw
#   "dial tcp 127.0.0.1:5431: connection refused" (the proxy carries the local
#   database port), and the upgrade service timed out at step 17 for the same
#   reason.
#
# EXPECTED BEHAVIOUR:
#   A green box loses proxy, app and worker. Running the install again:
#     - step 8 prints RUNNING (not OK) and ends with "All services are running."
#     - all five services are running afterwards
#     - Migrations and Upgrade service steps pass
#     - the final check prints "All services are running and the API is ready."
#     - the upgrade service is active
#
# Usage:
#   ./test/install-recovery/scenarios/5-install-proxy-never-started.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-proxy-never-started}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-proxy-never-started"
echo "  Validates: step 8 starts every service and confirms each is running"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" ""

INSTALL_LOG="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-install.log"

echo ""
echo "── initial install to green ──"
install_statbus_in_vm "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_active "$VM_NAME"

echo ""
echo "── remove proxy, app and worker (the Finland run-2 leftover shape) ──"
VM_EXEC bash -c "cd ~/statbus && docker compose --profile all rm -sf proxy app worker"
REMAINING=$(VM_EXEC bash -c "cd ~/statbus && docker compose --profile all ps --format '{{.Service}}' | sort | tr '\n' ' '")
echo "  containers left: $REMAINING"
case " $REMAINING " in
    *" proxy "*|*" app "*|*" worker "*)
        echo "✗ precondition: proxy/app/worker still present" >&2
        exit 1
        ;;
esac
echo "  ✓ precondition: only db and rest remain"

echo ""
echo "── run the install again ──"
: > "$INSTALL_LOG"
install_statbus_in_vm "$VM_NAME"

if grep -E '^\[[0-9]+/[0-9]+\] Services +OK' "$INSTALL_LOG" >/dev/null; then
    echo "✗ step 8 reported Services OK with proxy, app and worker missing" >&2
    exit 1
fi
grep -E '^\[[0-9]+/[0-9]+\] Services +RUNNING' "$INSTALL_LOG" >/dev/null || {
    echo "✗ step 8 did not run" >&2
    exit 1
}
grep -F 'All services are running.' "$INSTALL_LOG" >/dev/null || {
    echo "✗ step 8 did not confirm every service is running" >&2
    exit 1
}
grep -E '^\[[0-9]+/[0-9]+\] Migrations +(OK|DONE)' "$INSTALL_LOG" >/dev/null || {
    echo "✗ Migrations step did not pass" >&2
    exit 1
}
grep -F 'All services are running and the API is ready.' "$INSTALL_LOG" >/dev/null || {
    echo "✗ the final check did not confirm the API is ready" >&2
    exit 1
}

RUNNING_NOW=$(VM_EXEC bash -c "cd ~/statbus && docker compose --profile all ps --status running --format '{{.Service}}' | sort | tr '\n' ' '")
echo "  running now: $RUNNING_NOW"
for svc in app db proxy rest worker; do
    case " $RUNNING_NOW " in
        *" $svc "*) ;;
        *) echo "✗ $svc is not running after the install" >&2; exit 1 ;;
    esac
done
echo "  ✓ all five services running"

assert_step_upgrade_service_completed "$VM_NAME"
assert_systemd_active "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 5-install-proxy-never-started"
echo "  (step 8 saw the missing services, started them, and the install finished"
echo "   only after confirming every service runs and the API is ready)"
