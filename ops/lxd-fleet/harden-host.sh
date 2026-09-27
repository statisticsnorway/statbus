#!/usr/bin/env bash
# Host-only, noninteractive subset of ops/setup-ubuntu-lts.sh stages 2-4.
# Run from a client with a proven root public-key SSH session. Do not harden
# the disposable guests here: scenario hardening is deliberately independent.
set -euo pipefail
host=${1:?usage: harden-host.sh root@fleet-ip}
opts=(-o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
# The second, independent connection is the safety gate before any auth or
# firewall tightening. A fresh hcloud console remains the break-glass path.
ssh "${opts[@]}" "$host" 'test -s /root/.ssh/authorized_keys && id -u | grep -qx 0' || {
    echo 'REFUSE: root key authentication or authorized_keys not verified' >&2; exit 1;
}
# A fleet can arrive via another runner at any time. The host-side lock covers
# the complete hardening transaction (including all verification connections)
# through an owned marker, and every starter checks the same marker.
ssh "${opts[@]}" "$host" 'flock -n /root/fleet-run.lock bash -c '\''test ! -e /root/fleet-run.active && test ! -e /root/fleet-reaping && test ! -e /root/fleet-hardening.active && guests=$(lxc list --format csv) && ! grep -q RUNNING <<< "$guests" && touch /root/fleet-hardening.active'\''' || {
    echo 'REFUSE: active fleet, running guest, or reaper; defer host hardening' >&2; exit 1;
}
trap 'ssh "${opts[@]}" "$host" "rm -f /root/fleet-hardening.active" || true' EXIT
ssh "${opts[@]}" "$host" 'bash -s' <<'REMOTE'
set -euo pipefail
mkdir -p /etc/ssh/sshd_config.d
config=/etc/ssh/sshd_config.d/00-statbus-lxd-fleet.conf
# An early drop-in wins on Ubuntu's first-value-wins OpenSSH config. Match
# setup-ubuntu-lts.sh stage 2 without changing the unrelated host settings.
cat > "$config.stage" <<'EOF'
# STATBUS-417 LXD host: key-only SSH (setup-ubuntu-lts.sh stage 2).
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
EOF
if ! cmp -s "$config.stage" "$config"; then
    mv "$config.stage" "$config"
else
    rm "$config.stage"
fi
sshd -t
# Verify effective config rather than relying on the mere existence of a file.
effective=$(sshd -T -C user=root,host=localhost,addr=127.0.0.1)
grep -Eq '^permitrootlogin (prohibit-password|without-password)$' <<<"$effective"
grep -qx 'pubkeyauthentication yes' <<<"$effective"
grep -qx 'passwordauthentication no' <<<"$effective"
grep -qx 'kbdinteractiveauthentication no' <<<"$effective"
systemctl reload ssh || systemctl reload sshd
REMOTE
# A genuinely new key-only connection proves SSH still works after reload.
ssh "${opts[@]}" "$host" 'true'
ssh "${opts[@]}" "$host" 'bash -s' <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
missing=()
for package in ufw unattended-upgrades; do
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' || missing+=("$package")
done
if (( ${#missing[@]} )); then
    apt-get update -qq
    apt-get install -y "${missing[@]}" </dev/null >/dev/null
fi
# Stage 3's security-update cadence, without its interactive email/reboot
# policy: these short-lived fleet hosts must not reboot underneath forks.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null
# Same intrusion stack as setup-ubuntu-lts.sh stage 4. The installer only
# adds CrowdSec's apt repository and is skipped on subsequent ramps.
if ! command -v crowdsec >/dev/null 2>&1; then
    curl -fsSL https://install.crowdsec.net | bash
    apt-get update -qq </dev/null
    apt-get install -y crowdsec crowdsec-firewall-bouncer-nftables </dev/null >/dev/null
fi
if ! dpkg-query -W -f='${Status}' crowdsec-firewall-bouncer-nftables 2>/dev/null | grep -qx 'install ok installed'; then
    apt-get install -y crowdsec-firewall-bouncer-nftables </dev/null >/dev/null
fi
cscli collections list -o json </dev/null | grep -q 'crowdsecurity/sshd' || cscli collections install crowdsecurity/sshd </dev/null
systemctl enable --now crowdsec >/dev/null
systemctl is-active --quiet crowdsec
# The package can create a local YAML key without registering the bouncer in
# CrowdSec's API (observed on the live box: "API error: access forbidden").
# An already healthy registration is left untouched on subsequent ramps.
if ! systemctl is-active --quiet crowdsec-firewall-bouncer; then
    cscli bouncers delete statbus-lxd-host </dev/null >/dev/null 2>&1 || true
    bouncer_key=$(cscli bouncers add statbus-lxd-host -o raw </dev/null)
    config=/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
    awk -v key="$bouncer_key" '$1 == "api_key:" {$0 = "api_key: " key; found=1} {print} END {if (!found) exit 1}' "$config" > "$config.stage"
    chmod 600 "$config.stage"
    mv "$config.stage" "$config"
    unset bouncer_key
    systemctl enable --now crowdsec-firewall-bouncer >/dev/null
fi
systemctl is-active --quiet crowdsec-firewall-bouncer
# The host exposes only SSH. Guests need DNS/DHCP to the bridge and outbound
# forwarding/NAT. No public guest ports are opened by this policy.
egress=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
[ -n "$egress" ] && ip link show "$egress" >/dev/null
ip link show lxdbr0 >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw default deny routed >/dev/null
ufw allow 22/tcp comment 'LXD fleet SSH' >/dev/null
ufw allow in on lxdbr0 comment 'LXD guest DHCP DNS' >/dev/null
ufw route allow in on lxdbr0 out on "$egress" comment 'LXD guest outbound NAT' >/dev/null
ufw --force enable >/dev/null
ufw status | grep -q '^Status: active'
ufw status | grep -q '22/tcp'
ufw status | grep -q 'lxdbr0'
REMOTE
# Closing the controlling connection is not a proof. Establish ANOTHER new
# public-key SSH connection after UFW is live and refuse to report success if
# either the SSH path or firewall state is wrong.
ssh "${opts[@]}" "$host" 'ufw status | grep -q "^Status: active" && systemctl is-active --quiet crowdsec && systemctl is-active --quiet crowdsec-firewall-bouncer && systemctl is-active --quiet apt-daily-upgrade.timer'
# Actual guest egress is a boundary check: UFW can appear correct while its
# FORWARD chain blocks LXD NAT. Use a disposable guest and always remove it.
ssh "${opts[@]}" "$host" 'bash -s' <<'REMOTE'
set -euo pipefail
guest=fleet-hardening-egress-check
if lxc info "$guest" >/dev/null 2>&1; then
    echo "REFUSE: reserved egress guest $guest already exists" >&2
    exit 1
fi
trap 'lxc delete "$guest" --force >/dev/null 2>&1 || true' EXIT
lxc launch ubuntu:24.04 "$guest" < /dev/null >/dev/null
for attempt in $(seq 1 30); do
    # </dev/null: lxc exec forwards stdin, and stdin here is the rest of this
    # bash -s script. Without it the failure tail below is swallowed and a
    # failed egress check exits 0.
    if lxc exec "$guest" -- getent ahostsv4 archive.ubuntu.com </dev/null >/dev/null 2>&1 &&
       lxc exec "$guest" -- timeout 8 bash -c 'echo >/dev/tcp/1.1.1.1/80' </dev/null >/dev/null 2>&1; then
        echo 'Guest DNS and outbound TCP verified through LXD bridge'
        exit 0
    fi
    sleep 2
done
echo 'LXD guest DNS or outbound TCP failed after UFW activation' >&2
exit 1
REMOTE
echo 'LXD host security verified: key-only root SSH, deny-by-default UFW, CrowdSec nftables bouncer, unattended security updates'
