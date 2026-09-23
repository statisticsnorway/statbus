#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/vm-bootstrap.sh"

events=$(mktemp)
trap 'rm -f "$events"' EXIT
VM_EXEC() {
    printf '%s\n' "$*" >> "$events"
    case "$*" in
        *'iptables -C OUTPUT'*) return 1 ;;
        *'iptables -A OUTPUT'*) return 0 ;;
        *'curl --fail'*'http://example.com/statbus-http-egress-mutation'*) return 7 ;;
    esac
    return 99
}

output=$(apply_https_only_egress)
grep -q 'iptables -A OUTPUT -p tcp --dport 80 -j REJECT' "$events"
grep -q 'curl --fail --silent --show-error --max-time 5 http://example.com/statbus-http-egress-mutation' "$events"
grep -q 'plain-HTTP fetch rejected: http://example.com/statbus-http-egress-mutation' <<<"$output"
grep -q 'HARNESS_HTTPS_ONLY_EGRESS=1' "$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
grep -q '0-happy-upgrade.sh' "$ROOT/test/install-recovery/scenarios/0-https-only-egress.sh"
echo 'PASS: HTTPS-only scenario reuses happy upgrade and its HTTP mutation is rejected with the URL named'
