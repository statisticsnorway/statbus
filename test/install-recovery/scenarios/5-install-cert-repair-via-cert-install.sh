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
#   and the printed remedy now names `cd ~/statbus && ./sb cert install`.
#   This scenario proves `./sb cert install <crt> <key>`, run as the
#   unprivileged statbus user with NO sudo, repairs
#   caddy/data/custom-certs/ itself, writes a working certificate, and
#   leaves the box able to complete a rerun of the real operator command
#   (`curl -fsSL https://statbus.org/install.sh | bash`, as the printed
#   remedy names it).
#
# EXPECTED BEHAVIOUR:
#   1. A box installs with NO custom certificate at all
#      (HARNESS_NO_CUSTOM_CERT=1, opted out of the harness's normal
#      pre-staged-custom-certs standalone install): Docker therefore
#      creates caddy/data/ as root:root the first time the proxy container
#      starts, exactly as it does on any real box's first "Services" step,
#      and NOT as the statbus user the harness's default staging would
#      otherwise leave it as (STATBUS-429 review M1b — the harness's
#      ordinary standalone path pre-creates custom-certs/ as statbus
#      BEFORE the first `compose up`, which would never reproduce Ville's
#      state at all).
#   2. The operator hand-edits .env.config to a host-path cert (Ville's
#      exact mistake), pointing at the harness's own CA-signed
#      ~/harness-certs/domain.{crt,key} (so the eventual served
#      certificate is one the health check can verify — a bare
#      self-signed cert would leave step 6's own probe unable to complete
#      without --insecure, and the harness's assert_health_passes /
#      assert_harness_https_passes both expect the harness CA). `./sb
#      install` refuses at Settings, printing the `cd ~/statbus && ./sb
#      cert install` remedy (never a bare mkdir/cp instruction, never a
#      bare `./sb` that would fail if pasted from $HOME).
#   3. As the statbus user, with NO sudo, `./sb cert install <crt> <key>`:
#        - probes real writability and repairs caddy/data/custom-certs/
#          ownership without operator help (STATBUS-429 M2: this must work
#          whether custom-certs/ never existed, or already exists),
#        - places the certificate,
#        - rewrites .env.config to the correct container paths,
#        - regenerates config, restarts the proxy,
#        - verifies the served certificate matches what it installed.
#   4. caddy/data/caddy/ (Caddy's own ACME/PKI state) is byte-for-byte
#      untouched by the repair: its ownership is captured BEFORE `cert
#      install` runs and compared after.
#   5. A rerun of the real operator command (the install.sh curl|bash form
#      staged at /tmp/statbus-install.sh, exactly as a pasted-from-~
#      remedy would run it) reaches a ready installation with CA-verified
#      HTTPS.
#
# STATUS: UNRUN ON LXD. Authored and reviewed against the harness's LXD
# backend (lib/lxd-backend.sh) and assertion library, but never executed
# against the paid LXD fleet (test/install-recovery/README.md) — doing so
# requires a tagged release candidate at HEAD on that fleet. Run it via:
#   HARNESS_LXD_BACKEND=1 ./test/install-recovery/scenarios/5-install-cert-repair-via-cert-install.sh
#
# Usage:
#   ./test/install-recovery/scenarios/5-install-cert-repair-via-cert-install.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-cert-repair-via-cert-install}"
HARNESS_DEPLOYMENT_MODE=standalone
# STATBUS-429 M1b: opt OUT of the harness's normal pre-staged custom-certs
# (which would make caddy/data/ statbus-owned from the very first install
# and never reproduce Ville's root-owned state at all).
HARNESS_NO_CUSTOM_CERT=1

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

echo ""
echo "── initial clean install with NO custom certificate at all ──"
echo "   (caddy/data/ is created root:root by Docker on the proxy's first start)"
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
# HARNESS_NO_CUSTOM_CERT=1 means Caddy served its own auto-generated internal
# cert; standalone health without a public domain cannot be CA-verified yet,
# so only confirm the box is up (docker-level), not HTTPS correctness — the
# HTTPS proof comes after the repair below.
[ "$(VM_EXEC bash -c 'cd ~/statbus && docker compose ps -q | wc -l' | tr -d ' ')" -gt 0 ] || { echo 'FAIL: no services started' >&2; exit 1; }

echo ""
echo "── confirm caddy/data/ is root-owned (Services already ran once, no custom cert was ever staged) ──"
OWNER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data")
[ "$OWNER" = "root:root" ] || { echo "FAIL: expected caddy/data/ root:root, got $OWNER" >&2; exit 1; }
echo "  ✓ caddy/data/ is $OWNER (Docker created it on first Services run)"
CADDY_OWNER_BEFORE=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data/caddy 2>/dev/null || echo absent")

echo ""
echo "── hand-edit .env.config to an INVALID host-path cert (Ville's mistake), pointing at the harness CA-signed cert ──"
VM_EXEC bash -c "cd ~/statbus && printf 'TLS_CERT_FILE=/home/statbus/harness-certs/domain.crt\nTLS_KEY_FILE=/home/statbus/harness-certs/domain.key\n' >> .env.config"

REFUSAL_LOG=$(mktemp)
if VM_EXEC bash -c "cd ~/statbus && ./sb install --non-interactive" >"$REFUSAL_LOG" 2>&1; then
    cat "$REFUSAL_LOG" >&2
    echo 'FAIL: install should have refused on the invalid host-path certificate' >&2
    exit 1
fi
grep -Fq 'The custom certificate settings are invalid.' "$REFUSAL_LOG" || { cat "$REFUSAL_LOG" >&2; exit 1; }
grep -Fq 'cd ~/statbus && ./sb cert install' "$REFUSAL_LOG" || { cat "$REFUSAL_LOG" >&2; echo 'FAIL: refusal must name cd ~/statbus && ./sb cert install (STATBUS-429 M4), not a manual mkdir/cp remedy or a bare ./sb' >&2; exit 1; }
echo 'PASS: Settings refused the invalid host-path certificate and named cd ~/statbus && ./sb cert install'

echo ""
echo "── operator follows the printed remedy: ./sb cert install, no sudo ──"
CERT_LOG=$(mktemp)
VM_EXEC bash -c "cd ~/statbus && ./sb cert install /home/statbus/harness-certs/domain.crt /home/statbus/harness-certs/domain.key" >"$CERT_LOG" 2>&1 || { cat "$CERT_LOG" >&2; exit 1; }
grep -Fq '✓ Files placed:' "$CERT_LOG" || { cat "$CERT_LOG" >&2; echo 'FAIL: cert install did not report file placement' >&2; exit 1; }
grep -Fq '✓ .env.config updated' "$CERT_LOG" || { cat "$CERT_LOG" >&2; exit 1; }
grep -Fq '✓ Caddy restarted' "$CERT_LOG" || { cat "$CERT_LOG" >&2; exit 1; }
grep -Eq '✓ Verified: https://.* serves the new certificate' "$CERT_LOG" || { cat "$CERT_LOG" >&2; echo 'FAIL: cert install did not verify the served certificate' >&2; exit 1; }
echo 'PASS: ./sb cert install repaired ownership, placed the cert, and verified it is served — unprivileged, no sudo'

echo ""
echo "── custom-certs/ is now owned by the statbus user; caddy/data/caddy/ (Caddy's own ACME state) is byte-for-byte unchanged ──"
NEW_OWNER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data/custom-certs")
[ "$NEW_OWNER" = "statbus:statbus" ] || { echo "FAIL: expected custom-certs/ statbus:statbus, got $NEW_OWNER" >&2; exit 1; }
CADDY_OWNER_AFTER=$(VM_EXEC bash -c "stat -c '%U:%G' ~/statbus/caddy/data/caddy 2>/dev/null || echo absent")
[ "$CADDY_OWNER_AFTER" = "$CADDY_OWNER_BEFORE" ] || { echo "FAIL: caddy/data/caddy/ ownership changed ($CADDY_OWNER_BEFORE -> $CADDY_OWNER_AFTER); the repair must be scoped to custom-certs/ only" >&2; exit 1; }
echo "  ✓ custom-certs/ is $NEW_OWNER; caddy/data/caddy/ is unchanged ($CADDY_OWNER_AFTER)"

echo ""
echo "── rerun via the exact operator command the printed remedy would have named (curl | bash form) ──"
RERUN_LOG=$(mktemp)
VM_EXEC bash -c "cd ~ && bash /tmp/statbus-install.sh --non-interactive" >"$RERUN_LOG" 2>&1 || { cat "$RERUN_LOG" >&2; exit 1; }
grep -Eq '^\[[0-9]+/[0-9]+\] Settings +OK' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; echo 'FAIL: Settings should now pass with the corrected certificate paths' >&2; exit 1; }
assert_health_passes "$VM_NAME"
assert_harness_https_passes
echo 'PASS: box reached a ready installation with CA-verified HTTPS after the ./sb cert install repair'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PASS: 5-install-cert-repair-via-cert-install"
echo "════════════════════════════════════════════════════════════════"
