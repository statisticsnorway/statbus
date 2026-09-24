#!/bin/bash
# Scenario: 5-install-orphaned-db-volume-credentials  (credentials agree)
#
# Class:            db-volume-outlives-its-credentials
# Class kind:       Reconcile (install re-applies role passwords from .env.credentials)
# Source forensics: Finland first install, v2026.09.2 (VM-reproduced):
#                   $JCODE_SCRATCH_DIR/rest-loop.md, tmp/installer-message-audit.md B1/B10
#
# THE GAP THIS CLOSES:
#   postgres/init-db.sh sets the role passwords (admin, app, authenticator,
#   notify) only when the database volume is first initialised. Three
#   defects together turned a port-80 conflict into a box that could not be
#   finished:
#     1. A fresh install that failed at step 8 was refused on every rerun as
#        "pre-1.0 install detected" (DB reachable, public.upgrade absent).
#     2. The operator's only remaining lever was to delete ~/statbus and run
#        install.sh again. That generated new .env.credentials while the
#        statbus-<code>-db-data volume kept the old passwords.
#     3. Nothing re-applied the passwords: rest restart-looped on
#        `password authentication failed for user "authenticator"`, and the
#        upgrade service never connected, timing out at step 17.
#
# EXPECTED BEHAVIOUR (the operator never runs anything but the install command):
#   a. install.sh while port 80 is held: step 8 "Services" FAILS and names the
#      web server; the DB volume exists.
#   b. Port 80 freed, `./sb install` again: detected as fresh-db-incomplete
#      (never "pre-1.0"), continues, completes, API /ready answers 200.
#   c. `docker compose down; rm -rf ~/statbus` (volume KEPT), install.sh again:
#      step 8 makes the database passwords match the new .env.credentials,
#      rest runs without restarting, /ready 200, the upgrade service is active,
#      the newest public.upgrade row is completed, the users are still there.
#
# Standalone mode with the site domain only in /etc/hosts (Finland's shape).
#
# Usage:
#   ./test/install-recovery/scenarios/5-install-orphaned-db-volume-credentials.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-orphaned-db-volume-credentials}"
HARNESS_DEPLOYMENT_MODE=standalone
SITE_DOMAIN=statbus-test.local

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-orphaned-db-volume-credentials"
echo "  Validates: install re-applies role passwords; an interrupted fresh"
echo "  install continues instead of being refused as pre-1.0"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" ""

VM_ROOT_EXEC bash -c "echo '127.0.1.1 ${SITE_DOMAIN}' >> /etc/hosts"

INSTALL_LOG="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-install.log"

rest_admin_ready() {
    VM_EXEC bash -c "cd ~/statbus && curl -s -m 5 -o /dev/null -w '%{http_code}' http://\$(./sb dotenv -f .env get REST_ADMIN_BIND_ADDRESS)/ready" 2>/dev/null || echo 000
}

rest_restart_count() {
    VM_EXEC bash -c "cd ~/statbus && docker inspect \"\$(./sb dotenv -f .env get COMPOSE_INSTANCE_NAME)-rest\" --format '{{.RestartCount}} {{.State.Status}}'" 2>/dev/null || echo "? ?"
}

# ─────────────────────────────────────────────────────────────────────────
# Phase a — port 80 is held by another program; step 8 must fail and say so.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── phase a: install.sh while port 80 is held ──"
VM_ROOT_EXEC bash -c 'cd /tmp && (nohup python3 -m http.server 80 >/tmp/http80.log 2>&1 &) ; sleep 1; ss -ltn | grep -q ":80 " && echo "port 80 held"'
harness_register_log port80-squatter /tmp/http80.log
set +e
install_statbus_in_vm "$VM_NAME"
set -e
if ! grep -E '^\[[0-9]+/[0-9]+\] Services +FAILED' "$INSTALL_LOG" >/dev/null; then
    echo "✗ phase a: step 'Services' did not fail while port 80 was held" >&2
    exit 1
fi
if ! grep -F 'the web server (proxy)' "$INSTALL_LOG" >/dev/null; then
    echo "✗ phase a: the failure does not name the web server in plain words" >&2
    exit 1
fi
VOLUME=$(VM_EXEC bash -c "docker volume ls --format '{{.Name}}' | grep -E '^statbus-.*-db-data\$' | head -1" | tr -d '\r\n')
[ -n "$VOLUME" ] || { echo "✗ phase a: no database volume was created" >&2; exit 1; }
echo "  ✓ phase a: Services FAILED naming the web server; volume $VOLUME exists"

# ─────────────────────────────────────────────────────────────────────────
# Phase b — free port 80, rerun the install: it continues, never "pre-1.0".
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── phase b: port 80 freed, ./sb install again ──"
VM_ROOT_EXEC bash -c 'pkill -f "http.server 80"; sleep 1; ss -ltn | grep -q ":80 " && echo "port 80 STILL held" || echo "port 80 free"'
: > "$INSTALL_LOG"
install_statbus_in_vm "$VM_NAME"
if grep -F 'pre-1.0 install detected' "$INSTALL_LOG" >/dev/null; then
    echo "✗ phase b: the rerun was refused as a pre-1.0 install" >&2
    exit 1
fi
grep -F 'Detected install state: fresh-db-incomplete' "$INSTALL_LOG" >/dev/null || {
    echo "✗ phase b: expected 'Detected install state: fresh-db-incomplete'" >&2
    grep -F 'Detected install state' "$INSTALL_LOG" >&2 || true
    exit 1
}
grep -F 'All services are running and the API is ready.' "$INSTALL_LOG" >/dev/null || {
    echo "✗ phase b: the install did not confirm the API is ready" >&2
    exit 1
}
[ "$(rest_admin_ready)" = 200 ] || { echo "✗ phase b: rest /ready is not 200" >&2; exit 1; }
assert_systemd_active "$VM_NAME"
echo "  ✓ phase b: continued as fresh-db-incomplete, completed, /ready 200"

USERS_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -t -A -c 'SELECT count(*) FROM auth.user;'" | tr -d ' \r\n')
[ "${USERS_BEFORE:-0}" -gt 0 ] || { echo "✗ phase b: no users were created" >&2; exit 1; }
FINGERPRINT_BEFORE=$(VM_EXEC bash -c "sha256sum ~/statbus/.env.credentials | cut -c1-16" | tr -d '\r\n')

# ─────────────────────────────────────────────────────────────────────────
# Phase c — the operator starts over: containers down, ~/statbus deleted, the
# database volume survives. install.sh generates NEW credentials.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── phase c: docker compose down, rm -rf ~/statbus (volume kept), install.sh ──"
VM_EXEC bash -c "systemctl --user disable --now statbus-upgrade@statbus.service 2>/dev/null; cd ~/statbus && docker compose --profile all down; cd ~ && rm -rf ~/statbus"
VM_EXEC bash -c "docker volume inspect $VOLUME >/dev/null && echo 'volume kept: $VOLUME'"
: > "$INSTALL_LOG"
install_statbus_in_vm "$VM_NAME"

FINGERPRINT_AFTER=$(VM_EXEC bash -c "sha256sum ~/statbus/.env.credentials | cut -c1-16" | tr -d '\r\n')
if [ "$FINGERPRINT_BEFORE" = "$FINGERPRINT_AFTER" ]; then
    echo "✗ phase c precondition: .env.credentials was not regenerated (the scenario did not orphan the volume)" >&2
    exit 1
fi
echo "  ✓ phase c precondition: .env.credentials regenerated over the surviving volume"

grep -F 'The database held older passwords for' "$INSTALL_LOG" >/dev/null || {
    echo "✗ phase c: the install did not report re-applying the database passwords" >&2
    exit 1
}
grep -F 'All services are running and the API is ready.' "$INSTALL_LOG" >/dev/null || {
    echo "✗ phase c: the install did not confirm the API is ready" >&2
    exit 1
}

# rest must be running and stay running (no restart loop) over 60 s.
read -r RESTARTS_1 STATUS_1 <<< "$(rest_restart_count)"
sleep 60
read -r RESTARTS_2 STATUS_2 <<< "$(rest_restart_count)"
echo "  rest: status=$STATUS_1→$STATUS_2 restarts=$RESTARTS_1→$RESTARTS_2"
if [ "$STATUS_2" != running ] || [ "$RESTARTS_1" != "$RESTARTS_2" ]; then
    echo "✗ phase c: rest is not running steadily" >&2
    VM_EXEC bash -c "cd ~/statbus && docker compose logs --tail 30 rest" >&2 || true
    exit 1
fi
[ "$(rest_admin_ready)" = 200 ] || { echo "✗ phase c: rest /ready is not 200" >&2; exit 1; }
AUTH_STATUS=$(VM_EXEC bash -c "cd ~/statbus && curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://\$(./sb dotenv -f .env get REST_BIND_ADDRESS)/rpc/auth_status" | tr -d '\r\n')
[ "$AUTH_STATUS" = 200 ] || { echo "✗ phase c: POST /rpc/auth_status returned $AUTH_STATUS" >&2; exit 1; }
echo "  ✓ phase c: rest steady, /ready 200, /rpc/auth_status 200"

assert_systemd_active "$VM_NAME"
assert_step_upgrade_service_completed "$VM_NAME"

NEWEST=$(VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -t -A -c 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;'" | tr -d ' \r\n')
[ "$NEWEST" = completed ] || { echo "✗ phase c: newest public.upgrade row is '$NEWEST', expected completed" >&2; exit 1; }
USERS_AFTER=$(VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -t -A -c 'SELECT count(*) FROM auth.user;'" | tr -d ' \r\n')
[ "$USERS_AFTER" -ge "$USERS_BEFORE" ] || { echo "✗ phase c: auth.user shrank ($USERS_BEFORE → $USERS_AFTER)" >&2; exit 1; }
echo "  ✓ phase c: daemon active, newest upgrade row completed, auth.user intact ($USERS_AFTER)"

echo ""
echo "PASS: 5-install-orphaned-db-volume-credentials"
echo "  (an install interrupted at step 8 continued on rerun, and a reinstall over a"
echo "   surviving database volume made the role passwords match the new credentials:"
echo "   rest steady, API ready, upgrade service active)"
