#!/usr/bin/env bash
# A plain Ubuntu 26.04 server for testing setup.sh, install.sh and
# uninstall.sh by hand, exactly as an operator would on a fresh machine.
# Nothing is pre-configured: default hostname, root login with the owner's
# key, no StatBus user, no firewall, no DNS name. The point is to prove the
# published scripts work on a default box.
#
#   ops/manual-box.sh up       create the server (or show it if it exists)
#   ops/manual-box.sh ssh      log in as root in a logged tmux session
#                              (reattaches if the session is already open)
#   ops/manual-box.sh cert     after setup: hand the box a test certificate the
#                              way an NSO would (a PFX in the statbus home)
#   ops/manual-box.sh rebuild  wipe it back to a blank Ubuntu 26.04 (same IP)
#   ops/manual-box.sh down     delete it (billing stops)
#   ops/manual-box.sh status   show it, with its creation time
#
# Cost: cx33 (4 cores, 8 GB) is about EUR 0.017 per hour, billed hourly.
# Delete it when the session is over.
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

describe() { hcloud server describe "$name" -o json 2>/dev/null || true; }

# A same-name server that is not labelled as ours is someone else's: refuse.
require_ours() {
    local server=$1
    [ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$server")" = manual-box ] \
        || { echo "REFUSE: server '$name' exists but is not labelled $label" >&2; exit 1; }
}

wait_for_ssh() {
    local ip=$1 i
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
    for ((i = 0; i < 90; i++)); do
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "root@$ip" true 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo "SSH did not answer on $ip within 3 minutes" >&2
    exit 1
}

show() {
    local server=$1 ip created
    ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    created=$(jq -r '.created' <<<"$server")
    cat <<EOF
Server:  $name ($type, $image, $location), created $created
Address: $ip

Log in:            ops/manual-box.sh ssh
Session log:       $log
Delete when done:  ops/manual-box.sh down
EOF
}

# One tmux session per box, named after it. Everything the terminal shows is
# appended to the session log so the coordinating agent can read along. The
# session waits briefly before ssh starts so the log captures the login too.
# Leaving ssh ends the session; running `ssh` again opens a new one and keeps
# appending to the same log.
connect() {
    local ip=$1
    mkdir -p "$(dirname "$log")"
    if ! tmux has-session -t "=$name" 2>/dev/null; then
        printf '\n===== %s session start %s =====\n' "$name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"
        tmux new-session -d -s "$name" \
            "sleep 0.5; exec ssh -o StrictHostKeyChecking=accept-new root@$ip"
        # pipe-pane takes a pane target: '=name:' is the exact session's
        # current window and pane ('=name' alone is rejected).
        tmux pipe-pane -o -t "=$name:" "cat >> '$log'"
    fi
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "=$name"
    else
        tmux attach-session -t "=$name"
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
    local ip=$1 domain=$2
    [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Not a host name: $domain" >&2; exit 1; }
    ssh -o BatchMode=yes "root@$ip" "DOMAIN='$domain' PASSWORD='$cert_password' bash -s" <<'REMOTE'
set -euo pipefail
if ! id statbus >/dev/null 2>&1; then
    echo "There is no statbus user yet. Run setup first; the certificate goes into its home." >&2
    exit 1
fi
home=$(getent passwd statbus | cut -d: -f6)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 \
    -subj '/CN=StatBus manual-box test CA' -keyout "$work/ca.key" -out "$work/ca.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=*.${DOMAIN#*.}" \
    -keyout "$work/site.key" -out "$work/site.csr" 2>/dev/null
printf 'subjectAltName=DNS:%s,DNS:*.%s\nextendedKeyUsage=serverAuth\n' "$DOMAIN" "${DOMAIN#*.}" > "$work/ext"
openssl x509 -req -in "$work/site.csr" -CA "$work/ca.crt" -CAkey "$work/ca.key" -CAcreateserial \
    -days 30 -sha256 -extfile "$work/ext" -out "$work/site.crt" 2>/dev/null
dest="$home/Documents/certificate-from-it"
install -d -o statbus -g statbus -m 0755 "$home/Documents" "$dest"
pfx="$dest/wildcard_${DOMAIN#*.}.pfx"
openssl pkcs12 -export -inkey "$work/site.key" -in "$work/site.crt" -certfile "$work/ca.crt" \
    -passout "pass:$PASSWORD" -out "$pfx"
chown statbus:statbus "$pfx"; chmod 0600 "$pfx"
install -m 0644 "$work/ca.crt" /usr/local/share/ca-certificates/statbus-manual-box-test-ca.crt
update-ca-certificates >/dev/null 2>&1
echo "Placed:   $pfx"
echo "Covers:   $DOMAIN and *.${DOMAIN#*.} (valid 30 days)"
echo "Password: $PASSWORD"
echo "Trusted:  the test CA is in this box's trust store"
REMOTE
    cat <<EOF

Use it like an operator:
  setup:   when asked for the server's full name, enter $domain
  install: answer yes to the certificate question, then pick the folder
           ~/Documents/certificate-from-it and give the password above.
EOF
}

case "${1:-}" in
up)
    server=$(describe)
    if [ -z "$server" ]; then
        hcloud server create --name "$name" --type "$type" --image "$image" \
            --location "$location" --ssh-key "$ssh_key" --label "$label" >/dev/null
        server=$(describe)
    fi
    require_ours "$server"
    wait_for_ssh "$(jq -er '.public_net.ipv4.ip' <<<"$server")"
    show "$server"
    ;;
ssh|connect)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    connect "$(jq -er '.public_net.ipv4.ip' <<<"$server")"
    ;;
cert)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    give_certificate "$(jq -er '.public_net.ipv4.ip' <<<"$server")" "${2:-$cert_domain}"
    ;;
rebuild)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; run: ops/manual-box.sh up" >&2; exit 1; }
    require_ours "$server"
    hcloud server rebuild "$name" --image "$image" >/dev/null
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
    echo "Deleted $name ($ip). Billing has stopped."
    ;;
status)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'."; exit 0; }
    require_ours "$server"
    show "$server"
    ;;
*)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
