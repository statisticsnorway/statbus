#!/bin/bash
# shellcheck disable=SC1091,SC2329 # Dynamic production-helper source and indirect overrides are intentional.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/cloud.sh" "$TMP/cloud.sh"
cp "$ROOT/sb" "$TMP/sb"
mkdir -p "$TMP/ops"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: expected '$1', got '$2'"; }
assert_contains() { grep -Fq -- "$2" <<<"$1" || fail "$3: missing '$2' in: $1"; }
assert_not_contains() { ! grep -Fq -- "$2" <<<"$1" || fail "$3: unexpectedly found '$2' in: $1"; }
assert_words() { assert_eq "$1" "$(tr '\n' ' ' <<<"$2" | xargs)" "$3"; }

BIN="$TMP/bin"
mkdir -p "$BIN"
SSH_LOG="$TMP/ssh.log"
SB_LOG="$TMP/sb.log"
cat >"$BIN/ssh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SSH_LOG"
[ -n "${SSH_FAIL_CODE:-}" ] && [[ "$*" = *"statbus_${SSH_FAIL_CODE}@"* || ( "$SSH_FAIL_CODE" = no && "$*" = *"statbus@rune.statbus.org"* ) ]] && exit 255
if [[ "$*" = *"config show"* ]] && [ -n "${SSH_MALFORMED_CODE:-}" ] && [[ "$*" = *"statbus_${SSH_MALFORMED_CODE}@"* ]]; then
    # A box that answers with exit 0 but not the three-field contract.
    printf '%s\n' "${SSH_MALFORMED_TEXT:-not-delimited}"
    exit 0
fi
if [[ "$*" = *"config show"* ]]; then
    case "$*" in *statbus_dev@*|*statbus@rune*) channel=prerelease ;; *) channel=stable ;; esac
    code=$(sed -n 's/.*statbus_\([^@ ]*\)@.*/\1/p' <<<"$*")
    [ -n "$code" ] || code=no
    printf 'sb version test (commit local)|%s|%s name\n' "$channel" "$code"
fi
exit "${SSH_EXIT:-0}"
STUB
chmod +x "$BIN/ssh"
cat >"$TMP/sb" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SB_LOG"
case "$1 $2" in
  "--version ") echo "sb version test (commit local)" ;;
  "release check") exit 0 ;;
esac
STUB
chmod +x "$TMP/sb"
cat >"$TMP/ops/create-new-statbus-installation.sh" <<'STUB'
#!/bin/bash
printf 'create %s\n' "$1" >>"$OPS_LOG"
STUB
cat >"$TMP/ops/inspect-cloud-installations.sh" <<'STUB'
#!/bin/bash
printf 'inspect\n' >>"$OPS_LOG"
STUB
chmod +x "$TMP/ops/"*.sh
OPS_LOG="$TMP/ops.log"

run_cloud() {
    : >"$SSH_LOG"; : >"$SB_LOG"; : >"$OPS_LOG"
    PATH="$BIN:$PATH" SSH_LOG="$SSH_LOG" SB_LOG="$SB_LOG" OPS_LOG="$OPS_LOG" bash "$TMP/cloud.sh" "$@"
}
run_cloud_closed() { run_cloud "$@" </dev/null; }

# Registry parsing and normal target resolution still use the production helpers.
STATBUS_CLOUD_LIB_ONLY=1 source "$ROOT/cloud.sh"
assert_eq "dev|cloud|statbus_dev@niue.statbus.org|dev.statbus.org" "$(registry_entry dev)" "cloud registry entry"
assert_eq "no|standalone|statbus@rune.statbus.org|no.statbus.org" "$(registry_entry no)" "standalone registry entry"
assert_eq "9" "$(registry_entries_for_group cloud | wc -l | xargs)" "cloud group count"
assert_eq "1" "$(registry_entries_for_group standalone | wc -l | xargs)" "standalone group count"
read_server_metadata() {
    case "$1" in dev|no) printf 'sb version test|prerelease|%s name\n' "$1" ;; *) printf 'sb version test|stable|%s name\n' "$1" ;; esac
}
assert_words "dev demo et jo ma mw ug ua gh no" "$(resolve_target_codes all)" "all target"
assert_words "ma" "$(resolve_target_codes ma)" "code target"
assert_words "demo et jo ma mw ug ua gh" "$(resolve_target_codes stable)" "stable channel"
assert_words "dev no" "$(resolve_target_codes prerelease)" "prerelease channel"
assert_words "dev demo et jo ma mw ug ua gh" "$(resolve_target_codes cloud)" "cloud group"
assert_words "no" "$(resolve_target_codes standalone)" "standalone group"

# Finding 1: tail reaches the real transport with the deployment-user unit suffix.
output=$(run_cloud tail no 2>&1) || fail "tail no should succeed: $output"
assert_contains "$(cat "$SSH_LOG")" "statbus-upgrade@statbus.service" "tail uses standalone unit"
output=$(run_cloud tail dev 2>&1) || fail "tail dev should succeed: $output"
assert_contains "$(cat "$SSH_LOG")" "statbus-upgrade@statbus_dev.service" "tail uses cloud unit"

# Finding 2: a channel target fails closed if even one registry box is unreadable.
read_server_metadata() {
    [ "$1" = no ] && return 255
    printf 'sb version test|prerelease|%s name\n' "$1"
}
set +e
output=$(resolve_target_codes prerelease 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "unreadable channel member must fail the whole resolution"
assert_contains "$output" "no" "channel failure names unreadable box"

# Fail-closed channel resolution must be reached through every executable verb.
assert_channel_dispatch_fails_closed() {
    local verb="$1"; shift
    set +e
    output=$(SSH_FAIL_CODE=no run_cloud "$verb" prerelease "$@" 2>&1); rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "$verb prerelease must fail closed"
    assert_contains "$output" "no" "$verb channel failure names unreadable box"
}
assert_channel_dispatch_fails_closed status
assert_not_contains "$output" "demo " "status prerelease excludes stable row"
assert_channel_dispatch_fails_closed health
assert_channel_dispatch_fails_closed install vX
assert_channel_dispatch_fails_closed upgrade --yes
assert_channel_dispatch_fails_closed notify
assert_channel_dispatch_fails_closed tail

# Luna round 3: metadata that returns exit 0 but not the three-field contract is
# UNREADABLE, not a non-member. Otherwise a MOTD or a shell warning on one box
# silently shrinks every channel-targeted verb to the other boxes.
assert_malformed_metadata_fails_closed() {
    local text="$1" label="$2"
    set +e
    output=$(SSH_MALFORMED_CODE=dev SSH_MALFORMED_TEXT="$text" run_cloud status prerelease 2>&1); rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "status prerelease with malformed dev metadata ($label) must fail closed"
    assert_contains "$output" "dev" "malformed metadata ($label) names the box"
    assert_not_contains "$output" "demo " "malformed metadata ($label) prints no channel row"
}
assert_malformed_metadata_fails_closed 'not-delimited' 'no delimiter'
assert_malformed_metadata_fails_closed 'sb version test|weekly|dev name' 'unknown channel'
assert_malformed_metadata_fails_closed '|prerelease|dev name' 'empty version'
assert_malformed_metadata_fails_closed $'Welcome to dev\nsb version test|prerelease|dev name' 'MOTD before the line'
assert_malformed_metadata_fails_closed $'sb version test|prerelease|dev name\r' 'trailing CR'
assert_malformed_metadata_fails_closed 'sb version test|prerelease|dev name|extra' 'fourth field'
assert_malformed_metadata_fails_closed 'sb version test| prerelease |dev name' 'channel with whitespace'
assert_malformed_metadata_fails_closed '' 'empty stdout with exit 0'
# A human-facing UTF-8 name is valid regardless of the caller's locale.
output=$(LC_ALL=C SSH_MALFORMED_CODE=dev SSH_MALFORMED_TEXT='sb version test (commit local)|prerelease|Norge Ø' run_cloud status prerelease 2>&1) || fail "UTF-8 name must resolve under LC_ALL=C: $output"
assert_contains "$output" "Norge Ø" "UTF-8 name survives the reader under LC_ALL=C"
assert_malformed_metadata_fails_closed $'sb version test|prerelease|dev\tname' 'tab in name'
# ...and a box that is correctly formed is still a member (control).
output=$(SSH_MALFORMED_CODE=dev SSH_MALFORMED_TEXT='sb version test (commit local)|prerelease|dev name' run_cloud status prerelease 2>&1) || fail "well-formed metadata must resolve: $output"
assert_contains "$output" "dev " "well-formed metadata keeps the box on its channel"

# Unqualified status renders all rows, but partial output is still failure.
set +e
output=$(SSH_FAIL_CODE=no run_cloud status 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "status with unreadable box must fail"
assert_contains "$output" "dev " "status shows readable rows"
assert_contains "$output" "no " "status shows unreadable row"
assert_contains "$output" "METADATA READ FAILED" "status marks unreadable row"

# Finding 3: preserve the retired standalone install/upgrade command contract.
output=$(run_cloud install no --version vX 2>&1) || fail "pinned install should succeed: $output"
assert_eq "release check --tag vX" "$(cat "$SB_LOG")" "install --version value reaches release check"
assert_contains "$(cat "$SSH_LOG")" "bash -s -- --version vX" "install --version value reaches transport"

for help_arg in help -h --help; do
    output=$(run_cloud upgrade "$help_arg" 2>&1) || fail "upgrade $help_arg should exit 0"
    assert_contains "$output" "upgrade" "upgrade help text"
    assert_eq "" "$(cat "$SSH_LOG")" "upgrade help must not connect"
done
output=$(run_cloud upgrade --yes 2>&1) || fail "upgrade --yes should be accepted as a flag: $output"
assert_contains "$(cat "$SSH_LOG")" "statbus_dev@niue.statbus.org" "upgrade --yes defaults to all targets"
set +e
output=$(run_cloud upgrade bogus 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "unknown upgrade target must fail"
assert_eq "" "$(cat "$SSH_LOG")" "unknown upgrade target must not connect"
set +e
output=$(run_cloud_closed upgrade no 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "upgrade without confirmation must refuse on closed stdin"
assert_eq "" "$(cat "$SSH_LOG")" "refused upgrade must not connect"
assert_contains "$output" "Aborted" "upgrade confirmation refusal"

# Finding 4: executable `all` behavior for every group-only verb. Interactive
# ssh and fleet-wide inspect refuse; the other four process eligible entries.
test_all_entrypoint() {
    local verb="$1" output rc
    case "$verb" in
        create)
            output=$(run_cloud create all "Test" vX 2>&1); rc=$?
            assert_eq "0" "$rc" "create all exit"
            assert_eq "9" "$(wc -l <"$OPS_LOG" | xargs)" "create all eligible count"
            assert_not_contains "$(cat "$OPS_LOG")" "create no" "create all never runs standalone"
            assert_contains "$output" "no: skipped" "create all skip no"
            ;;
        wipe)
            set +e
            output=$(printf 'dev\ndemo\net\njo\nma\nmw\nug\nua\ngh\n' | run_cloud wipe all 2>&1); rc=$?
            set -e
            assert_eq "0" "$rc" "wipe all exit"
            assert_eq "9" "$(wc -l <"$SSH_LOG" | xargs)" "wipe all eligible count"
            assert_not_contains "$(cat "$SSH_LOG")" "statbus@rune.statbus.org" "wipe all never contacts standalone"
            assert_contains "$output" "no: skipped" "wipe all skip no"
            ;;
        import)
            output=$(run_cloud import all selection test@example.com 2>&1); rc=$?
            assert_eq "0" "$rc" "import all exit"
            assert_contains "$(cat "$SSH_LOG")" "statbus@rune.statbus.org" "import all eligible entry"
            assert_not_contains "$(cat "$SSH_LOG")" "niue.statbus.org" "import all never contacts cloud"
            for code in dev demo et jo ma mw ug ua gh; do assert_contains "$output" "$code: skipped" "import all skip $code"; done
            ;;
        reimport)
            set +e
            output=$(printf 'no\n' | run_cloud reimport all selection test@example.com 2>&1); rc=$?
            set -e
            assert_eq "0" "$rc" "reimport all exit"
            assert_contains "$(cat "$SSH_LOG")" "statbus@rune.statbus.org" "reimport all contacts standalone"
            assert_not_contains "$(cat "$SSH_LOG")" "niue.statbus.org" "reimport all never contacts cloud"
            for code in dev demo et jo ma mw ug ua gh; do assert_contains "$output" "$code: skipped" "reimport all skip $code"; done
            ;;
        inspect|ssh)
            set +e
            output=$(run_cloud "$verb" all 2>&1); rc=$?
            set -e
            [ "$rc" -ne 0 ] || fail "$verb all must refuse"
            assert_contains "$output" "$verb all is not supported" "$verb all refusal"
            assert_eq "" "$(cat "$SSH_LOG")" "$verb all no transport"
            ;;
    esac
}
for verb in create wipe inspect import reimport ssh; do test_all_entrypoint "$verb"; done

set +e
output=$(run_cloud 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "usage without a command must fail"
assert_contains "$output" "accepting 'all': create, wipe, import, reimport" "help lists all-capable group verbs"
assert_contains "$output" "refusing 'all': inspect, ssh" "help lists single-target group verbs"

# Finding 5: retired trust variable fails plainly, and the create helper uses
# the one fleet-wide name.
set +e
retired_trust_name="STANDALONE_TRUST_KEY""_USER"
# shellcheck disable=SC2016 # $1 is intentionally expanded by the inner bash.
output=$(env "$retired_trust_name=jhf" STATBUS_CLOUD_LIB_ONLY=1 bash -c 'source "$1"' _ "$ROOT/cloud.sh" 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "retired trust variable must fail"
assert_contains "$output" "$retired_trust_name" "trust rename names retired variable"
assert_contains "$output" "FLEET_TRUST_KEY_USER" "trust rename names replacement"
assert_not_contains "$(cat "$ROOT/ops/create-new-statbus-installation.sh")" "CLOUD_TRUST_KEY_USER" "create helper has no cloud-only trust variable"
assert_contains "$(cat "$ROOT/ops/create-new-statbus-installation.sh")" "FLEET_TRUST_KEY_USER" "create helper uses fleet trust variable"

# Finding 6: all six mismatches refuse through executable dispatch before SSH.
assert_dispatch_refusal() {
    local verb="$1" target="$2"; shift 2
    set +e
    output=$(run_cloud "$verb" "$target" "$@" 2>&1); rc=$?
    set -e
    assert_eq "2" "$rc" "$verb mismatch exit"
    assert_contains "$output" "only available" "$verb mismatch message"
    assert_eq "" "$(cat "$SSH_LOG")" "$verb mismatch before SSH"
}
assert_dispatch_refusal create no "Name" vX
assert_dispatch_refusal wipe no
assert_dispatch_refusal inspect no
assert_dispatch_refusal import dev selection test@example.com
assert_dispatch_refusal reimport dev selection test@example.com
assert_dispatch_refusal ssh dev

echo "cloud registry tests: PASS"
