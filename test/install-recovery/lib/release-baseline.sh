#!/bin/bash
# Pure release-ledger helpers for the two happy smoke scenarios.
#
# A released tag has exactly one of the two shapes accepted here:
#   stable: vYYYY.MM.PATCH
#   RC:     vYYYY.MM.PATCH-rc.N
# These are the ShapeRelease / ShapePrerelease forms classified by
# cli/internal/upgrade/github.go's ClassifyReleaseShape. Other syntactically
# valid CalVer suffixes are deliberately ignored.

_release_tag_parts() {
    local tag="$1"
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        # Stable sorts after every RC with the same CalVer core.
        printf '%s %s %s 1 0\n' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)-rc\.([0-9]+)$ ]]; then
        printf '%s %s %s 0 %s\n' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}"
        return 0
    fi
    return 1
}

_release_tag_is_before() {
    local candidate target
    candidate=$(_release_tag_parts "$1") || return 1
    target=$(_release_tag_parts "$2") || return 1
    awk -v candidate="$candidate" -v target="$target" '
        BEGIN {
            split(candidate, c)
            split(target, t)
            for (i = 1; i <= 5; i++) {
                if (c[i] < t[i]) exit 0
                if (c[i] > t[i]) exit 1
            }
            exit 1
        }
    '
}

_release_tag_is_newer() {
    _release_tag_is_before "$2" "$1"
}

# select_release_baseline_from_tags TARGET
#
# Reads tag names from stdin and prints the preferred baseline strictly below
# TARGET. Stable releases are a separate preferred class: the newest stable
# wins even when a newer RC is also below TARGET. Only when no stable exists
# does the newest RC win.
select_release_baseline_from_tags() {
    local target="$1" tag best_stable="" best_rc=""
    _release_tag_parts "$target" >/dev/null || {
        echo "ERROR: target '$target' is not a released stable/RC tag" >&2
        return 1
    }

    while IFS= read -r tag; do
        _release_tag_parts "$tag" >/dev/null 2>&1 || continue
        _release_tag_is_before "$tag" "$target" || continue
        if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [ -z "$best_stable" ] || _release_tag_is_newer "$tag" "$best_stable"; then
                best_stable="$tag"
            fi
        elif [ -z "$best_rc" ] || _release_tag_is_newer "$tag" "$best_rc"; then
            best_rc="$tag"
        fi
    done

    if [ -n "$best_stable" ]; then
        printf '%s\n' "$best_stable"
    elif [ -n "$best_rc" ]; then
        printf '%s\n' "$best_rc"
    else
        echo "ERROR: no released stable or RC tag exists below $target" >&2
        return 1
    fi
}

# select_release_baseline_from_repo REPO [TARGET]
#
# TARGET is normally omitted: an exact released tag at HEAD is the target under
# test. For a developer's untagged HEAD, every released tag merged into HEAD is
# older than the target commit, so a synthetic upper bound selects from that
# reachable ledger without accidentally taking a tag from another branch.
select_release_baseline_from_repo() {
    local repo="$1" target="${2:-}" tags baseline exact_targets
    if [ -n "$target" ]; then
        tags=$(git -C "$repo" tag --list)
    else
        exact_targets=$(git -C "$repo" tag --points-at HEAD \
            | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
        if [ -n "$exact_targets" ]; then
            # Multiple release tags may point at one commit. A high synthetic
            # bound selects the newest exact tag using the same numeric order.
            target=$(printf '%s\n' "$exact_targets" \
                | select_release_baseline_from_tags v9999.99.999999)
            tags=$(git -C "$repo" tag --list)
        else
            target="v9999.99.999999"
            tags=$(git -C "$repo" tag --merged HEAD)
        fi
    fi

    baseline=$(printf '%s\n' "$tags" | select_release_baseline_from_tags "$target") || return 1
    if [ "$target" = "v9999.99.999999" ]; then
        echo "  Baseline selection: untagged HEAD; newest merged stable (RC fallback) is $baseline" >&2
    else
        echo "  Baseline selection: newest stable below $target (RC fallback) is $baseline" >&2
    fi
    printf '%s\n' "$baseline"
}
