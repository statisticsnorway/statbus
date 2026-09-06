#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATBUS_CLOUD_LIB_ONLY=1 source "$ROOT/cloud.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', got '$actual'"
}

assert_words() {
    local expected="$1" actual="$2" label="$3"
    assert_eq "$expected" "$(tr '\n' ' ' <<< "$actual" | xargs)" "$label"
}

# Registry parsing covers both deployment groups and all four fields.
assert_eq "dev|cloud|statbus_dev@niue.statbus.org|dev.statbus.org" "$(registry_entry dev)" "cloud registry entry"
assert_eq "no|standalone|statbus@rune.statbus.org|no.statbus.org" "$(registry_entry no)" "standalone registry entry"
assert_eq "9" "$(registry_entries_for_group cloud | wc -l | xargs)" "cloud group count"
assert_eq "1" "$(registry_entries_for_group standalone | wc -l | xargs)" "standalone group count"

# Channel resolution is live metadata, stubbed here to avoid SSH.
read_server_metadata() {
    case "$1" in
        dev|no) printf 'sb version test|prerelease|%s name\n' "$1" ;;
        *) printf 'sb version test|stable|%s name\n' "$1" ;;
    esac
}

assert_words "dev demo et jo ma mw ug ua gh no" "$(resolve_target_codes all)" "all target"
assert_words "ma" "$(resolve_target_codes ma)" "code target"
assert_words "demo et jo ma mw ug ua gh" "$(resolve_target_codes stable)" "stable channel"
assert_words "dev no" "$(resolve_target_codes prerelease)" "prerelease channel"
assert_words "dev demo et jo ma mw ug ua gh" "$(resolve_target_codes cloud)" "cloud group"
assert_words "no" "$(resolve_target_codes standalone)" "standalone group"

# Every remote operation goes through one helper. Stub it and assert the selected target.
transport_log=""
ssh_transport() {
    transport_log="$1"
}
ssh_entry dev true
assert_eq "statbus_dev@niue.statbus.org" "$transport_log" "cloud transport"
ssh_entry no true
assert_eq "statbus@rune.statbus.org" "$transport_log" "standalone transport"

assert_refusal() {
    local verb="$1" target="$2" expected="$3" output rc
    set +e
    output=$(assert_verb_target_group "$verb" "$target" 2>&1)
    rc=$?
    set -e
    assert_eq "2" "$rc" "$verb refusal exit"
    assert_eq "$expected" "$output" "$verb refusal message"
    assert_eq "1" "$(printf '%s\n' "$output" | wc -l | xargs)" "$verb refusal line count"
}

for verb in create wipe inspect; do
    assert_refusal "$verb" no "Error: $verb is only available for cloud targets; 'no' is standalone."
done
for verb in import reimport ssh; do
    assert_refusal "$verb" dev "Error: $verb is only available for standalone targets; 'dev' is cloud."
done

echo "cloud registry tests: PASS"
