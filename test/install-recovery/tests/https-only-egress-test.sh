#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BOOTSTRAP="$ROOT/test/install-recovery/lib/vm-bootstrap.sh"
SCENARIO="$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
source "$BOOTSTRAP"
trap - ERR

die() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_event_order() {
    local events="$1"
    shift
    local previous=0
    local pattern line
    for pattern in "$@"; do
        line=$(grep -nF "$pattern" "$events" | head -1 | cut -d: -f1) || die "missing event: $pattern"
        [ "$line" -gt "$previous" ] || die "event out of order: $pattern"
        previous="$line"
    done
}

assert_https_only_contract() {
    local events="$1"
    local output="$2"
    assert_event_order "$events" \
        'bash -c command -v nft >/dev/null 2>&1' \
        'sudo nft --version' \
        'sudo nft add table inet statbus_https_only' \
        'sudo nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }' \
        'sudo nft add rule inet statbus_https_only output tcp dport 80 reject' \
        'sudo nft list chain inet statbus_https_only output' \
        'curl --noproxy * -4 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://93.184.216.34/statbus-http-egress-mutation' \
        'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946' \
        'curl --noproxy * -6 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation'
    grep -Fq 'IPv4 TCP/80 connection refused: http://93.184.216.34/statbus-http-egress-mutation' <<<"$output" \
        || die 'missing IPv4 enforcement diagnostic'
    grep -Fq 'IPv6 TCP/80 connection refused: http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation' <<<"$output" \
        || die 'missing IPv6 enforcement diagnostic'
}

run_contract() {
    local events="$1"
    VM_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            *'bash -c command -v nft'*) return 0 ;;
            *'sudo nft --version') return 0 ;;
            *'sudo nft list table inet statbus_https_only') return 1 ;;
            *'sudo nft add table inet statbus_https_only') return 0 ;;
            *'sudo nft add chain inet statbus_https_only output'*) return 0 ;;
            *'sudo nft add rule inet statbus_https_only output tcp dport 80 reject') return 0 ;;
            *'sudo nft list chain inet statbus_https_only output') printf '%s\n' 'tcp dport 80 reject'; return 0 ;;
            *'curl --noproxy * -4 --fail'*'http://93.184.216.34/'*) return 7 ;;
            *'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946'*) return 0 ;;
            *'curl --noproxy * -6 --fail'*'http://[2606:2800:220:1:248:1893:25c8:1946]/'*) return 7 ;;
        esac
        return 99
    }
    apply_https_only_egress
}

events=$(mktemp)
mutated_bootstrap=$(mktemp)
mutated_events=$(mktemp)
trap 'rm -f "$events" "$mutated_bootstrap" "$mutated_events"' EXIT

output=$(run_contract "$events")
assert_https_only_contract "$events" "$output"

# Negative control: omitting the one inet-family rule must make the contract red.
sed '/VM_EXEC sudo nft add rule inet statbus_https_only output tcp dport 80 reject/d' "$BOOTSTRAP" > "$mutated_bootstrap"
if (
    source "$mutated_bootstrap"
    trap - ERR
    mutated_output=$(run_contract "$mutated_events")
    assert_https_only_contract "$mutated_events" "$mutated_output"
) >/dev/null 2>&1; then
    die 'skipping the inet-family nft rule did not turn the offline contract red'
fi

grep -q 'HARNESS_HTTPS_ONLY_EGRESS=1' "$SCENARIO"
grep -Fq 'HARNESS_HARDENING_SKIP_STAGES=""' "$SCENARIO"
grep -q '0-happy-upgrade.sh' "$SCENARIO"
grep -Fq 'HARNESS_VM_IMAGE="ubuntu-24.04"' "$ROOT/test/install-recovery/scenarios/0-happy-upgrade.sh"
grep -Fq 'if [ "${HARNESS_HTTPS_ONLY_EGRESS:-0}" != "1" ]; then' "$ROOT/test/install-recovery/scenarios/0-happy-upgrade.sh"
! grep -Eq 'ubuntu-24\.04|HARNESS_VM_IMAGE=' "$SCENARIO" \
    || die 'HTTPS-only scenario does not retain the Ubuntu 26.04 harness default'
grep -Fq 'HARNESS_VM_IMAGE="${HARNESS_VM_IMAGE:-ubuntu-26.04}"' "$BOOTSTRAP"
! grep -Eq 'iptables|ip6tables|apt-get install -y iptables' "$events" \
    || die 'HTTPS-only policy introduced parallel iptables tooling'
echo 'PASS: HTTPS-only scenario uses hardened nftables, installs one inet rule, and verifies IPv4/IPv6 enforcement in order'
