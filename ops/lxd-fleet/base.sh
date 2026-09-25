#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 && $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || { echo 'Usage: base.sh <release-tag>' >&2; exit 2; }
tag=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
host=${LXD_HOST:-root@$("$ROOT/ops/lxd-fleet/up.sh")}
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
remote() { ssh "${opts[@]}" "$host" "$@"; }
name="fleet-base-${tag//[^a-zA-Z0-9-]/-}"
start=$(date +%s)
# Serialize base creation and reaping with the same host-side lock.
state=$(remote 'flock -n /root/fleet-run.lock bash -s' <<REMOTE
set -euo pipefail
[ ! -e /root/fleet-reaping ] || { echo 'REFUSE: fleet host is being reaped' >&2; exit 1; }
date +%s > /root/last-fleet-activity
if lxc info '$name' 2>/dev/null | grep -Fq '| installed '; then
    echo REUSED
    exit 0
fi
if lxc info '$name' >/dev/null 2>&1; then echo 'REFUSE: incomplete base $name exists' >&2; exit 1; fi
lxc launch ubuntu:24.04 '$name' --config security.nesting=true --config limits.cpu=2 --config limits.memory=6GiB
touch /root/fleet-run.active
REMOTE
)
if [ "$state" = REUSED ]; then printf 'base=%s snapshot=installed reused=true\n' "$name"; exit 0; fi
trap 'remote "rm -f /root/fleet-run.active; date +%s > /root/last-fleet-activity"' EXIT
# Transfer the actual current hardening script. A stopped incomplete base is
# intentionally retained on failure for diagnosis, never silently overwritten.
scp "${opts[@]}" "$ROOT/ops/setup-ubuntu-lts.sh" "$host:/root/fleet-setup.sh"
remote "lxc file push /root/fleet-setup.sh '$name/root/setup.sh'"
remote "lxc exec '$name' -- bash -c 'printf \"ADMIN_EMAIL=test@statbus.org\\nGITHUB_USERS=jhf\\nEXTRA_LOCALES=\\nCADDY_PLUGINS=\\n\" > /root/.setup-ubuntu.env; mkdir -p /run/sshd'"
remote "lxc exec '$name' -- env SKIP_STAGES=4 bash /root/setup.sh --non-interactive" || {
    remote "lxc exec '$name' -- rm -f /etc/apt/sources.list.d/ubuntu.sources.bak"
    remote "lxc exec '$name' -- env SKIP_STAGES='1 3 4 5 6 7 8' bash /root/setup.sh --non-interactive"
}
remote "lxc exec '$name' -- bash -c 'usermod -aG docker statbus; loginctl enable-linger statbus; echo '\''export XDG_RUNTIME_DIR=/run/user/\$(id -u)'\'' >> /home/statbus/.profile'"
# Certificate helper follows provision_harness_certificate in vm-bootstrap.sh.
remote "lxc exec '$name' -- env HARNESS_DOMAIN=statbus-test.local bash -s" <<'CERT'
set -euo pipefail
dir=/home/statbus/harness-certs
install -d -m 0700 -o statbus -g statbus "$dir"
openssl req -x509 -newkey rsa:2048 -nodes -days 7 -sha256 -subj '/CN=StatBus harness CA' -keyout "$dir/ca.key" -out "$dir/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=$HARNESS_DOMAIN" -keyout "$dir/domain.key" -out "$dir/domain.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$HARNESS_DOMAIN" > "$dir/extensions"
openssl x509 -req -in "$dir/domain.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial -days 7 -sha256 -extfile "$dir/extensions" -out "$dir/domain.pem" >/dev/null 2>&1
cat "$dir/domain.pem" "$dir/ca.crt" > "$dir/domain.crt"
chown -R statbus:statbus "$dir"
chmod 0600 "$dir/domain.key" "$dir/ca.key"
printf '127.0.0.1 %s\n' "$HARNESS_DOMAIN" >> /etc/hosts
CERT
remote "lxc exec '$name' -- sudo -i -u statbus bash -lc 'git clone --depth 1 --branch $tag https://github.com/statisticsnorway/statbus.git ~/statbus'"
remote "lxc exec '$name' -- bash -c 'printf \"CADDY_DEPLOYMENT_MODE=standalone\\nSITE_DOMAIN=statbus-test.local\\nDEPLOYMENT_SLOT_NAME=Install Test\\nDEPLOYMENT_SLOT_CODE=test\\nTLS_CERT_FILE=/data/custom-certs/domain.crt\\nTLS_KEY_FILE=/data/custom-certs/domain.key\\n\" > /home/statbus/statbus/.env.config; printf -- \"- email: test@statbus.org\\n  password: test-install-password-2026\\n  role: admin_user\\n  display_name: Admin\\n\" > /home/statbus/statbus/.users.yml; mkdir -p /home/statbus/statbus/caddy/data/custom-certs; cp /home/statbus/harness-certs/domain.crt /home/statbus/harness-certs/domain.key /home/statbus/statbus/caddy/data/custom-certs/; chown -R statbus:statbus /home/statbus/statbus/.env.config /home/statbus/statbus/.users.yml /home/statbus/statbus/caddy/data/custom-certs; chmod 600 /home/statbus/statbus/.env.config'"
remote "lxc exec '$name' -- sudo -i -u statbus bash -lc 'set -o pipefail; curl -fsSL https://statbus.org/install.sh | env STATBUS_INSTALL_VERSION=$tag STATBUS_MIN_DISK_GB=5 bash -s -- --non-interactive --trust-github-user jhf'"
remote "lxc exec '$name' -- curl -kfsS --max-time 20 -o /dev/null https://statbus-test.local/rest/"
remote "lxc exec '$name' -- sudo -i -u statbus bash -lc 'cd ~/statbus && ./sb --version && ./sb ps'"
remote "lxc stop '$name' && lxc snapshot '$name' installed && date +%s > /root/last-fleet-activity"
printf 'base=%s snapshot=installed wall_seconds=%s\n' "$name" "$(($(date +%s)-start))"
