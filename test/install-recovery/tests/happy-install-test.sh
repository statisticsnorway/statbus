#!/bin/bash
# Offline scenario control-flow tests. No credentials, SSH, VM, Docker or DB.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-369-happy.XXXXXX")
trap 'rc=$?; if [ "$rc" -ne 0 ]; then cat "$TMP_ROOT/output" "$TMP_ROOT/trace" >&2 2>/dev/null || true; fi; rm -rf "$TMP_ROOT"' EXIT
HARNESS="$TMP_ROOT/test/install-recovery"
mkdir -p "$HARNESS/lib" "$HARNESS/scenarios"
cp "$TEST_DIR/../scenarios/0-happy-install.sh" "$HARNESS/scenarios/"
cp "$TEST_DIR/../lib/release-baseline.sh" "$HARNESS/lib/"
cat > "$HARNESS/lib/vm-bootstrap.sh" <<'MOCK'
bootstrap_install_test_vm() { echo "bootstrap:$*" >> "$TRACE"; }
install_statbus_in_vm() { echo "WRONG:baseline-install:$*" >> "$TRACE"; }
install_statbus_at_sha() { echo "candidate-install:$*" >> "$TRACE"; }
cleanup_vm() { echo cleanup >> "$TRACE"; }
VM_SCRIPT() { echo operator-settings >> "$TRACE"; [ "${FAULT:-}" != operator-settings ]; }
VM_EXEC() {
    echo "query:$*" >> "$TRACE"
	case "$*" in
		*'grep -F -q test-install-password-2026'*) return 1 ;;
		*'/tmp/statbus-install.sh --non-interactive'*)
			[ "${FAULT:-}" != rerun ] || return 45
			for n in $(seq 1 17); do
				[ "${FAULT:-}" != missing-step ] || [ "$n" != 7 ] || continue
				if [ "$n" = 12 ]; then printf '[12/17] Seed                 OK\n'; else printf '[%d/17] Step%-16d OK\n' "$n" "$n"; fi
				[ "${FAULT:-}" != duplicate-step ] || [ "$n" != 7 ] || printf '[7/17] Step7            OK\n'
			done
			;;
        *CADDY_DEPLOYMENT_MODE*) echo "${INSTALLED_MODE:-private}" ;;
        *UPGRADE_CHANNEL*) [ "${FAULT:-}" != channel-transport ] || return 44; echo "${INSTALLED_CHANNEL:-stable}" ;;
        *--version*) [ "${FAULT:-}" != transport ] || return 42
            echo "sb version ${BINARY_VERSION:-v2026.09.0-rc.02} (commit ${TARGET_SHA:0:8})" ;;
        *'SELECT '*public.upgrade*)
            [ "${FAULT:-}" != sql ] || return 43
            [ "${FAULT:-}" != empty-row ] || return 0
            echo "${ROW_VERSION:-v2026.09.0-rc.02}|${ROW_SHA:-$TARGET_SHA}|${ROW_STATE:-completed}" ;;
        *) echo "Unexpected VM command: $*" >&2; return 90 ;;
    esac
}
MOCK
cat > "$HARNESS/lib/assertions.sh" <<'MOCK'
assert_health_passes() { echo health >> "$TRACE"; [ "${FAULT:-}" != health ]; }
assert_step9_completed() { :; }
assert_step_upgrade_service_completed() { :; }
assert_systemd_active() { :; }
MOCK
git -C "$TMP_ROOT" init -q
git -C "$TMP_ROOT" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit --allow-empty -qm baseline
git -C "$TMP_ROOT" tag v2026.08.1
git -C "$TMP_ROOT" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit --allow-empty -qm candidate
git -C "$TMP_ROOT" tag v2026.09.0-rc.02
export TRACE="$TMP_ROOT/trace"
export TARGET_SHA
auto_sha=$(git -C "$TMP_ROOT" rev-parse HEAD)
TARGET_SHA="$auto_sha"
SCENARIO="$HARNESS/scenarios/0-happy-install.sh"
if ! bash "$SCENARIO" > "$TMP_ROOT/output" 2>&1; then
    cat "$TMP_ROOT/output" >&2
    cat "$TRACE" >&2
    exit 1
fi
if ! grep -Fxq "candidate-install:statbus-recovery-0-happy-install $TARGET_SHA v2026.09.0-rc.02" "$TRACE"; then
    echo 'FAIL: fresh install did not install the candidate via the SHA helper' >&2
    cat "$TRACE" >&2
    exit 1
fi
grep -Fq 'ORDER BY id DESC LIMIT 1' "$TRACE"
grep -Fxq health "$TRACE"
grep -Fxq operator-settings "$TRACE"
grep -Fq '/tmp/statbus-install.sh --non-interactive' "$TRACE"
! grep -Fq 'https://statbus.org/install.sh' "$TRACE"
# Operator tuning must follow the on-box identity checks and initial health.
identity_line=$(grep -n 'ORDER BY id DESC LIMIT 1' "$TRACE" | cut -d: -f1)
operator_line=$(grep -n '^operator-settings$' "$TRACE" | cut -d: -f1)
[ "$identity_line" -lt "$operator_line" ]
echo 'PASS: candidate selected, installed, binary/ledger/health checked'
for assignment in BINARY_VERSION=v2026.08.1 ROW_VERSION=v2026.08.1 ROW_SHA=deadbeef ROW_STATE=failed FAULT=transport FAULT=sql FAULT=empty-row FAULT=health FAULT=operator-settings FAULT=channel-transport FAULT=rerun FAULT=missing-step FAULT=duplicate-step INSTALLED_MODE=development INSTALLED_CHANNEL=local HARNESS_DEPLOYMENT_MODE=development HARNESS_UPGRADE_CHANNEL=prerelease INSTALL_TARGET_TAG=v2026.08.1 INSTALL_TARGET_TAG=not-a-release; do
    : > "$TRACE"
    if env "$assignment" bash "$SCENARIO" > "$TMP_ROOT/output" 2>&1; then
        echo "FAIL: accepted $assignment" >&2; exit 1
    fi
    echo "PASS: refused $assignment"
done
# Neither an inherited baseline override nor an untagged HEAD may weaken the proof.
if INSTALL_VERSION=v2026.08.1 bash "$SCENARIO" > "$TMP_ROOT/output" 2>&1; then
    echo 'FAIL: accepted baseline override' >&2; exit 1
fi
git -C "$TMP_ROOT" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit --allow-empty -qm untagged
: > "$TRACE"
if bash "$SCENARIO" > "$TMP_ROOT/output" 2>&1; then
    echo 'FAIL: accepted untagged HEAD' >&2; exit 1
fi
[ ! -s "$TRACE" ] || { echo 'FAIL: touched VM before validating candidate'; exit 1; }
echo 'PASS: untagged HEAD refused before bootstrap'
echo 'happy-install tests: PASS'
