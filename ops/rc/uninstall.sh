#!/usr/bin/env bash
# statbus.org/rc/uninstall.sh runs the newest release candidate's own
# uninstall.sh. niue's Caddy redirects /rc/<name>.sh to this directory on
# master (STATBUS-570), so a pushed change is live at once; the code it runs
# is always the candidate's tagged script.
# statbus.org/uninstall.sh serves the latest stable instead.
#   curl -fsSL https://statbus.org/rc/uninstall.sh | bash
# The body is one function called on the last line, so a download cut short
# runs nothing.
ASSET=uninstall.sh
STABLE=https://statbus.org/uninstall.sh
PIN_VERSION=0

# release_tags prints the tags of StatBus's recent releases, one per line.
# GitHub's release list (the API) can fail for anonymous callers while the
# rest of GitHub works: the rc.14 gate (2026-11-06) got 504 on every call
# for over 20 minutes (STATBUS-582). So the list is asked a bounded number
# of times with a growing pause, then the public releases feed is read
# instead. Returns 1 only when neither answered, so the caller can tell
# "GitHub could not be reached" from "no candidate is published".
RELEASE_LIST_ATTEMPTS="${RELEASE_LIST_ATTEMPTS:-4}"
RELEASE_LIST_RETRY_DELAY_S="${RELEASE_LIST_RETRY_DELAY_S:-5}"
release_tags() {
    local attempt body
    for (( attempt=1; attempt<=RELEASE_LIST_ATTEMPTS; attempt++ )); do
        if body=$(curl -fsSL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=50" 2>/dev/null); then
            printf '%s\n' "$body" | grep '"tag_name"' | cut -d'"' -f4
            return 0
        fi
        [ "$attempt" -lt "$RELEASE_LIST_ATTEMPTS" ] && sleep $(( attempt * RELEASE_LIST_RETRY_DELAY_S ))
    done
    if body=$(curl -fsSL --connect-timeout 10 --max-time 30 "https://github.com/statisticsnorway/statbus/releases.atom" 2>/dev/null); then
        echo "GitHub's release list did not answer; using the releases feed instead." >&2
        printf '%s\n' "$body" | grep -o 'releases/tag/[^"<]*' | sed 's|^releases/tag/||'
        return 0
    fi
    return 1
}

statbus_rc_main() {
    set -euo pipefail
    local tag
    local -a args
    # Newest v*-rc.* tag, ordered by (year, month, patch, rc) exactly as
    # install.sh orders its prerelease channel.
    local tags
    if ! tags=$(release_tags); then
        echo "Could not reach GitHub to find the newest StatBus release candidate. Run the same command again when GitHub answers." >&2
        return 1
    fi
    tag=$(printf '%s\n' "$tags" | grep -E '^v[0-9]{4}\.[0-9]{2}\.[0-9]+-rc\.[0-9]+$' \
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
