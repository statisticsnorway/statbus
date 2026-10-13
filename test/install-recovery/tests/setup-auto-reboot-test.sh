#!/usr/bin/env bash
# STATBUS-496: the automatic-updates stage must ENABLE automatic reboots, not
# just name an hour, and the text it prints must match the configuration it
# writes. The original fault was exactly that mismatch: the prompt advertised a
# reboot window while the config set a time without the switch, and
# unattended-upgrades defaults Automatic-Reboot to false, so nothing happened.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail (that copy
# never writes the switch), which is how the red half of the evidence is made.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

# The stage ends at a line that is exactly "}"; a bare /^}/ would stop early at
# the config block's own "};" lines and hide the settings from these assertions.
stage="$(awk '/^stage_auto_updates\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$stage" ]]; then
    echo "FAIL stage_auto_updates is not defined in $SCRIPT"
    exit 1
fi

# 1. The switch must be written, and enabled.
if grep -Eq '^Unattended-Upgrade::Automatic-Reboot "true";' <<<"$stage"; then
    echo "PASS automatic reboots are enabled in the written configuration"
else
    echo "FAIL the written configuration does not enable automatic reboots"; fail=1
fi

# 2. An hour must be written.
configured="$(grep -Eo '^Unattended-Upgrade::Automatic-Reboot-Time "[0-9]{2}:[0-9]{2}";' <<<"$stage" | grep -Eo '[0-9]{2}:[0-9]{2}')"
if [[ -n "$configured" ]]; then
    echo "PASS a reboot hour is configured ($configured)"
else
    echo "FAIL no reboot hour is configured"; fail=1
fi

# 3. The text the operator reads must name the same hour as the config writes.
announced="$(grep -Eo 'Reboot at [0-9]{2}:[0-9]{2}' <<<"$stage" | grep -Eo '[0-9]{2}:[0-9]{2}')"
if [[ -n "$announced" && "$announced" == "$configured" ]]; then
    echo "PASS the stage announces the configured hour ($announced)"
else
    echo "FAIL the stage says '${announced:-nothing}' but configures '${configured:-nothing}'"; fail=1
fi

exit $fail
