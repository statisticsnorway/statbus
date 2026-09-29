#!/usr/bin/env bash
# Scenario: 5-install-cert-repair-via-cert-install  (STATBUS-429)
#
# Class:            operator-cert-remedy
# Class kind:       Repair (an unprivileged operator fixes their own box)
# Source forensics: tmp/ville-replay-v2026.09.3.md defect D3, and the owner
#                    correction that the fix is `./sb cert install`, not a
#                    printed mkdir/cp remedy.
#
# THE GAP THIS CLOSES:
#   Once "Services" has started the proxy container at least once, Docker
#   owns caddy/data/ as root:root. A box that reaches that point with an
#   INVALID host-path TLS_CERT_FILE/TLS_KEY_FILE in .env.config (Ville's
#   exact mistake) has Settings refuse on every subsequent `./sb install`,
#   and the printed remedy now names `./sb cert install`. This scenario
#   proves `./sb cert install <crt> <key>`, run as the unprivileged statbus
#   user with NO sudo, repairs caddy/data/custom-certs/ itself, writes a
#   working certificate, and leaves the box able to complete a plain
#   `./sb install` rerun.
#
# EXPECTED BEHAVIOUR:
#   1. A box installs cleanly (standalone mode, self-signed cert staged at a
#      HOST path — Ville's shape), and Services has therefore already
#      chowned caddy/data/ to root:root.
#   2. The operator hand-edits .env.config to the invalid host path exactly
#      as Ville did, and `./sb install` refuses at Settings, printing the
#      `./sb cert install` remedy (never a bare mkdir/cp instruction).
#   3. As the statbus user, with NO sudo, `./sb cert install <crt> <key>`:
#        - repairs caddy/data/custom-certs/ ownership without operator help,
#        - places the certificate,
#        - rewrites .env.config to the correct container paths,
#        - regenerates config, restarts the proxy,
#        - verifies the served certificate matches what it installed.
#   4. A subsequent `./sb install` reaches a ready installation (every step
#      green).
#
# STATUS: AUTHORED, NOT RUN. This scenario requires the paid LXD fleet
# (test/install-recovery/README.md) and a tagged release candidate; it was
# not executed as part of this change. Run it via:
#   ./test/install-recovery/scenarios/5-install-cert-repair-via-cert-install.sh
#
# Usage:
#   ./test/install-recovery/scenarios/5-install-cert-repair-via-cert-install.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-cert-repair-via-cert-install}"
HARNESS_DEPLOYMENT_MODE=standalone

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag must point at HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-cert-repair-via-cert-install (STATBUS-429)"
echo "  Validates: ./sb cert install repairs root-owned caddy/data/ and"
echo "             replaces an invalid host-path certificate, unprivileged"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
IP=$(_hcloud_server_ip "$VM_NAME")
_wait_for_ssh "$IP" 30

echo ""
echo "── initial clean install (self-signed cert at a HOST path, unused by .env.config yet) ──"
VM_ROOT_EXEC bash -c "echo '127.0.1.1 statbus-test.local' >> /etc/hosts"
VM_EXEC bash -c "openssl req -x509 -newkey rsa:2048 -nodes -keyout \$HOME/statbus.key -out \$HOME/statbus.crt -days 1 -subj '/CN=statbus-test.local' -addext 'subjectAltName=DNS:statbus-test.local'"
install_statbus_in_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
assert_health_passes "$VM_NAME"

echo ""
echo "── hand-edit .env.config to an INVALID host-path cert (Ville's mistake) ──"
VM_EXEC bash -c "cd ~/statbus && printf 'TLS_CERT_FILE=/home/statbus/statbus.crt\nTLS_KEY_FILE=/home/statbus/statbus.key\n' >> .env.config"

REFUSAL_LOG=$(mktemp)
if VM_EXEC bash -c "cd ~/statbus && ./sb install --non-interactive" >"$REFUSAL_LOG" 2>&1; then
    cat "$REFUSAL_LOG" >&2
    echo 'FAIL: install should have refused on the invalid host-path certificate' >&2
    exit 1
fi
grep -Fq 'The custom certificate settings are invalid.' "$REFUSAL_LOG" || { cat "$REFUSAL_LOG" >&2; exit 1; }
grep -Fq './sb cert install' "$REFUSAL_LOG" || { cat "$REFUSAL_LOG" >&2; echo 'FAIL: refusal must name ./sb cert install, not a manual mkdir/cp remedy' >&2; exit 1; }
! grep -Eq 'mkdir -p.*custom-certs' "$REFUSAL_LOG" || { echo 'FAIL: refusal must not print a raw mkdir remedy' >&2; exit 1; }
echo 'PASS: Settings refused the invalid host-path certificate and named ./sb cert install'

echo ""
echo "── confirm caddy/data/ is root-owned (Services already ran once) ──"
OWNER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data")
[ "$OWNER" = "root:root" ] || { echo "FAIL: expected caddy/data/ root:root, got $OWNER" >&2; exit 1; }
echo "  ✓ caddy/data/ is $OWNER (Docker created it on first Services run)"

echo ""
echo "── operator follows the printed remedy: ./sb cert install, no sudo ──"
CERT_LOG=$(mktemp)
VM_EXEC bash -c "cd ~/statbus && ./sb cert install /home/statbus/statbus.crt /home/statbus/statbus.key" >"$CERT_LOG" 2>&1 || { cat "$CERT_LOG" >&2; exit 1; }
grep -Fq '✓ Files placed:' "$CERT_LOG" || { cat "$CERT_LOG" >&2; echo 'FAIL: cert install did not report file placement' >&2; exit 1; }
grep -Fq '✓ .env.config updated' "$CERT_LOG" || { cat "$CERT_LOG" >&2; exit 1; }
grep -Fq '✓ Caddy restarted' "$CERT_LOG" || { cat "$CERT_LOG" >&2; exit 1; }
grep -Eq '✓ Verified: https://.* serves the new certificate' "$CERT_LOG" || { cat "$CERT_LOG" >&2; echo 'FAIL: cert install did not verify the served certificate' >&2; exit 1; }
echo 'PASS: ./sb cert install repaired ownership, placed the cert, and verified it is served — unprivileged, no sudo'

echo ""
echo "── custom-certs/ is now owned by the statbus user, not root ──"
NEW_OWNER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data/custom-certs")
[ "$NEW_OWNER" = "statbus:statbus" ] || { echo "FAIL: expected custom-certs/ statbus:statbus, got $NEW_OWNER" >&2; exit 1; }
CADDY_OWNER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data/caddy 2>/dev/null || echo absent")
echo "  ✓ custom-certs/ is $NEW_OWNER; caddy/data/caddy/ (Caddy's own ACME state) is $CADDY_OWNER, untouched by the repair"

echo ""
echo "── a plain ./sb install rerun now reaches a ready installation ──"
RERUN_LOG=$(mktemp)
VM_EXEC bash -c "cd ~/statbus && ./sb install --non-interactive" >"$RERUN_LOG" 2>&1 || { cat "$RERUN_LOG" >&2; exit 1; }
grep -Eq '^\[[0-9]+/[0-9]+\] Settings +OK' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; echo 'FAIL: Settings should now pass with the corrected certificate paths' >&2; exit 1; }
assert_health_passes "$VM_NAME"
echo 'PASS: box reached a ready installation after the ./sb cert install repair'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PASS: 5-install-cert-repair-via-cert-install"
echo "════════════════════════════════════════════════════════════════"
