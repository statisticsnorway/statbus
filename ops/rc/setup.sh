#!/usr/bin/env bash
# statbus.org/rc/setup.sh runs the newest release candidate's own setup script
# (setup-ubuntu-lts.sh). niue's Caddy redirects /rc/<name>.sh to this
# directory on master (STATBUS-570), so a pushed change is live at once; the
# code it runs is always the candidate's tagged script.
# statbus.org/setup.sh serves the latest stable instead.
#   curl -fsSL https://statbus.org/rc/setup.sh | bash
# The body is one function called on the last line, so a download cut short
# runs nothing.
ASSET=setup-ubuntu-lts.sh
STABLE=https://statbus.org/setup.sh
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
