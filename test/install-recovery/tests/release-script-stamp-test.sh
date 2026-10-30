#!/usr/bin/env bash
# STATBUS-537: the release tag is the only version. install.sh, uninstall.sh and
# ops/setup-ubuntu-lts.sh each carry one STATBUS_RELEASE placeholder line; the
# release workflow stamps the tag there, so every published script's banner
# names the release it belongs to. A copy taken from git keeps the placeholder
# and says "development copy (not a release)". The stamper refuses anything
# that is not a release tag.
#
# The stamper is run for real on scratch copies of the scripts, so the test
# needs no network and touches nothing in the working tree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
STAMPER="$ROOT/ops/release/stamp-release-scripts.sh"
TAG=v2026.10.5
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/release-script-stamp.XXXXXX")"
trap 'rm -rf "$work"' EXIT

has() { # has <name> <expected text> <output>
    if grep -Fq -- "$2" <<<"$3"; then
        pass "$1"
    else
        nope "$1 (missing: $2)"
        printf '%s\n' "$3" | sed 's/^/    /'
    fi
}

# The stamper reads install.sh, uninstall.sh and ops/setup-ubuntu-lts.sh from
# the current directory, exactly as release.yaml runs it from the repo root.
mkdir -p "$work/repo/ops" "$work/dist" "$work/refused"
cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$work/repo/"
cp "$ROOT/ops/setup-ubuntu-lts.sh" "$work/repo/ops/"

if (cd "$work/repo" && bash "$STAMPER" "$TAG" "$work/dist" >"$work/stamp.out" 2>&1); then
    pass "the stamper stamps the three scripts"
else
    nope "the stamper refused a release tag"
    sed 's/^/    /' "$work/stamp.out"
fi
for name in install.sh uninstall.sh setup-ubuntu-lts.sh; do
    if [ -f "$work/dist/$name" ] && [ -x "$work/dist/$name" ]; then
        pass "dist/$name exists and is executable"
    else
        nope "dist/$name exists and is executable"
    fi
done

# setup: --help prints the banner before any root check.
out="$(bash "$work/dist/setup-ubuntu-lts.sh" --help 2>&1)"
if [ "$?" -eq 0 ]; then
    pass "stamped setup --help exits 0"
else
    nope "stamped setup --help exits 0"
fi
has "stamped setup names the release" "StatBus: $TAG" "$out"
if [ ! -f "$work/dist/setup-ubuntu-lts.sh" ] || grep -q 'SCRIPT_VERSION' "$work/dist/setup-ubuntu-lts.sh"; then
    nope "SCRIPT_VERSION is gone from the setup script"
else
    pass "SCRIPT_VERSION is gone from the setup script"
fi

# install: an unknown option makes it exit non-zero after naming itself.
out="$(bash "$work/dist/install.sh" --bogus 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then pass "stamped install refuses an unknown option"; else nope "stamped install refuses an unknown option"; fi
has "stamped install names the release" "StatBus installer $TAG" "$out"

# uninstall: run only the part before DIR=, so no removal code executes.
banner_of() { awk '/^DIR=/{exit} {print}' "$1"; }
out="$(banner_of "$work/dist/uninstall.sh" | bash 2>&1)"
has "stamped uninstaller names the release" "StatBus uninstaller $TAG" "$out"

# The git copies keep the placeholder and say they are not a release.
out="$(bash "$ROOT/ops/setup-ubuntu-lts.sh" --help 2>&1)"
has "git setup says development copy" "development copy (not a release)" "$out"
out="$(bash "$ROOT/install.sh" --bogus 2>&1)"
has "git install says development copy" "development copy (not a release)" "$out"
out="$(banner_of "$ROOT/uninstall.sh" | bash 2>&1)"
has "git uninstaller says development copy" "development copy (not a release)" "$out"

# Anything that is not a release tag is refused before any file is written.
out="$(cd "$work/repo" && bash "$STAMPER" 1.2.3 "$work/refused" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then pass "the stamper refuses a non-release tag"; else nope "the stamper refuses a non-release tag"; fi
has "the refusal names the tag" "Refusing to stamp" "$out"
if [ -z "$(ls -A "$work/refused")" ]; then
    pass "the refusal writes no scripts"
else
    nope "the refusal writes no scripts"
fi

# A script whose placeholder line is not exactly one is refused too.
mkdir -p "$work/bad/repo/ops" "$work/bad/dist"
cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$work/bad/repo/"
cp "$ROOT/ops/setup-ubuntu-lts.sh" "$work/bad/repo/ops/"
printf '\nSTATBUS_RELEASE="@STATBUS_RELEASE@"\n' >> "$work/bad/repo/install.sh"
out="$(cd "$work/bad/repo" && bash "$STAMPER" "$TAG" "$work/bad/dist" 2>&1)"
if [ "$?" -ne 0 ]; then
    pass "the stamper refuses a script with two placeholder lines"
else
    nope "the stamper refuses a script with two placeholder lines"
fi
has "the placeholder refusal names the script" "exactly one" "$out"

if [ "$fail" -eq 0 ]; then
    echo "release script stamp test: PASS"
else
    echo "release script stamp test: FAIL"
    exit 1
fi
