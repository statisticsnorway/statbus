#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BOOTSTRAP="$ROOT/test/install-recovery/lib/vm-bootstrap.sh"
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
        'bash -c command -v iptables >/dev/null 2>&1 && command -v ip6tables >/dev/null 2>&1' \
        'sudo apt-get update' \
        'sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y iptables' \
        'sudo iptables --version' \
        'sudo ip6tables --version' \
        'sudo iptables -A OUTPUT -p tcp --dport 80 -j REJECT' \
        'sudo ip6tables -A OUTPUT -p tcp --dport 80 -j REJECT' \
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
    local tools_check_count=0
    VM_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            *'bash -c command -v iptables'*)
                tools_check_count=$(grep -cF 'bash -c command -v iptables' "$events")
                if [ "$tools_check_count" -gt 1 ]; then
                    return 0
                fi
                return 1
                ;;
            *'iptables --version'|*'ip6tables --version') return 0 ;;
            *'iptables -C OUTPUT'|*'ip6tables -C OUTPUT') return 1 ;;
            *'iptables -A OUTPUT'|*'ip6tables -A OUTPUT') return 0 ;;
            *'curl --noproxy * -4 --fail'*'http://93.184.216.34/'*) return 7 ;;
            *'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946'*) return 0 ;;
            *'curl --noproxy * -6 --fail'*'http://[2606:2800:220:1:248:1893:25c8:1946]/'*) return 7 ;;
            *'apt-get update'|*'apt-get install -y iptables') return 0 ;;
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

# Negative control: omitting the IPv6 rule must make the same contract red.
sed 's/for firewall in iptables ip6tables; do/for firewall in iptables; do/' "$BOOTSTRAP" > "$mutated_bootstrap"
if (
    source "$mutated_bootstrap"
    mutated_output=$(run_contract "$mutated_events")
    assert_https_only_contract "$mutated_events" "$mutated_output"
) >/dev/null 2>&1; then
    die 'skipping the ip6tables rule did not turn the offline contract red'
fi

grep -q 'HARNESS_HTTPS_ONLY_EGRESS=1' "$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
grep -q '0-happy-upgrade.sh' "$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
grep -Fq 'HARNESS_VM_IMAGE="ubuntu-24.04"' "$ROOT/test/install-recovery/scenarios/0-happy-upgrade.sh"
grep -Fq 'HARNESS_VM_IMAGE="${HARNESS_VM_IMAGE:-ubuntu-26.04}"' "$BOOTSTRAP"
echo 'PASS: HTTPS-only scenario ensures tools, installs both rules, and verifies IPv4/IPv6 enforcement in order'
