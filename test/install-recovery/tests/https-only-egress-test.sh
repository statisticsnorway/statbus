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
        'nft --version' \
        'nft add table inet statbus_https_only' \
        'nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }' \
        'nft add rule inet statbus_https_only output oifname != lo tcp dport 80 reject' \
        'nft list chain inet statbus_https_only output' \
        'curl --noproxy * -4 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://93.184.216.34/statbus-http-egress-mutation' \
        'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946' \
        'curl --noproxy * -6 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation' \
        'curl --noproxy * --fail --silent --show-error http://127.0.0.1:3010/rest/'
    grep -Fq 'IPv4 TCP/80 connection refused: http://93.184.216.34/statbus-http-egress-mutation' <<<"$output" \
        || die 'missing IPv4 enforcement diagnostic'
    grep -Fq 'IPv6 TCP/80 connection refused: http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation' <<<"$output" \
        || die 'missing IPv6 enforcement diagnostic'
    grep -Fq 'loopback health path allowed: http://127.0.0.1:3010/rest/' <<<"$output" \
        || die 'missing loopback exemption diagnostic'
}

run_contract() {
    local events="$1"
    local rule_state
    rule_state=$(mktemp)
    : > "$rule_state"

    VM_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            *'bash -c command -v nft'*) return 0 ;;
            *'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946'*) return 0 ;;
            *'curl --noproxy * -4 --fail'*'http://93.184.216.34/'*)
                grep -Eq '^(oifname != "lo" )?tcp dport 80 reject$' "$rule_state" && return 7
                return 0
                ;;
            *'curl --noproxy * -6 --fail'*'http://[2606:2800:220:1:248:1893:25c8:1946]/'*)
                grep -Eq '^(oifname != "lo" )?tcp dport 80 reject$' "$rule_state" && return 7
                return 0
                ;;
            *'curl --noproxy * --fail --silent --show-error http://127.0.0.1:3010/rest/'*)
                grep -Fqx 'tcp dport 80 reject' "$rule_state" && return 7
                return 0
                ;;
        esac
        return 99
    }
    VM_ROOT_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            'nft --version') return 0 ;;
            'nft list table inet statbus_https_only') return 1 ;;
            'nft add table inet statbus_https_only') return 0 ;;
            'nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }') return 0 ;;
            'nft add rule inet statbus_https_only output oifname != lo tcp dport 80 reject') printf '%s\n' 'oifname != "lo" tcp dport 80 reject' > "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output tcp dport 80 reject') printf '%s\n' 'tcp dport 80 reject' > "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output oifname != lo tcp dport 80 accept') printf '%s\n' 'oifname != "lo" tcp dport 80 accept' > "$rule_state"; return 0 ;;
            'nft list chain inet statbus_https_only output') cat "$rule_state"; return 0 ;;
        esac
        return 99
    }

    apply_https_only_egress || { rm -f "$rule_state"; return 1; }
    local loopback_url='http://127.0.0.1:3010/rest/'
    if ! VM_EXEC curl --noproxy '*' --fail --silent --show-error "$loopback_url" >/dev/null 2>&1; then
        echo "ERROR: HTTPS-only rule blocked loopback health path: $loopback_url" >&2
        rm -f "$rule_state"
        return 1
    fi
    echo "  ✓ loopback health path allowed: $loopback_url"
    rm -f "$rule_state"
}

expect_mutation_red() {
    local description="$1"
    local mutated_bootstrap="$2"
    local expected_failure="$3"
    local mutated_events mutation_output mutation_rc
    mutated_events=$(mktemp)
    set +e
    mutation_output=$(
        source "$mutated_bootstrap"
        trap - ERR EXIT
        set +e
        mutated_output=$(run_contract "$mutated_events" 2>&1)
        mutation_rc=$?
        if [ "$mutation_rc" -ne 0 ]; then
            printf '%s\n' "$mutated_output"
            exit "$mutation_rc"
        fi
        assert_https_only_contract "$mutated_events" "$mutated_output"
    2>&1)
    mutation_rc=$?
    set -e
    if [ "$mutation_rc" -eq 0 ]; then
        rm -f "$mutated_events"
        die "$description did not turn the offline contract red"
    fi
    if [ -n "$expected_failure" ]; then
        grep -Fq "$expected_failure" <<<"$mutation_output" || {
            rm -f "$mutated_events"
            die "$description failed for the wrong reason: $mutation_output"
        }
    fi
    rm -f "$mutated_events"
}

events=$(mktemp)
missing_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-missing.XXXXXX")
unscoped_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-unscoped.XXXXXX")
widened_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-widened.XXXXXX")
no_ipv6=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-no-ipv6.XXXXXX")
no_ipv6_events=$(mktemp)
trap 'rm -f "$events" "$missing_rule" "$unscoped_rule" "$widened_rule" "$no_ipv6" "$no_ipv6_events"' EXIT

output=$(run_contract "$events")
assert_https_only_contract "$events" "$output"

sed "/VM_ROOT_EXEC nft add rule inet statbus_https_only output oifname '!=' lo tcp dport 80 reject/d" "$BOOTSTRAP" > "$missing_rule"
expect_mutation_red 'missing nft rule' "$missing_rule" 'nftables HTTPS-only output rule was not installed'

sed -e "s/oifname '!=' lo //g" -e 's/oifname != \"lo\" //g' "$BOOTSTRAP" > "$unscoped_rule"
expect_mutation_red 'unscoped rc.02 rule that blocks loopback' "$unscoped_rule" 'HTTPS-only rule blocked loopback health path'

sed 's/tcp dport 80 reject/tcp dport 80 accept/g' "$BOOTSTRAP" > "$widened_rule"
expect_mutation_red 'widened accept rule' "$widened_rule" 'IPv4 HTTPS-only egress probe expected connection refusal'

sed '/if ! VM_EXEC ip -6 route get/,/echo "  ✓ deliberate IPv6 TCP\/80 connection refused/d' "$BOOTSTRAP" > "$no_ipv6"
if (
    source "$no_ipv6"
    trap - ERR EXIT
    no_ipv6_output=$(run_contract "$no_ipv6_events")
    assert_https_only_contract "$no_ipv6_events" "$no_ipv6_output"
) >/dev/null 2>&1; then
    die 'missing IPv6 enforcement path did not turn the offline contract red'
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
! grep -Fq 'sudo nft' "$events" \
    || die 'HTTPS-only policy incorrectly relies on the hardened statbus account having general sudo access'
grep -Fq 'oifname != lo tcp dport 80 reject' "$events" \
    || die 'HTTPS-only policy does not exempt host-local loopback traffic'
! grep -Fxq 'nft add rule inet statbus_https_only output tcp dport 80 reject' "$events" \
    || die 'HTTPS-only policy still rejects loopback TCP/80 along with external egress'
echo 'PASS: HTTPS registry/seed/APT traffic is exercised under enforcement; the baseline repo uses harness SSH/SCP; offline semantics reject external IPv4/IPv6 and allow loopback'
