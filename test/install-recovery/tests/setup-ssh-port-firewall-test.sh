#!/usr/bin/env bash
# The firewall must never close the port SSH actually listens on.
#
# Field report (Uganda, 2026-10-14): the local operator had moved sshd to port
# 713 on the server itself. Stage 4 ran `ufw allow OpenSSH` (port 22) then
# `ufw enable` with default-deny incoming, and the operator was locked out.
# Owner ruling (2026-10-15): the script must read the port sshd really listens
# on and allow THAT port, loudly; when it cannot tell, it must refuse rather
# than guess. Never a silent assumption of 22.
#
# This drives the real functions from ops/setup-ubuntu-lts.sh against a fake
# `sshd -T` and a recording `ufw`, so it proves behaviour, not wording.
# Point STATBUS_SETUP_SCRIPT at an older copy to see the red half.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/setup-ssh-port.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# Fake sshd: `sshd -T` prints the effective config; the port list comes from
# FAKE_SSHD_PORTS (space separated). An empty value makes sshd -T fail.
cat > "$work/bin/sshd" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = "-T" ] || exit 0
[ -n "${FAKE_SSHD_PORTS:-}" ] || { echo "sshd: cannot read config" >&2; exit 255; }
for p in $FAKE_SSHD_PORTS; do echo "port $p"; done
echo "permitrootlogin prohibit-password"
FAKE
# Recording ufw: logs every invocation.
cat > "$work/bin/ufw" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UFW_LOG"
FAKE
chmod +x "$work/bin/sshd" "$work/bin/ufw"

if ! grep -q '^ufw_allow_ssh_ports()' "$SCRIPT"; then
    nope "the script defines ufw_allow_ssh_ports (it still hardcodes 'ufw allow OpenSSH')"
    exit 1
fi

run_case() { # label ports -> sets rc and log
    local label=$1
    export FAKE_SSHD_PORTS=$2 UFW_LOG="$work/ufw-$label.log"
    : > "$UFW_LOG"
    out=$(PATH="$work/bin:$PATH" bash -c '
        set -u
        source "$1"
        ufw_allow_ssh_ports
    ' _ "$SCRIPT" 2>&1)
    rc=$?
}

# 1. Uganda: sshd on 713 only. Port 713 must be opened; 22 must not be.
run_case uganda "713"
if [ "$rc" -eq 0 ] && grep -qx 'allow 713/tcp comment SSH' "$UFW_LOG"; then
    pass "sshd on 713: ufw allows 713/tcp"
else
    nope "sshd on 713: expected 'allow 713/tcp comment SSH' (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG") out: $out"
fi
if grep -Eq 'OpenSSH|(^| )22/tcp' "$UFW_LOG"; then
    nope "sshd on 713: port 22 / OpenSSH must not be opened, ufw saw: $(tr '\n' ';' < "$UFW_LOG")"
else
    pass "sshd on 713: port 22 is not opened instead"
fi
if grep -q '713' <<<"$out"; then
    pass "sshd on 713: the port is named to the operator"
else
    nope "sshd on 713: the operator is not told which port was allowed: $out"
fi

# 2. The ordinary box: sshd on 22.
run_case standard "22"
if [ "$rc" -eq 0 ] && grep -qx 'allow 22/tcp comment SSH' "$UFW_LOG"; then
    pass "sshd on 22: ufw allows 22/tcp"
else
    nope "sshd on 22: expected 'allow 22/tcp comment SSH' (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG")"
fi

# 3. Several listening ports: every one stays reachable.
run_case several "22 2222"
if [ "$rc" -eq 0 ] && grep -qx 'allow 22/tcp comment SSH' "$UFW_LOG" && grep -qx 'allow 2222/tcp comment SSH' "$UFW_LOG"; then
    pass "sshd on 22 and 2222: both are allowed"
else
    nope "sshd on 22 and 2222: expected both allowed (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG")"
fi

# 4. Port unknown: refuse, and touch nothing in the firewall.
run_case unknown ""
if [ "$rc" -ne 0 ] && [ ! -s "$UFW_LOG" ]; then
    pass "sshd port unknown: refuses and leaves the firewall untouched"
else
    nope "sshd port unknown: expected a refusal with no ufw calls (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG")"
fi

# 5. The stage itself must use the helper before it enables the firewall, and
#    must not still open OpenSSH/22 by assumption.
stage="$(awk '/^stage_security_tools\(\)/,/^}$/' "$SCRIPT")"
helper_line=$(grep -n 'ufw_allow_ssh_ports' <<<"$stage" | head -1 | cut -d: -f1)
enable_line=$(grep -n 'ufw enable' <<<"$stage" | head -1 | cut -d: -f1)
if [ -n "$helper_line" ] && [ -n "$enable_line" ] && [ "$helper_line" -lt "$enable_line" ]; then
    pass "stage 4 allows the real SSH port(s) before enabling the firewall"
else
    nope "stage 4 must call ufw_allow_ssh_ports before 'ufw enable' (helper=${helper_line:-missing} enable=${enable_line:-missing})"
fi
if grep -q 'ufw allow OpenSSH' <<<"$stage"; then
    nope "stage 4 still opens OpenSSH (port 22) by assumption"
else
    pass "stage 4 no longer assumes OpenSSH/22"
fi

exit $fail
