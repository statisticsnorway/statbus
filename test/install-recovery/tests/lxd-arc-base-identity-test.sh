#!/usr/bin/env bash
# Offline contract (STATBUS-425 M3b, found live): the two-arg arc form of
# install_statbus_at_sha must pick its install path by COMMIT identity. The
# candidate's own commit takes the per-commit (arc-head-install) path, which
# is what the VM harness does. Only a historical commit takes the released-sb
# (arc-historical-install) path.
#
# The regression: a promoted candidate carries two tags (ebe058af is both
# v2026.09.3-rc.17 and v2026.09.3). `tag --points-at | head -n1` returned the
# stable tag, the name did not equal LXD_CANDIDATE, and the candidate itself
# was installed as the historical release v2026.09.3. Its upgrade row was then
# release_status='release', so runInstallSupersede superseded B's terminal
# 'failed' row in rollback-pair-terminal and restore-broke-reattempt.
#
# Never contacts the LXD host: VM_EXEC, VM_SCRIPT_INLINE and the staging and
# exit helpers are replaced with recorders after sourcing.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
fail() { echo "FAIL: $*" >&2; exit 1; }

# The regression needs a candidate commit with a second (stable) tag. Build it
# in a throwaway repo so the test does not depend on which real tags exist.
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m historical
git -C "$REPO" tag v2026.09.2
HIST=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m candidate
git -C "$REPO" tag v2026.09.3-rc.17
git -C "$REPO" tag v2026.09.3
CAND=$(git -C "$REPO" rev-parse HEAD)
[ "$(git -C "$REPO" tag --points-at "$CAND" | head -n1)" = v2026.09.3 ] ||
    fail "fixture: expected the stable tag to sort first (that is the regression shape)"

export LXD_CANDIDATE=v2026.09.3-rc.17 LXD_FORK_PREFIX=s2
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
export HARNESS_ROOT="$REPO"
mkdir -p "$REPO/tmp"

# VM_SCRIPT_INLINE runs as the left side of `| tee`, i.e. in a subshell, so
# it records to a file rather than to an array.
REC="$REPO/recorded"
VM_EXEC() { return 0; }
VM_SCRIPT_INLINE() { echo "$1|$2" >> "$REC"; cat >/dev/null; }
recorded() { paths=(); [ -f "$REC" ] && while IFS= read -r l; do paths+=("$l"); done < "$REC"; rm -f "$REC"; }
_lxd_stage_candidate_install() { :; }
_lxd_install_exit() { return "$1"; }
_lxd_mark() { :; }

install_statbus_at_sha statbus-arc-x "$CAND"
recorded
[ "${#paths[@]}" -eq 1 ] || fail "candidate: expected 1 install, got ${#paths[*]}"
case "${paths[0]}" in
    arc-head-install\|"$CAND") ;;
    *) fail "candidate commit took '${paths[0]}', expected the per-commit arc-head-install path" ;;
esac
echo 'PASS: the candidate commit installs via its per-commit path even when a stable tag also points at it'

install_statbus_at_sha statbus-arc-x "$HIST"
recorded
[ "${#paths[@]}" -eq 1 ] || fail "historical: expected 1 install, got ${#paths[*]}"
[ "${paths[0]}" = "arc-historical-install|v2026.09.2" ] || fail "historical commit took '${paths[0]}'"
echo 'PASS: a release-tagged historical commit installs via its own released sb'
