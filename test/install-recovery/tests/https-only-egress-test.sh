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
        'nft add set inet statbus_https_only local_ipv4 { type ipv4_addr; flags interval; }' \
        'nft add set inet statbus_https_only local_ipv6 { type ipv6_addr; flags interval; }' \
        'nft add element inet statbus_https_only local_ipv4 { 127.0.0.0/8 }' \
        'nft add element inet statbus_https_only local_ipv6 { ::1 }' \
        'nft add rule inet statbus_https_only output meta nfproto ipv4 ct original protocol tcp ct original ip daddr != @local_ipv4 ct original proto-dst 80 reject' \
        'nft add rule inet statbus_https_only output meta nfproto ipv6 ct original protocol tcp ct original ip6 daddr != @local_ipv6 ct original proto-dst 80 reject' \
        'curl --noproxy * -4 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://93.184.216.34/statbus-http-egress-mutation' \
        'curl --noproxy * -6 --fail --silent --show-error --connect-timeout 3 --max-time 5 http://[2606:2800:220:1:248:1893:25c8:1946]/statbus-http-egress-mutation' \
        'curl --noproxy * --fail --silent --show-error http://127.0.0.1:3010/rest/'
    grep -Fq 'IPv4 TCP/80 connection refused' <<<"$output" || die 'missing IPv4 enforcement diagnostic'
    grep -Fq 'IPv6 TCP/80 connection refused' <<<"$output" || die 'missing IPv6 enforcement diagnostic'
    grep -Fq 'loopback health path allowed' <<<"$output" || die 'missing loopback exemption diagnostic'
}

run_contract() {
    local events="$1" rule_state
    rule_state=$(mktemp)
    : > "$rule_state"

    VM_EXEC() {
        printf '%s\n' "$*" >> "$events"
        case "$*" in
            *'bash -c command -v nft'*) return 0 ;;
            'ip -o -4 addr show') printf '%s\n' '1: lo    inet 127.0.0.1/8' '2: eth0    inet 192.0.2.10/32'; return 0 ;;
            'ip -o -6 addr show') printf '%s\n' '1: lo    inet6 ::1/128' '2: eth0    inet6 2001:db8::10/64'; return 0 ;;
            *'ip -6 route get 2606:2800:220:1:248:1893:25c8:1946'*) return 0 ;;
            *'curl --noproxy * -4 --fail'*'http://93.184.216.34/'*)
                grep -Eq '^(canonical-ipv4|post-nat)$' "$rule_state" && return 7
                return 0
                ;;
            *'curl --noproxy * -6 --fail'*'http://[2606:2800:220:1:248:1893:25c8:1946]/'*)
                grep -Eq '^(canonical-ipv6|post-nat)$' "$rule_state" && return 7
                return 0
                ;;
            *'curl --noproxy * --fail --silent --show-error http://127.0.0.1:3010/rest/'*)
                # Docker DNAT rewrites this packet to bridge-address:80 before filter
                # OUTPUT. Only a post-NAT daddr/dport rule wrongly rejects it.
                grep -Fqx 'post-nat' "$rule_state" && return 7
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
            'nft add table inet statbus_https_only'|'nft add chain inet statbus_https_only output { type filter hook output priority 0; policy accept; }'|'nft add set inet statbus_https_only local_ipv4 { type ipv4_addr; flags interval; }'|'nft add set inet statbus_https_only local_ipv6 { type ipv6_addr; flags interval; }'|'nft add element inet statbus_https_only local_ipv4 { 127.0.0.0/8 }'|'nft add element inet statbus_https_only local_ipv6 { ::1 }'|'nft add element inet statbus_https_only local_ipv4 { 192.0.2.10 }'|'nft add element inet statbus_https_only local_ipv6 { 2001:db8::10 }') return 0 ;;
            'nft add rule inet statbus_https_only output meta nfproto ipv4 ct original protocol tcp ct original ip daddr != @local_ipv4 ct original proto-dst 80 reject') printf '%s\n' canonical-ipv4 >> "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output meta nfproto ipv6 ct original protocol tcp ct original ip6 daddr != @local_ipv6 ct original proto-dst 80 reject') printf '%s\n' canonical-ipv6 >> "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output meta nfproto ipv4 ip daddr != @local_ipv4 tcp dport 80 reject'|'nft add rule inet statbus_https_only output meta nfproto ipv6 ip6 daddr != @local_ipv6 tcp dport 80 reject') printf '%s\n' post-nat >> "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output ct original protocol tcp ct original proto-dst 80 reject') printf '%s\n' canonical-ipv4 canonical-ipv6 >> "$rule_state"; return 0 ;;
            'nft add rule inet statbus_https_only output meta nfproto ipv4 ct original protocol tcp ct original ip daddr != @local_ipv4 ct original proto-dst 80 accept') return 0 ;;
            'nft list chain inet statbus_https_only output')
                grep -Fqx canonical-ipv4 "$rule_state" && echo 'meta nfproto ipv4 ct original protocol tcp ct original ip daddr != @local_ipv4 ct original proto-dst 80 reject'
                grep -Fqx canonical-ipv6 "$rule_state" && echo 'meta nfproto ipv6 ct original protocol tcp ct original ip6 daddr != @local_ipv6 ct original proto-dst 80 reject'
                grep -Fqx post-nat "$rule_state" && printf '%s\n' 'meta nfproto ipv4 ip daddr != @local_ipv4 tcp dport 80 reject' 'meta nfproto ipv6 ip6 daddr != @local_ipv6 tcp dport 80 reject'
                return 0
                ;;
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
    local description="$1" mutated_bootstrap="$2" expected_failure="$3"
    local mutated_events mutation_output mutation_rc
    mutated_events=$(mktemp)
    set +e
    mutation_output=$(source "$mutated_bootstrap"; trap - ERR EXIT; set +e; mutated_output=$(run_contract "$mutated_events" 2>&1); mutation_rc=$?; if [ "$mutation_rc" -ne 0 ]; then printf '%s\n' "$mutated_output"; exit "$mutation_rc"; fi; assert_https_only_contract "$mutated_events" "$mutated_output" 2>&1)
    mutation_rc=$?
    set -e
    [ "$mutation_rc" -ne 0 ] || { rm -f "$mutated_events"; die "$description did not turn the offline contract red"; }
    grep -Fq "$expected_failure" <<<"$mutation_output" || { rm -f "$mutated_events"; die "$description failed for the wrong reason: $mutation_output"; }
    rm -f "$mutated_events"
}

events=$(mktemp)
missing_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-missing.XXXXXX")
unscoped_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-unscoped.XXXXXX")
widened_rule=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-widened.XXXXXX")
no_ipv6=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-no-ipv6.XXXXXX")
post_nat=$(mktemp "$ROOT/test/install-recovery/lib/.https-only-post-nat.XXXXXX")
trap 'rm -f "$events" "$missing_rule" "$unscoped_rule" "$widened_rule" "$no_ipv6" "$post_nat"' EXIT

output=$(run_contract "$events")
assert_https_only_contract "$events" "$output"

sed "/VM_ROOT_EXEC nft add rule inet statbus_https_only output meta nfproto ipv4 ct original protocol tcp/d" "$BOOTSTRAP" > "$missing_rule"
expect_mutation_red 'missing nft rule' "$missing_rule" 'nftables HTTPS-only output rule was not installed'

sed -e "s/meta nfproto ipv4 ct original protocol tcp ct original ip daddr '!=' @local_ipv4 ct original proto-dst 80 reject/ct original protocol tcp ct original proto-dst 80 reject/" -e "/VM_ROOT_EXEC nft add rule inet statbus_https_only output meta nfproto ipv6 ct original protocol tcp/d" "$BOOTSTRAP" > "$unscoped_rule"
expect_mutation_red 'unscoped all-destination rule' "$unscoped_rule" 'missing event: nft add rule inet statbus_https_only output meta nfproto ipv4'

sed 's/ct original proto-dst 80 reject/ct original proto-dst 80 accept/g' "$BOOTSTRAP" > "$widened_rule"
expect_mutation_red 'widened accept rule' "$widened_rule" 'nftables HTTPS-only output rule was not installed'

sed '/^[[:space:]]*VM_ROOT_EXEC nft add rule inet statbus_https_only output meta nfproto ipv6 ct original protocol tcp ct original ip6 daddr/d' "$BOOTSTRAP" > "$no_ipv6"
expect_mutation_red 'missing IPv6 rule' "$no_ipv6" 'nftables HTTPS-only output rule was not installed'

sed -e 's/ct original protocol tcp ct original ip daddr/ip daddr/' -e 's/ct original protocol tcp ct original ip6 daddr/ip6 daddr/' -e 's/ct original proto-dst 80/tcp dport 80/g' "$BOOTSTRAP" > "$post_nat"
expect_mutation_red 'post-NAT destination rule' "$post_nat" 'HTTPS-only rule blocked loopback health path'

grep -q 'HARNESS_HTTPS_ONLY_EGRESS=1' "$SCENARIO"
grep -Fq 'HARNESS_HARDENING_SKIP_STAGES=""' "$SCENARIO"
grep -q '0-happy-upgrade.sh' "$SCENARIO"
if grep -Fq 'HARNESS_SKIP_DEFAULT' "$SCENARIO"; then
    die 'HTTPS-only egress scenario remains excluded from the default set'
fi

echo 'PASS: HTTPS-only egress matches the pre-NAT original destination, preserves published loopback/container traffic, rejects external IPv4+IPv6 TCP/80, and every required mutation turns red'
