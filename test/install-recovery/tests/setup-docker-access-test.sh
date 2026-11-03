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
verify_block=$(line_of 'Verifying core-tools')

present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }
before() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (${2:-missing} vs ${3:-missing})"; fail=1; fi; }

present "the Docker stage grants the service account docker access" "$grant"
present "the Docker stage verifies access as that account, not as root" "$access_verify"
present "the access verification runs as the service account (runuser)" "$runuser"
before  "the grant happens before the stage declares itself verified" "$grant" "$verify_block"

# The account's systemd user manager starts at enable-linger, and keeps the
# groups it started with; the upgrader it starts then hit "permission denied ...
# docker.sock" while runuser (a fresh process) passed (manual box, 2026-11-03).
# So linger is enabled in this stage after the grant, and service-account no
# longer enables it. A manager already running without the group (a box
# prepared by an older setup) is restarted, and the stage verifies the running
# manager has the group.
service_stage="$(awk '/^stage_service_account\(\)/,/^}$/' "$SCRIPT")"
linger=$(line_of 'loginctl enable-linger')
restart_manager=$(line_of 'systemctl restart "user@')
manager_verify=$(line_of 'user_manager_has_docker_group')
present "the Docker stage enables linger for the service account" "$linger"
before  "linger is enabled after the docker grant" "$grant" "$linger"
if grep -q 'loginctl enable-linger' <<<"$service_stage"; then
    echo "FAIL service-account still enables linger before Docker exists"; fail=1
else
    echo "PASS service-account leaves linger to the Docker stage"
fi
present "a manager already running without the group is restarted" "$restart_manager"
present "the stage verifies the user manager itself has the docker group" "$manager_verify"

# The helper reads the manager's real groups: run it against faked /proc data.
helper="$(awk '/^user_manager_has_docker_group\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$helper" ]]; then
    echo "FAIL user_manager_has_docker_group is not defined"; fail=1
else
    work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/proc/4242"
    run_helper() {
        printf 'Groups:\t%s\n' "$1" > "$work/proc/4242/status"
        ( id() { echo 1001; }
          systemctl() { echo 4242; }
          getent() { echo "docker:x:983:statbus"; }
          eval "${helper//\/proc\//$work/proc/}"
          user_manager_has_docker_group statbus )
    }
    if run_helper "1001 983"; then echo "PASS a manager holding the docker group passes"; else echo "FAIL a manager holding the docker group was refused"; fail=1; fi
    if run_helper "1001"; then echo "FAIL a manager without the docker group passed"; fail=1; else echo "PASS a manager without the docker group fails"; fi
fi

exit $fail
