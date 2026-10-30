#!/usr/bin/env bash
# A plain Ubuntu 26.04 server for testing setup.sh, install.sh and
# uninstall.sh by hand, exactly as an operator would on a fresh machine.
# Nothing is pre-configured: default hostname, root login with the owner's
# key, no StatBus user, no firewall, no DNS name. The point is to prove the
# published scripts work on a default box.
#
#   ops/manual-box.sh up       create the server (or show it if it exists)
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

Log the session so it can be read alongside you:
  tmux new -s $name
  tmux pipe-pane -o -t $name 'cat >> $log'
  ssh root@$ip

Delete when done:  ops/manual-box.sh down
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
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
