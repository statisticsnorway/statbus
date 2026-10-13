#!/usr/bin/env bash
# STATBUS-500: the stage that installs Docker must also give the account that will
# RUN StatBus access to the socket, and it must verify that access AS that account.
# Before this, Docker arrived in Stage 5 while the user was added two stages later,
# and the checks (which docker / systemctl is-active / docker compose version) were
# all true for root while an ordinary user was refused — which is precisely how a
# real installation ended up with "permission denied ... docker.sock".
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which is how
# the red half of the evidence is produced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

stage="$(awk '/^stage_core_tools\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$stage" ]]; then
    echo "FAIL stage_core_tools is not defined in $SCRIPT"
    exit 1
fi

line_of() { grep -nE "$1" <<<"$stage" | head -1 | cut -d: -f1; }

grant=$(line_of 'usermod -aG docker')
access_verify=$(line_of 'verify "Docker usable by')
runuser=$(line_of 'runuser -u')
verify_block=$(line_of 'Verifying Stage 5')

present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }
before() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (${2:-missing} vs ${3:-missing})"; fail=1; fi; }

present "the Docker stage grants the service account docker access" "$grant"
present "the Docker stage verifies access as that account, not as root" "$access_verify"
present "the access verification runs as the service account (runuser)" "$runuser"
before  "the grant happens before the stage declares itself verified" "$grant" "$verify_block"

exit $fail
