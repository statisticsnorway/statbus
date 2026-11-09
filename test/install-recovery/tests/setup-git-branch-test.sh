#!/usr/bin/env bash
# Exercise base-system's etckeeper setup with real Git in private repositories.
# The package-install and etckeeper transports are isolated from the host /etc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
# shellcheck source=/dev/null
source "$SCRIPT"

# Load the real etckeeper operation without running any other setup stage.
# Older copies expose it inline, so retain an executable RED baseline as well.
if ! declare -F configure_etckeeper >/dev/null; then
    stage="$(awk '/^stage_base_system\(\)/ { active=1 } active && /log "Configuring eternal bash history/ { print "}"; exit } active { print }' "$SCRIPT")"
    eval "$stage"
    configure_etckeeper() { stage_base_system; }
    stage_header() { :; }
    ask_yes_no() { return 0; }
    pushd() { builtin pushd "$CASE_REPO" >/dev/null; }
    popd() { builtin popd >/dev/null; }
fi
log() { :; }
log_error() { echo "$*" >&2; }
apt_retry() { return 0; }
etckeeper() {
    case "$1" in
        init) git init "$CASE_REPO" ;;
        commit) git -C "$CASE_REPO" -c user.name=setup-test -c user.email=setup@example.invalid -c commit.gpgsign=false commit --quiet --allow-empty -m "$2" ;;
        *) return 1 ;;
    esac
}
apt_install() {
    # etckeeper's package post-install hook can initialize Git before the
    # explicit init below. Both paths must inherit the same branch choice.
    [[ "$(git config test.setup-marker)" = preserved ]]
    if [[ "$MODE" = package ]]; then
        git init "$CASE_REPO"
        etckeeper commit "Initial commit before hardening"
    fi
}

for MODE in package explicit; do
    for preference in unset main; do
        CASE_REPO="$SANDBOX/$MODE-$preference"
        mkdir -p "$CASE_REPO"
        : > "$GIT_CONFIG_GLOBAL"
        if [[ "$preference" = main ]]; then
            git config --global init.defaultBranch main
        fi
        cp "$GIT_CONFIG_GLOBAL" "$SANDBOX/before"
        export GIT_CONFIG_PARAMETERS="'test.setup-marker=preserved'"
        configure_etckeeper "$CASE_REPO" >"$SANDBOX/$MODE-$preference.out" 2>"$SANDBOX/$MODE-$preference.err"
        [[ "$(git -C "$CASE_REPO" symbolic-ref HEAD)" = refs/heads/master ]]
        [[ "$(git -C "$CASE_REPO" log -1 --format=%s)" = 'Initial commit before hardening' ]]
        if [[ -s "$SANDBOX/$MODE-$preference.err" ]]; then
            cat "$SANDBOX/$MODE-$preference.err" >&2
            echo "FAIL $MODE init printed diagnostics ($preference preference)" >&2
            exit 1
        fi
        [[ "$GIT_CONFIG_PARAMETERS" = "'test.setup-marker=preserved'" ]]
        [[ "$(git config test.setup-marker)" = preserved ]]
        cmp "$SANDBOX/before" "$GIT_CONFIG_GLOBAL"
        echo "PASS $MODE init uses explicit master, commits cleanly and preserves caller settings ($preference preference)"
    done
done

# A rerun keeps the existing /etc history and branch, even if it uses main.
MODE=existing
CASE_REPO="$SANDBOX/existing"
git -c init.defaultBranch=main init --quiet "$CASE_REPO"
etckeeper commit 'Existing operator history'
before="$(git -C "$CASE_REPO" rev-parse HEAD)"
configure_etckeeper "$CASE_REPO" >"$SANDBOX/existing.out" 2>"$SANDBOX/existing.err"
[[ "$(git -C "$CASE_REPO" symbolic-ref HEAD)" = refs/heads/main ]]
[[ "$(git -C "$CASE_REPO" rev-parse HEAD)" = "$before" ]]
[[ ! -s "$SANDBOX/existing.err" ]]
echo 'PASS rerun preserves the existing branch and commit'
