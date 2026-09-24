#!/bin/bash
# Scenario: 0-https-only-egress
# Reuses the complete 0-happy-upgrade install and supervised upgrade proof, but
# rejects every IPv4 and IPv6 outbound TCP/80 connection immediately after
# bootstrap. The policy exercises HTTPS registry pulls, seed retrieval, and APT
# mirrors. The harness stages the legacy baseline repository over its SSH/SCP
# channel and runs that checkout's ./sb install, so this scenario does not claim
# that every installation transport is HTTPS. Albania's network may DROP instead;
# REJECT is the stricter, faster regression proxy.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HARNESS_HTTPS_ONLY_EGRESS=1
# Unlike the general harness default, run security stage 4 so this scenario
# exercises the hardened box's CrowdSec nftables bouncer + UFW firewall shape.
export HARNESS_HARDENING_SKIP_STAGES=""
exec bash "$SCENARIO_DIR/0-happy-upgrade.sh" "${1:-statbus-recovery-0-https-only-egress}"
