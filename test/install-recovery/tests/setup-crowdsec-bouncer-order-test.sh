#!/usr/bin/env bash
# STATBUS-498: the security stage must install CrowdSec FIRST, wait for its
# configuration, and only then install the firewall bouncer — and it must give
# the bouncer an API key when the package did not, and verify the bouncer is
# both keyed and registered. Otherwise the bouncer runs inert while the stage
# still ticks it green, which is exactly what a real run showed.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail (that copy
# installs both packages in one transaction), which makes the red half.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

stage="$(awk '/^stage_security_tools\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$stage" ]]; then
    echo "FAIL stage_security_tools is not defined in $SCRIPT"
    exit 1
fi

line_of() { grep -nE "$1" <<<"$stage" | head -1 | cut -d: -f1; }

crowdsec_only=$(line_of 'apt_install "crowdsec" crowdsec$')
bouncer=$(line_of 'apt_install "crowdsec firewall bouncer" crowdsec-firewall-bouncer-nftables$')
wait_for_config=$(line_of 'Waiting for the CrowdSec configuration')
# STATBUS-539 moved the key logic into ensure_bouncer_registered; the stage's
# call to it still has to come after the bouncer package is installed.
key=$(line_of 'ensure_bouncer_registered')
api_verify=$(line_of 'Firewall bouncer has an API key')
reg_verify=$(line_of 'Firewall bouncer registered with the local API')

present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }
before() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (${2:-missing} vs ${3:-missing})"; fail=1; fi; }

present "CrowdSec is installed in its own step, not in one transaction with the bouncer" "$crowdsec_only"
present "the firewall bouncer is installed in its own step" "$bouncer"
before  "CrowdSec is installed before the bouncer" "$crowdsec_only" "$bouncer"
before  "the configuration is waited for before the bouncer is installed" "$wait_for_config" "$bouncer"
before  "the bouncer exists before its missing key is created" "$bouncer" "$key"
present "the stage verifies the bouncer has an API key" "$api_verify"
present "the stage verifies the bouncer is registered with the local API" "$reg_verify"

exit $fail
