#!/usr/bin/env bash
# STATBUS-539: the firewall bouncer's API key must be proven, not presumed.
#
# Field report (Uganda, statbus.ubos.org, 2026-10-30): Stage 4 found an api_key
# in crowdsec-firewall-bouncer.yaml and left it alone. The key came from an
# earlier install that CrowdSec no longer knew: `cscli bouncers list` was empty,
# the journal said "API error: access forbidden", and the bouncer restarted
# endlessly while banning nothing. Presence of a key in a file is not proof that
# the local API accepts it; registration in `cscli bouncers list` is.
#
# The stage therefore asks the local API. When the bouncer is listed, the key is
# left untouched. When it is not, any stale entry by that name is deleted, a
# fresh key is created and written to the configuration, never printed, and the
# bouncer is restarted so it picks the key up.
#
# This drives the real ensure_bouncer_registered from ops/setup-ubuntu-lts.sh
# against a fake cscli (recording calls and returning a fake key), a recording
# systemctl, and a scratch bouncer configuration. Point STATBUS_SETUP_SCRIPT at
# an older copy (which has no such function) to see the red half.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

if ! grep -q '^ensure_bouncer_registered()' "$SCRIPT"; then
    nope "the script defines ensure_bouncer_registered (the key step is still 'create only when empty')"
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/setup-bouncer-key.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

NEW_KEY="fake-new-bouncer-key-539"

# Fake cscli: records every call. `bouncers list` prints FAKE_BOUNCER_LIST
# (empty means no bouncers); `bouncers add` prints a fake key.
cat > "$work/bin/cscli" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$CSCLI_LOG"
case "\${1:-} \${2:-}" in
    "bouncers list")
        [ -n "\${FAKE_BOUNCER_LIST:-}" ] && printf '%s\n' "\$FAKE_BOUNCER_LIST"
        exit 0
        ;;
    "bouncers delete")
        exit 0
        ;;
    "bouncers add")
        printf '%s\n' "$NEW_KEY"
        exit 0
        ;;
esac
exit 0
FAKE
# Fake systemctl: records restarts.
cat > "$work/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
exit 0
FAKE
chmod +x "$work/bin/cscli" "$work/bin/systemctl"

write_config() { # path api_key_line
    printf '%s\n' \
        'mode: nftables' \
        'api_url: http://127.0.0.1:8080/' \
        "$2" \
        'log_level: info' > "$1"
}

run_key_step() { # label config -> sets rc out
    local label=$1 config=$2
    export CSCLI_LOG="$work/cscli-$label.log" SYSTEMCTL_LOG="$work/systemctl-$label.log"
    : > "$CSCLI_LOG"
    : > "$SYSTEMCTL_LOG"
    out=$(PATH="$work/bin:$PATH" bash -c '
        set -u
        source "$1"
        ensure_bouncer_registered "$2"
    ' _ "$SCRIPT" "$config" 2>&1)
    rc=$?
}

key_line() { grep -E '^api_key:' "$1" 2>/dev/null | tail -1; }

# 1. Stale key: the file has one, but the local API does not know the bouncer.
config="$work/stale.yaml"
write_config "$config" 'api_key: stale-key-from-a-previous-install'
export FAKE_BOUNCER_LIST=""
run_key_step stale "$config"

if [ "$rc" -eq 0 ]; then
    pass "stale key: the key step succeeds"
else
    nope "stale key: expected success (rc=$rc), got: $out"
fi
delete_line=$(grep -n '^bouncers delete statbus-firewall-bouncer$' "$CSCLI_LOG" | head -1 | cut -d: -f1)
add_line=$(grep -n '^bouncers add statbus-firewall-bouncer -o raw$' "$CSCLI_LOG" | head -1 | cut -d: -f1)
if [ -n "$delete_line" ] && [ -n "$add_line" ] && [ "$delete_line" -lt "$add_line" ]; then
    pass "stale key: the stale entry is deleted, then the bouncer is added"
else
    nope "stale key: expected 'bouncers delete' before 'bouncers add' (delete=${delete_line:-missing} add=${add_line:-missing}), cscli saw: $(tr '\n' ';' < "$CSCLI_LOG")"
fi
if [ "$(key_line "$config")" = "api_key: $NEW_KEY" ]; then
    pass "stale key: the new key replaces the stale api_key line"
else
    nope "stale key: expected 'api_key: $NEW_KEY' in the config, got: '$(key_line "$config")'"
fi
if [ "$(grep -c '^api_key:' "$config")" -eq 1 ]; then
    pass "stale key: the configuration keeps exactly one api_key line"
else
    nope "stale key: expected exactly one api_key line, got: $(grep -c '^api_key:' "$config")"
fi
if grep -qF "$NEW_KEY" <<<"$out"; then
    nope "stale key: the key must never be printed, but it appears in the output: $out"
else
    pass "stale key: the key is not printed"
fi
if grep -qx 'restart crowdsec-firewall-bouncer' "$SYSTEMCTL_LOG"; then
    pass "stale key: the bouncer is restarted"
else
    nope "stale key: expected 'restart crowdsec-firewall-bouncer', systemctl saw: $(tr '\n' ';' < "$SYSTEMCTL_LOG")"
fi

# 2. No api_key line at all: the new key is appended, exactly once.
config="$work/missing.yaml"
printf '%s\n' 'mode: nftables' 'api_url: http://127.0.0.1:8080/' > "$config"
export FAKE_BOUNCER_LIST=""
run_key_step missing "$config"

if [ "$rc" -eq 0 ] && [ "$(key_line "$config")" = "api_key: $NEW_KEY" ] && [ "$(grep -c '^api_key:' "$config")" -eq 1 ]; then
    pass "no api_key line: the new key is appended exactly once"
else
    nope "no api_key line: expected one 'api_key: $NEW_KEY' (rc=$rc), got: '$(key_line "$config")'"
fi
if grep -qF "$NEW_KEY" <<<"$out"; then
    nope "no api_key line: the key must never be printed, but it appears in the output: $out"
else
    pass "no api_key line: the key is not printed"
fi

# 3. Registered: the key is left alone and nothing is re-created.
config="$work/registered.yaml"
write_config "$config" 'api_key: good-key-in-use'
export FAKE_BOUNCER_LIST='name	ip_address	valid	last_api_pull	created_at
statbus-firewall-bouncer	127.0.0.1	true	2026-10-30T09:00:00Z	2026-10-30T08:00:00Z'
run_key_step registered "$config"

if [ "$rc" -eq 0 ]; then
    pass "registered: the key step succeeds"
else
    nope "registered: expected success (rc=$rc), got: $out"
fi
if ! grep -q '^bouncers add' "$CSCLI_LOG"; then
    pass "registered: no new key is created"
else
    nope "registered: the registered bouncer must not be re-created, cscli saw: $(tr '\n' ';' < "$CSCLI_LOG")"
fi
if ! grep -q '^bouncers delete' "$CSCLI_LOG"; then
    pass "registered: nothing is deleted"
else
    nope "registered: the registered bouncer must not be deleted, cscli saw: $(tr '\n' ';' < "$CSCLI_LOG")"
fi
if [ "$(key_line "$config")" = 'api_key: good-key-in-use' ]; then
    pass "registered: the existing key is unchanged"
else
    nope "registered: the existing key changed to '$(key_line "$config")'"
fi
if [ ! -s "$SYSTEMCTL_LOG" ]; then
    pass "registered: the bouncer is not restarted for no reason"
else
    nope "registered: expected no systemctl calls, saw: $(tr '\n' ';' < "$SYSTEMCTL_LOG")"
fi
if grep -qF "good-key-in-use" <<<"$out" || grep -qF "$NEW_KEY" <<<"$out"; then
    nope "registered: no key is printed: $out"
else
    pass "registered: no key is printed"
fi

# 4. Stage 4 verifies the bouncer is running, not merely registered.
stage="$(awk '/^stage_security_tools\(\)/,/^}$/' "$SCRIPT")"
if grep -q 'systemctl is-active crowdsec-firewall-bouncer' <<<"$stage"; then
    pass "stage 4 verifies the firewall bouncer is active"
else
    nope "stage 4 does not verify that crowdsec-firewall-bouncer is active"
fi
if grep -q 'ensure_bouncer_registered' <<<"$stage"; then
    pass "stage 4 calls the bouncer key step"
else
    nope "stage 4 does not call ensure_bouncer_registered"
fi

exit $fail
