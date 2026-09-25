#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BOOTSTRAP="$ROOT/test/install-recovery/lib/vm-bootstrap.sh"
SCENARIO="$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
HAPPY_UPGRADE="$ROOT/test/install-recovery/scenarios/0-happy-upgrade.sh"
source "$BOOTSTRAP"
trap - ERR

die() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_event_order() {
    local events="$1"
    shift
    local previous=0 pattern line
    for pattern in "$@"; do
        line=$(grep -nF "$pattern" "$events" | head -1 | cut -d: -f1) || die "missing event: $pattern"
        [ "$line" -gt "$previous" ] || die "event out of order: $pattern"
        previous="$line"
    done
}

assert_https_only_contract() {
    local events="$1" output="$2"
    assert_event_order "$events" \
        'bash -c command -v nft >/dev/null 2>&1' \
        'nft --version' \
        'nft add table inet statbus_https_only' \
        'nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }' \
        'nft add rule inet statbus_https_only output ip daddr != { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 80 reject' \
        'nft add rule inet statbus_https_only output ip6 daddr != { ::1, fc00::/7, fe80::/10 } tcp dport 80 reject' \
        'curl --noproxy * -4 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://93.184.216.34/statbus-http-egress-mutation' \
        'curl --noproxy * -6 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation' \
        'curl --noproxy * --fail --silent --show-error http://127.0.0.1:80/rest/'
    grep -Fq 'IPv4 TCP/80 connection refused' <<<"$output" || die 'missing IPv4 enforcement diagnostic'
    grep -Fq 'IPv6 TCP/80 connection refused' <<<"$output" || die 'missing IPv6 enforcement diagnostic'
    grep -Fq 'docker-proxy health path allowed' <<<"$output" || die 'missing docker-proxy exemption diagnostic'
}

run_contract() {
    local events="$1" rule_state
    rule_state=$(mktemp)
    : > "$rule_state"

    ipv4_to_int() {
        local address="$1" a b c d
        IFS=. read -r a b c d <<<"$address"
        printf '%u\n' "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
    }

    ipv4_in_cidr() {
        local address="$1" cidr="$2" network prefix address_int network_int mask
        network=${cidr%/*}
        prefix=${cidr#*/}
        address_int=$(ipv4_to_int "$address")
        network_int=$(ipv4_to_int "$network")
        mask=$(( (0xffffffff << (32 - prefix)) & 0xffffffff ))
        [ $((address_int & mask)) -eq $((network_int & mask)) ]
    }

    destination_is_exempt() {
        local family="$1" destination="$2" rule="$3" cidr
        if [ "$family" = "ipv4" ]; then
            while read -r cidr; do
                ipv4_in_cidr "$destination" "$cidr" && return 0
            done < <(grep -Eo '[0-9]+(\.[0-9]+){3}/[0-9]+' <<<"$rule")
            return 1
        fi
        while read -r cidr; do
            case "$cidr" in
                ::1) [ "$destination" = "::1" ] && return 0 ;;
                fc00::/7) [[ "$destination" = f[c-d]* ]] && return 0 ;;
                fe80::/10) [[ "$destination" = f[e-f][89abAB]* ]] && return 0 ;;
            esac
        done < <(grep -Eo '::1|fc00::/7|fe80::/10' <<<"$rule")
        return 1
    }

    packet_rejected() {
        local family="$1" destination="$2" rule family_selector
        case "$family" in
            ipv4) family_selector='^ip daddr' ;;
            ipv6) family_selector='^ip6 daddr' ;;
        esac
        rule=$(grep -E "$family_selector" "$rule_state" | tail -1 || true)
        [ -n "$rule" ] || return 1
        grep -Fq ' tcp dport 80 reject' <<<"$rule" || return 1
        # Docker's default userland-proxy accepts 127.0.0.1:80, then opens a
        # new host -> 172.18.0.3:80 connection. There is no NAT. The outcome is
        # determined solely by whether that destination belongs to an exempt CIDR.
        ! destination_is_exempt "$family" "$destination" "$rule"
    }

    VM_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            *'bash -c command -v nft'*) return 0 ;;
            *'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946'*) return 0 ;;
            *'curl --noproxy * -4 --fail'*'http://93.184.216.34/'*)
                packet_rejected ipv4 93.184.216.34 && return 7
                return 0
                ;;
            *'curl --noproxy * -6 --fail'*'http://[2606:2800:220:1:248:1893:25c8:1946]/'*)
                packet_rejected ipv6 2606:2800:220:1:248:1893:25c8:1946 && return 7
                return 0
                ;;
            *'curl --noproxy * --fail --silent --show-error http://127.0.0.1:80/rest/'*)
                packet_rejected ipv4 172.18.0.3 && return 7
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
            'nft add table inet statbus_https_only'|'nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }') return 0 ;;
            nft\ add\ rule\ inet\ statbus_https_only\ output\ *)
                local listed_rule="$*"
                listed_rule=${listed_rule#nft add rule inet statbus_https_only output }
                listed_rule=${listed_rule#meta nfproto ipv4 }
                listed_rule=${listed_rule#meta nfproto ipv6 }
                case "$listed_rule" in
                    ip\ daddr*\ reject) listed_rule="${listed_rule% reject} reject with icmp port-unreachable" ;;
                    ip6\ daddr*\ reject) listed_rule="${listed_rule% reject} reject with icmpv6 port-unreachable" ;;
                esac
                printf '%s\n' "$listed_rule" >> "$rule_state"
                return 0
                ;;
            'nft list chain inet statbus_https_only output') cat "$rule_state"; return 0 ;;
        esac
        return 99
    }

    apply_https_only_egress || { rm -f "$rule_state"; return 1; }
    local loopback_url='http://127.0.0.1:80/rest/'
    if ! VM_EXEC curl --noproxy '*' --fail --silent --show-error "$loopback_url" >/dev/null 2>&1; then
        echo "ERROR: HTTPS-only rule rejected docker-proxy host -> 172.18.0.3:80: $loopback_url" >&2
        rm -f "$rule_state"
        return 1
    fi
    echo "  ✓ docker-proxy health path allowed without NAT: host -> 172.18.0.3:80"
    rm -f "$rule_state"
}

expect_mutation_red() {
    local description="$1" mutated_bootstrap="$2" expected_failure="$3"
    local mutated_events mutation_output mutation_rc
    mutated_events=$(mktemp)
    set +e
    mutation_output=$(source "$mutated_bootstrap"; trap - ERR EXIT; set +e; run_contract "$mutated_events" 2>&1)
    mutation_rc=$?
    set -e
    [ "$mutation_rc" -ne 0 ] || { rm -f "$mutated_events"; die "$description did not turn the offline contract red"; }
    grep -Fq "$expected_failure" <<<"$mutation_output" || { rm -f "$mutated_events"; die "$description failed for the wrong reason: $mutation_output"; }
    rm -f "$mutated_events"
}

events=$(mktemp)
missing_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-missing.XXXXXX")
widened_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-widened.XXXXXX")
no_ipv6=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-no-ipv6.XXXXXX")
no_docker_bridge=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-no-docker-bridge.XXXXXX")
trap 'rm -f "$events" "$missing_rule" "$widened_rule" "$no_ipv6" "$no_docker_bridge"' EXIT

output=$(run_contract "$events")
assert_https_only_contract "$events" "$output"

sed '/^[[:space:]]*VM_ROOT_EXEC nft add rule inet statbus_https_only output ip daddr/d' "$BOOTSTRAP" > "$missing_rule"
expect_mutation_red 'missing IPv4 nft rule' "$missing_rule" 'nftables HTTPS-only output rule was not installed'

sed 's/tcp dport 80 reject/tcp dport 80 accept/g' "$BOOTSTRAP" > "$widened_rule"
expect_mutation_red 'widened accept rule' "$widened_rule" 'IPv4 HTTPS-only egress probe expected connection refusal'

sed '/^[[:space:]]*VM_ROOT_EXEC nft add rule inet statbus_https_only output ip6 daddr/d' "$BOOTSTRAP" > "$no_ipv6"
expect_mutation_red 'missing IPv6 rule' "$no_ipv6" 'nftables HTTPS-only output rule was not installed'

sed 's/, 172\.16\.0\.0\/12//g' "$BOOTSTRAP" > "$no_docker_bridge"
expect_mutation_red 'exempt set lacks 172.16.0.0/12' "$no_docker_bridge" 'HTTPS-only rule rejected docker-proxy host -> 172.18.0.3:80'

grep -q 'HARNESS_HTTPS_ONLY_EGRESS=1' "$SCENARIO"
grep -Fq 'HARNESS_HARDENING_SKIP_STAGES=""' "$SCENARIO"
grep -Fq 'HARNESS_SKIP_DEFAULT' "$SCENARIO"
grep -q '0-happy-upgrade.sh' "$SCENARIO"
grep -Fq 'at-install docker-proxy health path allowed' "$HAPPY_UPGRADE" \
    || die 'shared install flow lacks the fast at-install docker-proxy positive probe'

echo 'PASS: HTTPS-only egress allows Docker bridge destinations without NAT, rejects public IPv4+IPv6 TCP/80, keeps the scenario on-demand, and required mutations turn red'
