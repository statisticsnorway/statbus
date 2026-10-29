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

# rank_release_baselines_from_tags TARGET
#
# Reads tag names from stdin and prints every released tag strictly below
# TARGET in preference order: stables newest first, then RCs newest first.
# The first line is exactly select_release_baseline_from_tags' choice.
rank_release_baselines_from_tags() {
    local target="$1" tag parts
    _release_tag_parts "$target" >/dev/null || {
        echo "ERROR: target '$target' is not a released stable/RC tag" >&2
        return 1
    }
    while IFS= read -r tag; do
        parts=$(_release_tag_parts "$tag" 2>/dev/null) || continue
        _release_tag_is_before "$tag" "$target" || continue
        printf '%s %s\n' "$parts" "$tag"
    done | sort -k4,4nr -k1,1nr -k2,2nr -k3,3nr -k5,5nr | awk '{print $6}'
}

# select_release_baseline_with_migration_delta_from_repo REPO [TARGET]
#
# The baseline for a scenario whose fault fires inside migrate.up: the
# preferred release (as select_release_baseline_from_repo ranks them) whose
# tree lacks at least one migrations/*.up.sql that the target commit has.
# Upgrading from such a baseline runs the Migrations step for real. A
# candidate that adds no migration over the newest stable (an installer-only
# release) would otherwise give these scenarios nothing to stall in. TARGET
# and the untagged-HEAD bound are resolved exactly as in
# select_release_baseline_from_repo.
select_release_baseline_with_migration_delta_from_repo() {
    local repo="$1" target="${2:-}" tags target_commit exact_targets candidate added
    if [ -n "$target" ]; then
        tags=$(git -C "$repo" tag --list)
        target_commit=$(git -C "$repo" rev-parse --verify --quiet "$target^{commit}") || {
            echo "ERROR: target '$target' is not a tag in $repo" >&2
            return 1
        }
    else
        target_commit=$(git -C "$repo" rev-parse HEAD)
        exact_targets=$(git -C "$repo" tag --points-at HEAD \
            | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
        if [ -n "$exact_targets" ]; then
            target=$(printf '%s\n' "$exact_targets" \
                | select_release_baseline_from_tags v9999.99.999999)
            tags=$(git -C "$repo" tag --list)
        else
            target="v9999.99.999999"
            tags=$(git -C "$repo" tag --merged HEAD)
        fi
    fi

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        # :(top) anchors the pathspec at the repository root. REPO is often a
        # subdirectory (the LXD fleet's shadow tree), where a plain pathspec
        # would be relative to it and match nothing.
        added=$(git -C "$repo" diff --name-only --diff-filter=A "$candidate" "$target_commit" -- ':(top)migrations/*.up.sql' | wc -l | tr -d ' ')
        if [ "$added" -gt 0 ]; then
            echo "  Baseline selection: newest stable below $target (RC fallback) with a migration delta is $candidate ($added migration(s) to apply)" >&2
            printf '%s\n' "$candidate"
            return 0
        fi
        echo "  Baseline selection: $candidate has no migration delta to $target; trying an older release" >&2
    done < <(printf '%s\n' "$tags" | rank_release_baselines_from_tags "$target")
    echo "ERROR: no released stable or RC tag below $target has a migration delta" >&2
    return 1
}
