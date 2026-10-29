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
# This drives the real functions from ops/setup-ubuntu-lts.sh against fake
# `ss`, `systemctl` and `sshd`, plus a recording `ufw`, so it proves behaviour,
# not wording. Ubuntu 22.10+ socket-activates sshd: `sshd -T` reports
# sshd_config's Port while `ssh.socket`'s ListenStream (visible through `ss`
# as the real listener, or `systemctl show ssh.socket`) decides the actual
# port. The fakes model both sources.
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
# Fake ss: prints FAKE_SS_OUT verbatim (the test supplies `ss -H -ltnp` rows).
cat > "$work/bin/ss" <<'FAKE'
#!/usr/bin/env bash
[ -n "${FAKE_SS_OUT:-}" ] && printf '%s\n' "$FAKE_SS_OUT"
exit 0
FAKE
# Fake systemctl: answers the ssh.socket liveness and Listen queries.
cat > "$work/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
case "${1:-}" in
    is-active)
        [ "${FAKE_SSH_SOCKET_ACTIVE:-0}" = "1" ] && exit 0
        exit 3
        ;;
    show)
        [ "${FAKE_SSH_SOCKET_ACTIVE:-0}" = "1" ] || exit 0
        [ -n "${FAKE_SSH_SOCKET_LISTEN:-}" ] && printf '%s\n' "$FAKE_SSH_SOCKET_LISTEN"
        exit 0
        ;;
esac
exit 0
FAKE
# Recording ufw: logs every invocation.
cat > "$work/bin/ufw" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UFW_LOG"
FAKE
chmod +x "$work/bin/sshd" "$work/bin/ss" "$work/bin/systemctl" "$work/bin/ufw"

if ! grep -q '^ufw_allow_ssh_ports()' "$SCRIPT"; then
    nope "the script defines ufw_allow_ssh_ports (it still hardcodes 'ufw allow OpenSSH')"
    exit 1
fi

fakes_reset() { # no real socket information in this case
    export FAKE_SS_OUT="" FAKE_SSH_SOCKET_ACTIVE=0 FAKE_SSH_SOCKET_LISTEN=""
}

run_ufw() { # label -> runs ufw_allow_ssh_ports, sets rc and out
    local label=$1
    export UFW_LOG="$work/ufw-$label.log"
    : > "$UFW_LOG"
    out=$(PATH="$work/bin:$PATH" bash -c '
        set -u
        source "$1"
        ufw_allow_ssh_ports
    ' _ "$SCRIPT" 2>&1)
    rc=$?
}

run_case() { # label sshd -T ports -> sets rc and log
    fakes_reset
    export FAKE_SSHD_PORTS=$2
    run_ufw "$1"
}

run_ports() { # sets out to ssh_listen_ports output and rc to its status
    out=$(PATH="$work/bin:$PATH" bash -c '
        set -u
        source "$1"
        ssh_listen_ports
    ' _ "$SCRIPT" 2>&1)
    rc=$?
}

# 1. Uganda: sshd on 713 only. Port 713 must be opened; 22 must not be.
run_case uganda "713"
if [ "$rc" -eq 0 ] && [ "$(cat "$UFW_LOG")" = "allow 713/tcp comment SSH" ]; then
    pass "sshd on 713: ufw allows exactly 713/tcp"
else
    nope "sshd on 713: expected only 'allow 713/tcp comment SSH' (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG") out: $out"
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

# 5. Socket-activated, connected: sshd -T says 4713, but the real listener is
#    ssh.socket's 713, visible with sshd and systemd both holding it. Only 713
#    is returned; the firewall may never open 4713.
fakes_reset
export FAKE_SSHD_PORTS=4713
export FAKE_SS_OUT='LISTEN 0 4096 0.0.0.0:713 0.0.0.0:* users:(("sshd",pid=70895,fd=3),("systemd",pid=1,fd=152))
LISTEN 0 4096 [::]:713 [::]:* users:(("sshd",pid=70895,fd=4),("systemd",pid=1,fd=153))'
export UFW_LOG="$work/ufw-socket.log"; : > "$UFW_LOG"
run_ports
if [ "$rc" -eq 0 ] && [ "$out" = "713" ]; then
    pass "socket-activated: ssh_listen_ports returns only the real port 713"
else
    nope "socket-activated: expected exactly '713' (rc=$rc), got: '$out'"
fi
run_ufw socket
if [ "$rc" -eq 0 ] && [ "$(cat "$UFW_LOG")" = "allow 713/tcp comment SSH" ]; then
    pass "socket-activated: ufw allows exactly 713/tcp"
else
    nope "socket-activated: expected only 'allow 713/tcp comment SSH' (rc=$rc), ufw saw: $(tr '\n' ';' < "$UFW_LOG")"
fi

# 6. Socket-activated but idle: no connection yet, so ss shows only systemd
#    holding the socket. ssh.socket's Listen value supplies the port.
fakes_reset
export FAKE_SSHD_PORTS=4713 FAKE_SSH_SOCKET_ACTIVE=1
export FAKE_SSH_SOCKET_LISTEN='[::]:713 (Stream)
0.0.0.0:713 (Stream)'
export FAKE_SS_OUT='LISTEN 0 4096 0.0.0.0:713 0.0.0.0:* users:(("systemd",pid=1,fd=152))
LISTEN 0 4096 [::]:713 [::]:* users:(("systemd",pid=1,fd=153))'
run_ports
if [ "$rc" -eq 0 ] && [ "$out" = "713" ]; then
    pass "socket-activated idle: ssh.socket Listen yields 713"
else
    nope "socket-activated idle: expected exactly '713' (rc=$rc), got: '$out'"
fi

# 7. Classic sshd: the real listener is 22 even though sshd_config says 4713.
fakes_reset
export FAKE_SSHD_PORTS=4713
export FAKE_SS_OUT='LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=900,fd=3))'
run_ports
if [ "$rc" -eq 0 ] && [ "$out" = "22" ]; then
    pass "classic sshd: ssh_listen_ports returns the listening port 22"
else
    nope "classic sshd: expected exactly '22' (rc=$rc), got: '$out'"
fi

# 8. Several real listeners, repeated and out of order: dedupe and sort.
fakes_reset
export FAKE_SS_OUT='LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=900,fd=3))
LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=900,fd=4))
LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=900,fd=5))
LISTEN 0 128 *:713 *:* users:(("sshd",pid=900,fd=6))'
run_ports
expected=$(printf '%s\n' 22 713 2222)
if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
    pass "multiple listeners: ports are deduped and sorted numerically"
else
    nope "multiple listeners: expected '22 713 2222' (rc=$rc), got: '$out'"
fi

# 9. The stage itself must use the helper before it enables the firewall, and
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
