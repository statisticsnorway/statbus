#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/cloud.sh" "$TMP/cloud.sh"
cp "$ROOT/sb" "$TMP/sb"

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

run_cloud() {
    : >"$SSH_LOG"; : >"$SB_LOG"
    PATH="$BIN:$PATH" SSH_LOG="$SSH_LOG" SB_LOG="$SB_LOG" bash "$TMP/cloud.sh" "$@"
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

# Finding 4: all processes eligible registry entries and explicitly skips each
# ineligible entry. Import has one eligible standalone entry. Create has nine
# eligible cloud entries. Stub their per-entry operations after real selection.
test_all_eligibility() {
    STATBUS_CLOUD_LIB_ONLY=1 source "$ROOT/cloud.sh"
    local log="$TMP/all-$1.log" output rc
    : >"$log"
    case "$1" in
      import)
        cmd_import_one() { echo "ran:$1" >>"$log"; }
        set +e; output=$(cmd_import all selection test@example.com 2>&1); rc=$?; set -e
        assert_eq "0" "$rc" "import all exit"
        assert_eq "ran:no" "$(cat "$log")" "import all eligible entry"
        for code in dev demo et jo ma mw ug ua gh; do assert_contains "$output" "$code: skipped" "import all skip $code"; done
        ;;
      create)
        cmd_create_one() { echo "ran:$1" >>"$log"; }
        set +e; output=$(cmd_create all "Test" vX 2>&1); rc=$?; set -e
        assert_eq "0" "$rc" "create all exit"
        assert_eq "9" "$(wc -l <"$log" | xargs)" "create all eligible count"
        assert_contains "$output" "no: skipped" "create all skip no"
        ;;
    esac
}
test_all_eligibility import
test_all_eligibility create

# Finding 5: retired trust variable fails plainly, and the create helper uses
# the one fleet-wide name.
set +e
output=$(STANDALONE_TRUST_KEY_USER=jhf STATBUS_CLOUD_LIB_ONLY=1 bash -c 'source "$1"' _ "$ROOT/cloud.sh" 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] || fail "retired trust variable must fail"
assert_contains "$output" "STANDALONE_TRUST_KEY_USER" "trust rename names retired variable"
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
