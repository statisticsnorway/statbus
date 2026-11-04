#!/usr/bin/env bash
# statbus.org/rc/uninstall.sh runs the newest release candidate's own
# uninstall.sh. niue's Caddy serves this file unchanged for every candidate
# (STATBUS-570); its source is ops/niue/rc/ in the StatBus repository.
# statbus.org/uninstall.sh serves the latest stable instead.
#   curl -fsSL https://statbus.org/rc/uninstall.sh | bash
# The body is one function called on the last line, so a download cut short
# runs nothing.
ASSET=uninstall.sh
STABLE=https://statbus.org/uninstall.sh
PIN_VERSION=0

statbus_rc_main() {
    set -euo pipefail
    local tag
    local -a args
    # Newest v*-rc.* tag, ordered by (year, month, patch, rc) exactly as
    # install.sh orders its prerelease channel.
    tag=$(curl -fsSL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=50" \
        | grep '"tag_name"' | cut -d'"' -f4 | grep -E '^v[0-9]{4}\.[0-9]{2}\.[0-9]+-rc\.[0-9]+$' \
        | awk -F'[v.\\-]' '{print $2*1e8 + $3*1e6 + $4*1e4 + $6+0, $0}' \
        | sort -n | tail -1 | awk '{print $2}') || true
    if [ -z "$tag" ]; then
        echo "No StatBus release candidate is published; $STABLE serves the latest stable." >&2
        return 1
    fi
    # Global, not local: the EXIT trap runs after this function has returned.
    script=$(mktemp "${TMPDIR:-/tmp}/statbus-rc.XXXXXX")
    trap 'rm -f "$script"' EXIT
    if ! curl -fsSL "https://github.com/statisticsnorway/statbus/releases/download/$tag/$ASSET" -o "$script"; then
        echo "Cannot download $ASSET from release $tag." >&2
        return 1
    fi
    args=("$@")
    if [ "$PIN_VERSION" = 1 ]; then
        args=(--version "$tag" ${args[@]+"${args[@]}"})
    fi
    # curl | bash leaves stdin on the pipe; the release script reads its
    # answers from the terminal when there is one.
    if (: </dev/tty) 2>/dev/null; then
        bash "$script" ${args[@]+"${args[@]}"} </dev/tty
    else
        bash "$script" ${args[@]+"${args[@]}"}
    fi
}
statbus_rc_main "$@"
