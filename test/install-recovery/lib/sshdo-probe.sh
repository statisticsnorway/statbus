#!/bin/bash
# sshdo-probe.sh — STATBUS-170 AC#4: replicate production's CI-poll TRANSPORT on
# an arc VM, so the deploy-status proof polls through the SAME gate class the
# niue slots use: a dedicated ssh key, forced through sshdo, allowlisted to
# exactly one command (the status read).
#
# WHY the key lands on the `statbus` user: on niue, each slot's CI key lands on
# the slot's OWN service-owning user (statbus_<slot> owns ~/statbus), gated by
# the forced command — the key's power is the ALLOWLIST, not the account. The
# arc VM's statbus user is the same shape, so the replica is faithful: the
# ephemeral key can run `~/statbus/ops/ci-deploy-status.sh <40-hex>` and
# nothing else (sshdo refuses anything else with 'not in allowlist' — the proof
# arc probes that refusal explicitly).
#
# WHY ephemeral: the keypair is minted per run by the caller and dies with the
# VM — no standing secret, no custody lifecycle (King-ratified, STATBUS-170
# comment #10).
#
# sshdo + the sshdoers grammar install from the repo's CANONICAL copies
# (ops/niue/sshdo — python3, present on the ubuntu-24.04 VM image) — the same
# reviewable bytes the King provisions root-owned on niue. `match hexdigits`
# makes each '#' in a stored command match one hex digit at runtime, so 40 of
# them match the commit SHA (the niue grammar, ops/niue/sshdoers:7). sshdo
# executes an allowed command via the user's LOGIN SHELL (shell_exec), so `~`
# expands to /home/statbus ON the VM — the same form the niue slot lines use.
#
# STATBUS-021 discipline: the root-side setup script is written LOCALLY with a
# quoted heredoc (never evaluated in transit), scp'd, and executed via
# `ssh root@` with the pubkey delivered on STDIN. Not as an argument: ssh
# flattens its argv into ONE remote command string that the remote shell
# re-splits, so a three-word pubkey line would arrive as $1='ssh-ed25519' with
# the key material dropped (caught in foreman line review, verified against a
# live sshd). stdin is the only channel where no shell touches the payload.
#
# Requires: vm-bootstrap.sh sourced first (VM_IP, SSH_OPTS, HARNESS_ROOT).

# setup_sshdo_probe <pubkey-file>
# Installs on $VM_IP: /usr/local/bin/sshdo (root:root 0755, from ops/niue/sshdo),
# /etc/sshdoers (probe allowlist: the status read only), and the ephemeral
# pubkey on the statbus user under the HARDENED forced-command prefix (the
# STATBUS-069 ruling: command="/usr/local/bin/sshdo" + no-agent-forwarding,
# no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc).
setup_sshdo_probe() {
    local pubkey_file="$1"
    [ -f "$pubkey_file" ] || { echo "setup_sshdo_probe: pubkey file '$pubkey_file' not found" >&2; return 1; }
    local pubkey
    pubkey="$(head -n 1 "$pubkey_file" | tr -d '\r\n')"
    [ -n "$pubkey" ] || { echo "setup_sshdo_probe: pubkey file '$pubkey_file' is empty" >&2; return 1; }

    echo "── installing the sshdo probe transport (production replica) on $VM_IP ──"
    scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/ops/niue/sshdo" root@"$VM_IP":/usr/local/bin/sshdo >/dev/null

    local setup_script
    setup_script=$(mktemp /tmp/sshdo-probe-setup-XXXXXX.sh)
    cat > "$setup_script" <<'SETUP'
#!/bin/bash
# Root-side sshdo probe setup (arc VM). The ephemeral public key line arrives
# on STDIN (never as an argument — ssh's argv flattening would re-split it).
set -euo pipefail
pubkey="$(cat)"
# Fail fast on a truncated/malformed key — a pubkey line is at least
# '<type> <base64>' (the exact truncation class stdin-delivery prevents).
case "$pubkey" in
    ssh-*" "*) : ;;
    *) echo "sshdo-probe setup: malformed or truncated pubkey on stdin: '$pubkey'" >&2; exit 1 ;;
esac

chown root:root /usr/local/bin/sshdo
chmod 0755 /usr/local/bin/sshdo

cat > /etc/sshdoers <<'SSHDOERS'
# arc-VM probe allowlist — STATBUS-170 AC#4 transport replica (ops/niue grammar)
match hexdigits
syslog auth
statbus: ~/statbus/ops/ci-deploy-status.sh ########################################
SSHDOERS
chmod 0644 /etc/sshdoers

install -d -m 700 -o statbus -g statbus /home/statbus/.ssh
printf 'command="/usr/local/bin/sshdo",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc %s\n' "$pubkey" \
    >> /home/statbus/.ssh/authorized_keys
chown statbus:statbus /home/statbus/.ssh/authorized_keys
chmod 600 /home/statbus/.ssh/authorized_keys
echo "sshdo probe installed: /usr/local/bin/sshdo + /etc/sshdoers + forced-command key for statbus"
SETUP

    local remote_path
    remote_path="/tmp/sshdo-probe-setup-$$.sh"
    scp -O "${SSH_OPTS[@]}" "$setup_script" root@"$VM_IP":"$remote_path" >/dev/null
    rm -f "$setup_script"
    # Pubkey on STDIN (bash reads the script from the FILE, so stdin stays free
    # for the payload); the herestring's trailing newline is stripped by the
    # remote $(cat) substitution.
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" bash "$remote_path" <<<"$pubkey"
    echo "  ✓ sshdo + sshdoers + hardened forced-command key installed (probe identity: statbus)"
}
