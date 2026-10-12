#!/bin/bash
# STATBUS-357 acceptance criterion 2: mutations that MUST turn the HTTPS-only
# contract red, run against BOTH backends.
#
# Why both: the scenario calls apply_https_only_egress on whichever backend the
# runner installs in place of vm-bootstrap.sh (lxd/run-forks.sh symlinks the LXD
# backend over it). A rule that exists in only one of them means the scenario
# cannot run on the other — which is exactly how the LXD migration left this
# scenario dead while it still looked like coverage. So a mutation must turn the
# contract red for the backend that SHIPS today, not only for the retired one.
#
# The public destination in the probe is written as its IP, 93.184.216.34, which
# IS example.com — kept as a literal so the assertion needs no DNS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)

# The harness (stubs, run_contract, expect_mutation_red) lives in the contract
# test; HTTPS_ONLY_TEST_LIB makes it define the harness and stop before running.
HTTPS_ONLY_TEST_LIB=1 source "$ROOT/test/install-recovery/tests/https-only-egress-test.sh"
trap - ERR

LIB_DIR="$ROOT/test/install-recovery/lib"
mutations=(
    'missing IPv4 nft rule|/^[[:space:]]*VM_ROOT_EXEC nft add rule inet statbus_https_only output ip daddr/d||nftables HTTPS-only output rule was not installed'
    'widened accept rule|s/tcp dport 80 reject/tcp dport 80 accept/g||IPv4 HTTPS-only egress probe expected connection refusal'
    'missing IPv6 rule|/^[[:space:]]*VM_ROOT_EXEC nft add rule inet statbus_https_only output ip6 daddr/d||nftables HTTPS-only output rule was not installed'
    'exempt set lacks 172.16.0.0/12|s/, 172\.16\.0\.0\/12//g||HTTPS-only rule rejected docker-proxy host -> 172.18.0.3:80'
)

for backend in vm-bootstrap lxd-backend; do
    backend_lib="$LIB_DIR/$backend.sh"
    [ -f "$backend_lib" ] || { echo "FAIL: no $backend_lib" >&2; exit 1; }

    for entry in "${mutations[@]}"; do
        description=${entry%%|*}; rest=${entry#*|}
        sed_expression=${rest%%||*}; expected=${rest##*||}
        mutated=$(mktemp "$LIB_DIR/.https-only-mutation.XXXXXX")
        sed "$sed_expression" "$backend_lib" > "$mutated"
        expect_mutation_red "$description [$backend]" "$mutated" "$expected"
        rm -f "$mutated"
    done

    # The failure must NAME the URL it refused, or an operator cannot tell which
    # destination was let through. Widen the rule and look for the literal URL in
    # the diagnostic, not merely for a non-zero exit.
    widened=$(mktemp "$LIB_DIR/.https-only-mutation.XXXXXX")
    sed 's/tcp dport 80 reject/tcp dport 80 accept/g' "$backend_lib" > "$widened"
    mutation_output=$(set +e; unset -f apply_https_only_egress; HTTPS_ONLY_TEST_LIB=1 source "$widened"; trap - ERR EXIT; set +e; run_contract "$(mktemp)" 2>&1) || true  # red is expected; the grep below asserts the URL
    grep -Fq 'statbus-http-egress-mutation' <<<"$mutation_output" \
        || { echo "FAIL: [$backend] the widened rule failed without naming the URL: $mutation_output" >&2; exit 1; }
    rm -f "$widened"
    echo "  ✓ $backend: four rule mutations and the URL-naming mutation all turn the contract red"
done

echo 'PASS: the HTTPS-only contract is consequential on both backends, and names the URL it refused'
