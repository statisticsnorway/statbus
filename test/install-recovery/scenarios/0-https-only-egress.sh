#!/bin/bash
# Scenario: 0-https-only-egress
# Reuses the complete 0-happy-upgrade install and supervised upgrade proof, but
# rejects every IPv4 and IPv6 outbound TCP/80 connection immediately after
# bootstrap. Albania's network may DROP instead; REJECT is the stricter, faster
# regression proxy.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HARNESS_HTTPS_ONLY_EGRESS=1
exec bash "$SCENARIO_DIR/0-happy-upgrade.sh" "${1:-statbus-recovery-0-https-only-egress}"
