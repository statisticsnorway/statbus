#!/usr/bin/env bash
# A plain Ubuntu 26.04 server for testing setup.sh, install.sh and
# uninstall.sh by hand, exactly as an operator would on a fresh machine.
# It starts the way a stock Ubuntu cloud image does: the operator logs in as
# the sudo user "ubuntu" with their key, and root cannot log in over SSH.
# Nothing else is pre-configured: default hostname, no StatBus user, no
# firewall, no DNS name. The point is to prove the published scripts work on
# a default box, along the path most operators take (ubuntu, then sudo).
#
#   ops/manual-box.sh up       create the server (or show it if it exists)
#   ops/manual-box.sh ssh [user]
#                              log in (as ubuntu by default) in a logged tmux
#                              session; reattaches if that session is open
#   ops/manual-box.sh try-ssh [user]
#                              the "second terminal" login check setup asks
#                              for: logs in as user (statbus by default), runs
#                              id, logs out; no tmux, nothing else changes
#   ops/manual-box.sh cert [pfx|pem|check|remove]
#                              after setup: hand the box a test certificate the
#                              way an NSO would, into ~statbus/Documents/
#                              certificate-from-it: pfx (default) is a
#                              password-protected PFX as Windows exports it;
#                              pem is a fullchain.pem plus privkey.pem pair;
#                              check shows the certificate the site serves now;
#                              remove takes the handed-out files away again, so
#                              an install can start with no certificate to find
#   ops/manual-box.sh guide    print the test walkthrough (setup, certificate,
#                              install, health, uninstall)
#   ops/manual-box.sh rebuild  wipe it back to a blank Ubuntu 26.04 (same IP)
#   ops/manual-box.sh down     delete it (billing stops)
#   ops/manual-box.sh status   (or info) the box: address, live logins, ssh
#                              commands and session log
#
# MANUAL_BOX_SSH_PORT=713 ops/manual-box.sh up (or rebuild) moves sshd to that
# port before anyone logs in, through ssh.socket as on Ubuntu 26.04 boxes in the
# field (Uganda listens on 713), so setup's custom-port path is exercised: its
# firewall stage must open OpenSSH (22) and that port and say so in the summary
# (STATBUS-602). Every command here then reaches the box on that port; set the
# same variable for later commands. Default 22.
#
# Cost: cx33 (4 cores, 8 GB) is about EUR 0.017 per hour, billed hourly.
# Delete it when the session is over.

# The whole script is one block, so bash reads it completely before running:
# an ssh session lasts hours, and editing this file meanwhile (a commit, a
# pull) changes nothing for the running copy. The block ends in exit.
{
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required in .env.credentials}"
export HCLOUD_TOKEN

name=${MANUAL_BOX_NAME:-statbus-manual}
type=cx33
image=ubuntu-26.04
location=hel1
ssh_key='jorgen@veridit.no'
label=statbus-purpose=manual-box
log="$ROOT/tmp/$name-session.log"
ssh_port=${MANUAL_BOX_SSH_PORT:-22}
[[ "$ssh_port" =~ ^[0-9]+$ ]] && [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ] \
    || { echo "MANUAL_BOX_SSH_PORT must be a port number, got: $ssh_port" >&2; exit 1; }
# Every ssh to the box goes through this, so a moved port applies everywhere.
ssh() { command ssh -p "$ssh_port" "$@"; }
# The login user of a stock Ubuntu cloud image. Setup later adds devops and
# statbus; the guide reaches statbus with sudo -iu, as an operator would.
login_user=ubuntu

# ssh forwards LANG and LC_* (the default SendEnv), and a plain Ubuntu box has
# only C.UTF-8 and en_US.UTF-8, so a laptop locale such as nb_NO.UTF-8 makes
# every remote shell warn "cannot change locale". C.UTF-8 exists on every
# Ubuntu box; this script's ssh sessions use it.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
unset LANGUAGE

describe() { hcloud server describe "$name" -o json 2>/dev/null || true; }

# Hetzner's Ubuntu image has only root with the chosen key. This cloud-init
# makes it look like a stock Ubuntu cloud image instead: an "ubuntu" user with
# passwordless sudo and the same key, and no root login over SSH.
stock_ubuntu_user_data() {
    local key
    key=$(hcloud ssh-key describe "$ssh_key" -o json | jq -er '.public_key')
    cat <<EOF
#cloud-config
users:
  - name: $login_user
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - $key
disable_root: true
EOF
    # A moved SSH port: ssh.socket listens on it instead of 22, before the first
    # login, as an operator who moved SSH would have it.
    if [ "$ssh_port" != 22 ]; then
        cat <<EOF
write_files:
  - path: /etc/systemd/system/ssh.socket.d/port.conf
    content: |
      [Socket]
      ListenStream=
      ListenStream=0.0.0.0:$ssh_port
      ListenStream=[::]:$ssh_port
runcmd:
  - [systemctl, daemon-reload]
  - [systemctl, restart, ssh.socket]
EOF
    fi
}

# A same-name server that is not labelled as ours is someone else's: refuse.
require_ours() {
    local server=$1
    [ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$server")" = manual-box ] \
        || { echo "REFUSE: server '$name' exists but is not labelled $label" >&2; exit 1; }
}

wait_for_ssh() {
    local ip=$1 i
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
    ssh-keygen -R "[$ip]:$ssh_port" >/dev/null 2>&1 || true
    for ((i = 0; i < 90; i++)); do
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$login_user@$ip" 'sudo -n true' 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo "SSH as $login_user (with sudo) did not answer on $ip within 3 minutes" >&2
    exit 1
}

show() {
    local server=$1 ip created logins user
    ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    created=$(jq -r '.created' <<<"$server")
    # Which accounts take this key right now (ubuntu always; devops and
    # statbus once setup has created them). A quick BatchMode probe each.
    logins=""
    for user in "$login_user" devops statbus; do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$user@$ip" true 2>/dev/null; then
            logins="${logins:+$logins, }$user"
        fi
    done
    cat <<EOF
Box:          $name, $ip ($type, $image, $location), created $created
Site name:    $cert_domain (not in DNS; the test certificate covers it)
Logins now:   ${logins:-none answer yet}

Log in:       ops/manual-box.sh ssh [user]      (logged tmux session, default $login_user)
Plain ssh:    ssh -p $ssh_port <user>@$ip
Session log:  $log
Walkthrough:  ops/manual-box.sh guide
EOF
}

# The operator walkthrough for a manual test run, so the box carries its own
# instructions. Each step is what a real operator does, plus the checks that
# turn the run into ticket evidence. The site name and certificate details
# are the ones 'cert' produces. The box tests the newest release candidate:
# every command goes through statbus.org/rc/ (STATBUS-570), which runs that
# candidate's own scripts and installs it. The Release line names it, read
# the same way (newest prerelease), so the run's evidence names its version.
guide_text() {
    local release
    release=$(gh release list --limit 20 --exclude-drafts --json tagName,isPrerelease \
        -q '[.[] | select(.isPrerelease)][0].tagName') \
        || { echo "Cannot list releases with gh; run gh auth login." >&2; exit 1; }
    cat <<GUIDE
  Release:           $release (the newest candidate; statbus.org/rc/ runs it)
  1. Log in:         ops/manual-box.sh ssh      (you are $login_user, a sudo user; SSH on port $ssh_port)
  2. Root shell:     sudo -i
  3. Setup:          curl -fsSL https://statbus.org/rc/setup.sh | bash
                     Full name of this server: $cert_domain
                     At "Did that connect?": on your laptop run
                     ops/manual-box.sh try-ssh statbus, then answer y
                     With MANUAL_BOX_SSH_PORT set: the firewall stage says it
                     allows OpenSSH (22) and $ssh_port/tcp, and so does the summary
  4. Certificate:    on your laptop: ops/manual-box.sh cert      (a Windows-style PFX)
                     or: ops/manual-box.sh cert pem          (fullchain.pem + privkey.pem)
  5. Install:        from the root shell: sudo -iu statbus
                     (or log in again directly: ops/manual-box.sh ssh statbus)
                     curl -fsSL https://statbus.org/rc/install.sh | bash
                     Domain: $cert_domain
                     Country name: United Nations, country code: un
                     (a test box serves no real country; un is in the
                     country list, so the installer accepts it without a note)
                     Certificate: yes, pick ~/Documents/certificate-from-it,
                     password $cert_password
  6. Health:         cd ~/statbus && ./sb monitor status; curl -s https://$cert_domain/monitor
  7. Uninstall:      (as statbus) curl -fsSL https://statbus.org/rc/uninstall.sh | bash
                     (keep users, credentials and the database backup: the defaults)
  8. Reinstall:      (as statbus) step 5 again; it ends by naming the newest kept backup and ./sb db restore
  Start over:        ops/manual-box.sh rebuild
GUIDE
}

# One tmux session per box and login user, named after both. Everything the
# terminal shows is appended to the one session log, so the coordinating agent
# can read along. The session waits briefly before ssh starts so the log
# captures the login too. Leaving ssh ends the session; running `ssh` again
# opens a new one and keeps appending to the same log.
connect() {
    local ip=$1 user=$2 session="$name-$2"
    mkdir -p "$(dirname "$log")"
    if ! tmux has-session -t "=$session" 2>/dev/null; then
        printf '\n===== %s session start as %s %s =====\n' "$name" "$user" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"
        tmux new-session -d -s "$session" \
            "sleep 0.5; exec env LANG=C.UTF-8 LC_ALL=C.UTF-8 ssh -p $ssh_port -o StrictHostKeyChecking=accept-new $user@$ip"
        # pipe-pane takes a pane target: '=name:' is the exact session's
        # current window and pane ('=name' alone is rejected).
        tmux pipe-pane -o -t "=$session:" "cat >> '$log'"
    fi
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "=$session"
    else
        tmux attach-session -t "=$session"
    fi
}

# The certificate an NSO hands over, recreated for a box with no public name:
# a password-protected PFX for the site name, signed by a throwaway test CA,
# copied into the operator's home the way someone would scp it there. The CA
# goes into the box's trust store, standing in for the public CA a real
# certificate chains to, so the installer's verified site check can pass.
# Nothing else on the box changes. The password is a fixed test value, not a
# secret: the certificate is for this throwaway box only.
cert_domain=statbus-manual.statbus-test.local
cert_password=manual-box-test
give_certificate() {
    local ip=$1 domain=$2 format=$3
    [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Not a host name: $domain" >&2; exit 1; }
    ssh -o BatchMode=yes "$login_user@$ip" "sudo DOMAIN='$domain' PASSWORD='$cert_password' FORMAT='$format' bash -s" <<'REMOTE'
set -euo pipefail
if ! id statbus >/dev/null 2>&1; then
    echo "There is no statbus user yet. Run setup first; the certificate goes into its home." >&2
    exit 1
fi
home=$(getent passwd statbus | cut -d: -f6)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# One test CA per box, kept under /root, so a PFX and a PEM pair handed out by
# separate runs both chain to the CA in the trust store.
ca_dir=/root/statbus-manual-box-test-ca
if [ ! -s "$ca_dir/ca.key" ]; then
    install -d -m 0700 "$ca_dir"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 \
        -subj '/CN=StatBus manual-box test CA' -keyout "$ca_dir/ca.key" -out "$ca_dir/ca.crt" 2>/dev/null
fi
cp "$ca_dir/ca.key" "$ca_dir/ca.crt" "$work/"
# One site certificate per box too: `cert` and `cert pem` export the same
# certificate in two formats, as an NSO given both files would have it.
if [ ! -s "$ca_dir/site.key" ]; then
    openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=*.${DOMAIN#*.}" \
        -keyout "$ca_dir/site.key" -out "$ca_dir/site.csr" 2>/dev/null
    printf 'subjectAltName=DNS:%s,DNS:*.%s\nextendedKeyUsage=serverAuth\n' "$DOMAIN" "${DOMAIN#*.}" > "$ca_dir/ext"
    openssl x509 -req -in "$ca_dir/site.csr" -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" -CAcreateserial \
        -days 30 -sha256 -extfile "$ca_dir/ext" -out "$ca_dir/site.crt" 2>/dev/null
fi
cp "$ca_dir/site.key" "$ca_dir/site.crt" "$work/"
dest="$home/Documents/certificate-from-it"
install -d -o statbus -g statbus -m 0755 "$home/Documents" "$dest"
if [ "$FORMAT" = pem ]; then
    # The pair most Linux CA tools hand out: the site certificate followed by
    # its chain, and the private key in its own file.
    cat "$work/site.crt" "$work/ca.crt" > "$dest/fullchain.pem"
    install -m 0600 "$work/site.key" "$dest/privkey.pem"
    chown statbus:statbus "$dest/fullchain.pem" "$dest/privkey.pem"; chmod 0644 "$dest/fullchain.pem"
    placed="$dest/fullchain.pem and $dest/privkey.pem"
else
    pfx="$dest/wildcard_${DOMAIN#*.}.pfx"
    openssl pkcs12 -export -inkey "$work/site.key" -in "$work/site.crt" -certfile "$work/ca.crt" \
        -passout "pass:$PASSWORD" -out "$pfx"
    chown statbus:statbus "$pfx"; chmod 0600 "$pfx"
    placed="$pfx"
fi
install -m 0644 "$work/ca.crt" /usr/local/share/ca-certificates/statbus-manual-box-test-ca.crt
update-ca-certificates >/dev/null 2>&1
echo "Placed:   $placed"
echo "Covers:   $DOMAIN and *.${DOMAIN#*.} (valid 30 days)"
[ "$FORMAT" = pem ] || echo "Password: $PASSWORD"
echo "Trusted:  the test CA is in this box's trust store"
REMOTE
    cat <<EOF

Use it like an operator: step 5 of the walkthrough (ops/manual-box.sh guide).
EOF
}

case "${1:-}" in
up)
    server=$(describe)
    if [ -z "$server" ]; then
        hcloud server create --name "$name" --type "$type" --image "$image" \
            --location "$location" --ssh-key "$ssh_key" --label "$label" \
            --user-data-from-file <(stock_ubuntu_user_data) >/dev/null
        server=$(describe)
    fi
    require_ours "$server"
    wait_for_ssh "$(jq -er '.public_net.ipv4.ip' <<<"$server")"
    show "$server"
    ;;
ssh|connect)
    [[ "${2:-$login_user}" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "Not a user name: ${2:-}" >&2; exit 1; }
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    connect "$(jq -er '.public_net.ipv4.ip' <<<"$server")" "${2:-$login_user}"
    ;;
try-ssh)
    # Setup's SSH stage asks the operator to prove a new login works from a
    # second terminal before it disables passwords. This is that login: a
    # fresh ssh as the user, no tmux, so the open walkthrough session is left
    # alone. BatchMode: a key that does not work fails instead of prompting.
    user=${2:-statbus}
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "Not a user name: $user" >&2; exit 1; }
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    echo "ssh -p $ssh_port $user@$ip"
    if ssh -o BatchMode=yes -o ConnectTimeout=10 "$user@$ip" 'echo "Logged in as $(id -un) on $(hostname)"'; then
        echo "That connected: answer y."
    else
        echo "That did not connect: answer n, and fix the access first." >&2
        exit 1
    fi
    ;;
cert)
    format=${2:-pfx}
    case "$format" in
        pfx|pem) ;;
        check|remove) ;;
        *) echo "Usage: ops/manual-box.sh cert [pfx|pem|check|remove]   (pfx is a Windows-style PFX export; pem is fullchain.pem + privkey.pem; check shows what the site serves; remove takes the handed-out files away)" >&2; exit 2 ;;
    esac
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    if [ "$format" = check ]; then
        # Asked on the box itself: the site name is not in DNS, so only the
        # box resolves it (setup put it in /etc/hosts) and trusts the test CA.
        ssh -o BatchMode=yes "$login_user@$(jq -er '.public_net.ipv4.ip' <<<"$server")" "DOMAIN='$cert_domain' bash -s" <<'REMOTE'
cert=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
if [ -z "$cert" ]; then
    echo "https://$DOMAIN serves no certificate (nothing answers on 443, or the TLS handshake fails)."
    exit 1
fi
printf '%s\n' "$cert" | sed -e 's/^subject=/Serves:   /' -e 's/^issuer=/Issuer:   /' -e 's/^notAfter=/Expires:  /'
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/" 2>/dev/null)
echo "HTTPS:    https://$DOMAIN/ answers HTTP ${code:-none} with a trusted certificate"
REMOTE
        exit $?
    fi
    if [ "$format" = remove ]; then
        # Only the folder `cert` hands out. The test CA stays in the trust
        # store and under /root, so a later `cert` gives the same certificate
        # and an installed copy keeps verifying.
        ssh -o BatchMode=yes "$login_user@$(jq -er '.public_net.ipv4.ip' <<<"$server")" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
home=$(getent passwd statbus | cut -d: -f6)
[ -n "$home" ] || { echo "There is no statbus user."; exit 0; }
dest="$home/Documents/certificate-from-it"
if [ -d "$dest" ]; then
    rm -rf -- "$dest"
    echo "Removed:  $dest"
else
    echo "Nothing to remove: $dest does not exist."
fi
REMOTE
        exit $?
    fi
    give_certificate "$(jq -er '.public_net.ipv4.ip' <<<"$server")" "$cert_domain" "$format"
    ;;
guide)
    guide_text
    ;;
rebuild)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    hcloud server rebuild "$name" --image "$image" \
        --user-data-from-file <(stock_ubuntu_user_data) >/dev/null
    wait_for_ssh "$(jq -er '.public_net.ipv4.ip' <<<"$server")"
    show "$server"
    ;;
down)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; nothing to delete."; exit 0; }
    require_ours "$server"
    ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    hcloud server delete "$name" >/dev/null
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
    ssh-keygen -R "[$ip]:$ssh_port" >/dev/null 2>&1 || true
    echo "Deleted $name ($ip). Billing has stopped."
    ;;
status|info)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'."; exit 0; }
    require_ours "$server"
    show "$server"
    ;;
*)
    # The header comment is the help: every line up to the first non-comment.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0" \
        | sed '/^Cost:/,$d'
    exit 2
    ;;
esac
exit
}
