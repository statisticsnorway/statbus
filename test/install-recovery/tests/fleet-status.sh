#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lxd/fleet-status.sh"
file=$(mktemp)
trap 'rm -f "$file"' EXIT
for status in PASSED FAILED SUPERSEDED ERROR; do
    printf 'STATUS=%s\nPHASE=verdict\n' "$status" > "$file"
    fleet_status_read "$file"
    [ "$FLEET_STATUS" = "$status" ] && [ "$FLEET_PHASE" = verdict ] || exit 1
done
# A present failure artifact is red, never neutral.
printf 'STATUS=FAILED\nPHASE=fork-test\n' > "$file"
fleet_status_read "$file"
[ "$FLEET_STATUS" = FAILED ] || exit 1
# The newer tag is metadata, not part of the classification token.
printf 'STATUS=SUPERSEDED\nDETAIL=newer tag v1.2.3-rc.4\n' > "$file"
fleet_status_read "$file"
[ "$FLEET_STATUS" = SUPERSEDED ] && [ "$FLEET_DETAIL" = 'newer tag v1.2.3-rc.4' ] || exit 1
printf 'SUPERSEDED by v1.2.3-rc.4\n' > "$file"
fleet_status_read "$file"
[ "$FLEET_STATUS" = ERROR ] || exit 1
rm "$file"
fleet_status_read "$file"
[ "$FLEET_STATUS" = ERROR ] || exit 1
echo 'fleet status parser: PASS'
