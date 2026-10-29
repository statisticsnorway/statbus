#!/usr/bin/env bash
# The server must know its own fully qualified name before StatBus is
# installed: `hostname --fqdn` returning a bare label (Uganda: "statbus") is
# not an address anyone can reach. Setup asks for the planned address, applies
# it the Ubuntu way (short host name unchanged when it already matches, and
# one 127.0.1.1 line in /etc/hosts), and refuses an unattended run that has no
# answer rather than guessing. `hostname` and `hostnamectl` are stubbed, and
# HOSTS_FILE points at a temporary file.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

for fn in configure_server_fqdn set_hosts_entry valid_dns_name; do
    if ! grep -q "^${fn}()" "$SCRIPT"; then
        nope "the script defines ${fn}()"
        exit 1
    fi
done

work="$(mktemp -d "${TMPDIR:-/tmp}/setup-fqdn.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export SHORT_FILE="$work/short"
export HOSTS_FILE="$work/hosts"
export HOSTNAMECTL_LOG="$work/hostnamectl.log"

cat > "$work/bin/hostname" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == "--fqdn" ]]; then
    fqdn="$(awk '$1 == "127.0.1.1" { print $2; exit }' "$HOSTS_FILE")"
    if [[ -n "$fqdn" ]]; then echo "$fqdn"; else cat "$SHORT_FILE"; fi
    exit 0
fi
cat "$SHORT_FILE"
FAKE
cat > "$work/bin/hostnamectl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOSTNAMECTL_LOG"
if [[ "${1:-}" == "set-hostname" ]]; then
    printf '%s\n' "$2" > "$SHORT_FILE"
fi
FAKE
chmod +x "$work/bin/hostname" "$work/bin/hostnamectl"

reset_host() { # short -> fresh hosts file and short-name state
    printf '%s\n' "$1" > "$SHORT_FILE"
    cat > "$HOSTS_FILE" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 statbus
HOSTS
    : > "$HOSTNAMECTL_LOG"
}

run_fqdn() { # noninteractive answer stdin -> rc, out
    local noninteractive="$1" answer="$2" input="${3:-}"
    out="$(printf '%s\n' "$input" | HOME="$work" HOSTS_FILE="$HOSTS_FILE" SHORT_FILE="$SHORT_FILE" \
        HOSTNAMECTL_LOG="$HOSTNAMECTL_LOG" NON_INTERACTIVE="$noninteractive" \
        SERVER_FQDN="$answer" PATH="$work/bin:$PATH" bash -c '
            source "$1"
            configure_server_fqdn
        ' _ "$SCRIPT" 2>&1)"
    rc=$?
}

# 1. No-dot FQDN: the first answer is rejected, the next is applied. The short
#    name already matches, so hostnamectl is not called.
reset_host statbus
run_fqdn false "" "not-a-full-name
statbus.ubos.org"
if [[ "$rc" -eq 0 ]] && grep -qx '127.0.1.1 statbus.ubos.org statbus' "$HOSTS_FILE"; then
    pass "no-dot FQDN is replaced with the planned address in /etc/hosts"
else
    nope "no-dot FQDN was not applied (rc=$rc): $(cat "$HOSTS_FILE")"; echo "$out"
fi
if grep -q 'not a plausible DNS name' <<<"$out"; then
    pass "an invalid address is rejected plainly"
else
    nope "an invalid address was not rejected: $out"
fi
if [[ ! -s "$HOSTNAMECTL_LOG" ]]; then
    pass "an unchanged short name does not call hostnamectl"
else
    nope "hostnamectl was called needlessly: $(cat "$HOSTNAMECTL_LOG")"
fi
if [[ "$(grep -c '^127\.0\.1\.1[[:space:]]' "$HOSTS_FILE")" -eq 1 ]]; then
    pass "exactly one 127.0.1.1 line is written"
else
    nope "expected one 127.0.1.1 line: $(cat "$HOSTS_FILE")"
fi

# 2. Rerunning is idempotent: the now-dotted FQDN changes nothing.
before="$(cat "$HOSTS_FILE")"
run_fqdn false "" ""
if [[ "$rc" -eq 0 && "$(cat "$HOSTS_FILE")" == "$before" ]] \
    && [[ "$(grep -c '^127\.0\.1\.1[[:space:]]' "$HOSTS_FILE")" -eq 1 ]] \
    && [[ ! -s "$HOSTNAMECTL_LOG" ]]; then
    pass "a rerun changes nothing and keeps one 127.0.1.1 line"
else
    nope "rerun changed the host state (rc=$rc): $(cat "$HOSTS_FILE")"; echo "$out"
fi
if grep -q 'full name is statbus.ubos.org' <<<"$out"; then
    pass "the existing full name is stated"
else
    nope "the existing full name was not stated: $out"
fi

# 3. An existing dotted FQDN changes nothing at all.
reset_host statbus
cat > "$HOSTS_FILE" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 statbus.ubos.org statbus
# keep this comment
HOSTS
before="$(cat "$HOSTS_FILE")"
run_fqdn false "" ""
if [[ "$rc" -eq 0 && "$(cat "$HOSTS_FILE")" == "$before" && ! -s "$HOSTNAMECTL_LOG" ]]; then
    pass "an existing full name leaves /etc/hosts and the short name untouched"
else
    nope "an existing full name was changed (rc=$rc): $(cat "$HOSTS_FILE")"; echo "$out"
fi

# 4. Unattended and no answer: refuse before changing anything.
reset_host statbus
before="$(cat "$HOSTS_FILE")"
run_fqdn true "" ""
if [[ "$rc" -ne 0 && "$(cat "$HOSTS_FILE")" == "$before" && ! -s "$HOSTNAMECTL_LOG" ]]; then
    pass "non-interactive without SERVER_FQDN refuses before mutation"
else
    nope "non-interactive missing answer mutated the host (rc=$rc): $(cat "$HOSTS_FILE")"; echo "$out"
fi
if grep -q 'SERVER_FQDN' <<<"$out"; then
    pass "the refusal names SERVER_FQDN"
else
    nope "the refusal does not name SERVER_FQDN: $out"
fi

# 5. A different first label sets the short name too.
reset_host statbus
run_fqdn false "" "status.statbus.ubos.org"
if [[ "$rc" -eq 0 ]] && grep -qx 'set-hostname status' "$HOSTNAMECTL_LOG" \
    && [[ "$(cat "$SHORT_FILE")" == "status" ]] \
    && grep -qx '127.0.1.1 status.statbus.ubos.org status' "$HOSTS_FILE"; then
    pass "a new short name is applied with hostnamectl and reflected in /etc/hosts"
else
    nope "a new short name was not applied (rc=$rc): $(cat "$HOSTS_FILE") $(cat "$HOSTNAMECTL_LOG")"; echo "$out"
fi

exit $fail
