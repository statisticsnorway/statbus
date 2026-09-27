#!/usr/bin/env bash
# STATBUS-417 scenario backend. Source via the runner's shadow vm-bootstrap.sh.
set -euo pipefail
LXD_HOST=${LXD_HOST:-root@65.108.241.95}
LXD_CANDIDATE=${LXD_CANDIDATE:-v2026.09.3-rc.05}
HARNESS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HARNESS_ROOT=$(git -C "$HARNESS_LIB_DIR" rev-parse --show-toplevel)
LXD_LOG_DIR=${LXD_LOG_DIR:-$HARNESS_ROOT/tmp}
mkdir -p "$LXD_LOG_DIR"
LXD_SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=30)
# shellcheck disable=SC2034 # Sourced assertions consume this variable.
# Nonempty because bash 3.2 with nounset treats an empty array expansion as unbound.
SSH_OPTS=(-o BatchMode=yes)
_lxd_host() { local q; printf -v q '%q ' "$@"; LC_ALL=C command ssh "${LXD_SSH_OPTS[@]}" "$LXD_HOST" "$q"; }
_lxd_name() { printf 's2-base-%s' "${1//[^a-zA-Z0-9-]/-}"; }
_lxd_mark() { printf '%s | %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
_lxd_prune_other_bases() {
    local tag=$1 safe=${1//[^a-zA-Z0-9-]/-}
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || return 2
    # CI/driver acquired the occupancy marker before entering here. The flock
    # serializes this destructive catalog maintenance with reaper and ramp-up.
    _lxd_host flock /root/fleet-run.lock bash -c '
set -euo pipefail
test -e /root/fleet-run.active && test ! -e /root/fleet-reaping && test ! -e /root/fleet-hardening.active
names=$(lxc list -c n --format csv)
while IFS= read -r name; do
    case "$name" in
        "fleet-base-$1"|"s2-base-$1-"*) continue ;;
        fleet-base-v*|s2-base-v*) echo "prune superseded base $name"; lxc delete "$name" --force ;;
    esac
done <<< "$names"
' _ "$safe"
}
_lxd_upload() { command scp -q "${LXD_SSH_OPTS[@]}" "$1" "$LXD_HOST:$2"; }
# Existing assertion/wedge helpers invoke ssh/scp directly rather than VM_EXEC.
# Route only this fork's guest IP; refuse any unrelated destination.
ssh() {
    local host='' option
    while [ "$#" -gt 0 ]; do
        option=$1; shift
        case "$option" in
            -o|-i|-p|-F) shift ;;
            -*) ;;
            *@*) host=$option; break ;;
            *) echo "Unexpected SSH argument: $option" >&2; return 2 ;;
        esac
    done
    [ "${host#*@}" = "${VM_IP:-UNSET}" ] || { echo "REFUSE: guest SSH destination $host does not match fork IP" >&2; return 2; }
    case "$host" in
        root@*) _lxd_host lxc exec "$VM_NAME" -- bash -lc "$*" ;;
        statbus@*) _lxd_host lxc exec "$VM_NAME" -- sudo -u statbus -H env XDG_RUNTIME_DIR=/run/user/1001 bash -c "$*" ;;
        *) return 2 ;;
    esac
}
scp() {
    local source='' destination='' arg staging
    while [ "$#" -gt 0 ]; do
        arg=$1; shift
        case "$arg" in
            -o|-i|-P|-F) shift ;;
            -*) ;;
            *) if [ -z "$source" ]; then source=$arg; else destination=$arg; fi ;;
        esac
    done
    [[ "$destination" == "root@${VM_IP:-UNSET}:"/* ]] || { echo "REFUSE: guest SCP destination $destination" >&2; return 2; }
    staging="/root/s2-transfer-$$"
    _lxd_upload "$source" "$staging"
    _lxd_host lxc file push "$staging" "$VM_NAME${destination#*:}"
}
_wait_for_ssh() {
    local ip=$1 max=${2:-90} i
    [ "$ip" = "${VM_IP:-}" ] || { echo "REFUSE: readiness probe outside fork IP $ip" >&2; return 2; }
    for ((i=1;i<=max;i++)); do
        if _lxd_host lxc exec "$VM_NAME" -- true >/dev/null 2>&1; then
            echo "  fork exec ready after ${i}s"
            return 0
        fi
        sleep 1
    done
    echo "  fork exec not ready within ${max}s" >&2
    return 1
}
_lxd_guest_ip() {
    # The LXD bridge address is the guest's eth0 (the default profile's nic).
    # Never match a subnet: lxdbr0's ipv4.address=auto picks a random /24 per
    # host (10.111.x on the prototype, 10.45.131.x on the 26.04 box), and the
    # guest's Docker bridges (172.17/172.18) are also listed by hostname -I.
    _lxd_host lxc exec "$1" -- ip -4 -o addr show dev eth0 scope global | awk '{split($4, a, "/"); print a[1]; exit}'
}
_lxd_ready() {
    local name=$1 ip i code
    for ((i=0;i<90;i++)); do
        ip=$(_lxd_guest_ip "$name" 2>/dev/null || true)
        if [ -n "$ip" ]; then
            code=$(_lxd_host lxc exec "$name" -- curl -ksS -m 3 -o /dev/null -w '%{http_code}' --resolve statbus-test.local:443:127.0.0.1 'https://statbus-test.local/rest/' 2>/dev/null || true)
            if [ "$code" = 200 ]; then
                # shellcheck disable=SC2034 # Sourced scenario and assertions consume VM_IP.
                VM_IP=$ip
                _lxd_mark "$name ready /rest/ 200 after ${i}s ($ip)"
                return 0
            fi
        fi
        sleep 1
    done
    _lxd_mark "$name readiness FAILED after 90s"; return 1
}
# The script, not its filename, declares its initial state. A fresh installer
# requires an absent checkout. Historical upgrade arcs select the baseline tag.
lxd_checkpoint_for_scenario() {
    local slug=$1 file="$HARNESS_ROOT/test/install-recovery/scenarios/$1.sh" baseline delegated
    [ -f "$file" ] || { echo "Unknown scenario $slug" >&2; return 2; }
    # Delegators execute another scenario without changing the VM name. Select
    # the checkpoint that the executed script actually bootstraps from.
    delegated=$(sed -nE 's@^[[:space:]]*exec (bash )?"\$\(dirname "\$0"\)/([a-zA-Z0-9-]+)\.sh".*@\2@p' "$file" | head -n 1)
    if [ -n "$delegated" ]; then
        [ "$delegated" != "$slug" ] || { echo "Self-delegating scenario $slug" >&2; return 2; }
        lxd_checkpoint_for_scenario "$delegated"
        return
    fi
    case "$slug" in
        0-happy-install|0-interactive-admin-password|4-install-*|5-install-interrupted-*|5-install-live-upgrade-wait|6-uninstall-reinstall)
            printf 'hardened-nothing-installed'; return ;;
    esac
    if grep -Eq 'bootstrap_install_test_vm "\$VM_NAME" ""' "$file"; then
        printf 'hardened-nothing-installed'; return
    fi
    if grep -Eq 'INSTALL_VERSION="\$\{INSTALL_VERSION:-\}"' "$file"; then
        printf 'hardened-nothing-installed'; return
    fi
    if grep -Eq 'select_release_baseline_from_repo|select_release_baseline_from_tags' "$file"; then
        # Same selector as the scenario, relative to the candidate tag.
        source "$HARNESS_ROOT/test/install-recovery/lib/release-baseline.sh"
        baseline=$(select_release_baseline_from_repo "$HARNESS_ROOT" "$LXD_CANDIDATE") || return
        printf 'installed-%s-standalone' "$baseline"
    else
        printf 'installed-%s-standalone' "$LXD_CANDIDATE"
    fi
}
lxd_certificates() {
    local name=$1
    _lxd_host lxc exec "$name" -- bash -c 'set -e; d=/home/statbus/harness-certs; install -d -m 0700 -o statbus -g statbus "$d"; openssl req -x509 -newkey rsa:2048 -nodes -days 7 -sha256 -subj "/CN=StatBus harness CA" -keyout "$d/ca.key" -out "$d/ca.crt" >/dev/null 2>&1; openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=statbus-test.local" -keyout "$d/domain.key" -out "$d/domain.csr" >/dev/null 2>&1; printf "subjectAltName=DNS:statbus-test.local\nextendedKeyUsage=serverAuth\n" > "$d/extensions"; openssl x509 -req -in "$d/domain.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial -days 7 -sha256 -extfile "$d/extensions" -out "$d/domain.pem" >/dev/null 2>&1; cat "$d/domain.pem" "$d/ca.crt" > "$d/domain.crt"; chown -R statbus:statbus "$d"; chmod 0600 "$d/domain.key" "$d/ca.key"; printf "127.0.0.1 statbus-test.local\n" >> /etc/hosts'
}
_lxd_prepare_fresh_answers() {
    local mode=${HARNESS_DEPLOYMENT_MODE:-standalone} channel=${HARNESS_UPGRADE_CHANNEL:-stable}
    local domain=${HARNESS_SITE_DOMAIN:-statbus-test.local} fixture
    case "$mode" in development|private|standalone) ;; *) echo "Invalid deployment mode: $mode" >&2; return 2 ;; esac
    case "$channel" in stable|prerelease) ;; *) echo "Invalid upgrade channel: $channel" >&2; return 2 ;; esac
    [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 2
    fixture=$(mktemp "$LXD_LOG_DIR/s2-env-XXXXXX")
    cat > "$fixture" <<CONFIG
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=$mode
SITE_DOMAIN=$domain
STATBUS_URL=https://$domain
BROWSER_REST_URL=https://$domain
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
UPGRADE_CHANNEL=$channel
CONFIG
    if [ "$mode" = standalone ] && [ "${HARNESS_NO_CUSTOM_CERT:-0}" != 1 ]; then
        printf 'TLS_CERT_FILE=/data/custom-certs/domain.crt\nTLS_KEY_FILE=/data/custom-certs/domain.key\n' >> "$fixture"
    fi
    _lxd_upload "$fixture" /root/s2-env-config
    _lxd_host lxc file push /root/s2-env-config "$VM_NAME/tmp/env-config"
    _lxd_host lxc exec "$VM_NAME" -- chown statbus:statbus /tmp/env-config
    _lxd_host lxc exec "$VM_NAME" -- chmod 0600 /tmp/env-config
    rm -f "$fixture"
    fixture=$(mktemp "$LXD_LOG_DIR/s2-users-XXXXXX")
    printf '%s\n' '- email: test@statbus.org' '  password: test-install-password-2026' '  role: admin_user' '  display_name: Admin' > "$fixture"
    _lxd_upload "$fixture" /root/s2-users.yml
    _lxd_host lxc file push /root/s2-users.yml "$VM_NAME/tmp/users.yml"
    _lxd_host lxc exec "$VM_NAME" -- chmod 0644 /tmp/users.yml
    rm -f "$fixture"
}
_lxd_build_base_for_candidate() {
    local tag=$1 checkpoint=${2:-installed-$1-standalone} base start fixture
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || { echo "Invalid candidate tag: $tag" >&2; return 2; }
    base=$(_lxd_name "$tag-$checkpoint")
    if _lxd_host lxc info "$base" 2>/dev/null | grep -qE '^\| checkpoint +\|'; then
        _lxd_mark "$base/checkpoint exists, reusing candidate catalog entry"; return 0
    fi
    if _lxd_host lxc info "$base" >/dev/null 2>&1; then
        echo "REFUSE: unsnapshotted base $base exists. Inspect or delete explicitly before retry." >&2; return 1
    fi
    start=$(date +%s)
    _lxd_mark "launch $base ubuntu:24.04 nesting=true cpu=2 memory=6GiB"
    _lxd_host lxc launch ubuntu:24.04 "$base" --config security.nesting=true --config limits.cpu=2 --config limits.memory=6GiB || return
    LXD_BASE_OWNED_BY_THIS_BUILD=1
    _lxd_upload "$HARNESS_ROOT/ops/setup-ubuntu-lts.sh" /root/s2-setup.sh || return
    _lxd_host lxc file push /root/s2-setup.sh "$base/root/setup.sh" || return
    _lxd_host lxc exec "$base" -- bash -c 'printf "ADMIN_EMAIL=test@statbus.org\nGITHUB_USERS=jhf\nEXTRA_LOCALES=\nCADDY_PLUGINS=\n" > /root/.setup-ubuntu.env; mkdir -p /run/sshd' || return
    _lxd_mark "hardening start $base (SKIP_STAGES=4 as VM harness)"
    _lxd_host lxc exec "$base" -- env SKIP_STAGES=4 bash /root/setup.sh --non-interactive || {
        # The prototype's Stage 0 verifier mistakenly inspected its own backup.
        # Retry only failed setup stages, never suppress an unexplained error.
        _lxd_host lxc exec "$base" -- bash -c 'rm -f /etc/apt/sources.list.d/ubuntu.sources.bak; mkdir -p /run/sshd' || return
        _lxd_host lxc exec "$base" -- env SKIP_STAGES='1 3 4 5 6 7 8' bash /root/setup.sh --non-interactive || return
    }
    _lxd_host lxc exec "$base" -- bash -c 'usermod -aG docker statbus; loginctl enable-linger statbus; echo "export XDG_RUNTIME_DIR=/run/user/1001" >> /home/statbus/.profile; systemctl is-active docker' || return
    _lxd_host lxc exec "$base" -- apt-get update -qq || return
    lxd_certificates "$base" || return
    _lxd_mark "hardening complete $base in $(($(date +%s)-start))s"
    if [ "$checkpoint" = hardened-nothing-installed ]; then
        _lxd_host lxc exec "$base" -- test ! -e /home/statbus/statbus || return
        _lxd_host lxc stop "$base" || return
        _lxd_host lxc snapshot "$base" checkpoint || return
        return 0
    fi
    local install_tag=${checkpoint#installed-}
    install_tag=${install_tag%-standalone}
    [[ "$install_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "Invalid checkpoint $checkpoint" >&2; return 2; }
    fixture=$(mktemp "$LXD_LOG_DIR/s2-users-XXXXXX")
    printf '%s\n' '- email: test@statbus.org' '  password: test-install-password-2026' '  role: admin_user' '  display_name: Admin' > "$fixture"
    _lxd_upload "$fixture" /root/s2-users.yml || return
    rm -f "$fixture"
    _lxd_host lxc file push /root/s2-users.yml "$base/home/statbus/users.yml"
    _lxd_host lxc exec "$base" -- chown statbus:statbus /home/statbus/users.yml
    _lxd_host lxc exec "$base" -- bash -c 'printf "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus-test.local\nTLS_CERT_FILE=/data/custom-certs/domain.crt\nTLS_KEY_FILE=/data/custom-certs/domain.key\nDEPLOYMENT_SLOT_NAME=Install Test\nDEPLOYMENT_SLOT_CODE=test\nTRUST_GITHUB_USER=jhf\n" > /home/statbus/install-input.env; chown statbus:statbus /home/statbus/install-input.env; chmod 600 /home/statbus/install-input.env'
    start=$(date +%s)
    _lxd_mark "REAL tagged installer start $tag $base"
    local installer_url=https://statbus.org/install.sh
    local staging=STATBUS_HARNESS_CERT_STAGING=/home/statbus/harness-certs
    if [ "$install_tag" != "$tag" ]; then
        # A historical baseline is installed the way vm-bootstrap.sh's
        # install_statbus_at_sha release-tag path installs it: that release's
        # own sb-linux asset, a checkout at its tag, pre-placed .env.config /
        # .users.yml / certificates, then its own ./sb install. Feeding it the
        # CURRENT installer's answer file is not what history did: v2026.09.2
        # refuses TLS keys there ("STATBUS_ENV_CONFIG: extra key
        # TLS_CERT_FILE"), which failed this checkpoint at rc.08 and rc.09.
        _lxd_mark "historical target $install_tag via its own released sb (VM harness baseline path)"
        local script
        script=$(mktemp "$LXD_LOG_DIR/s2-baseline-XXXXXX")
        cat > "$script" <<SCRIPT
set -euo pipefail
for attempt in 1 2 3 4 5 6 7 8; do
    if curl -fsSL https://github.com/statisticsnorway/statbus/releases/download/$install_tag/sb-linux-amd64 -o ~/sb.tmp; then break; fi
    echo "GitHub sb-linux download retry \$attempt/8" >&2
    [ "\$attempt" -eq 8 ] && exit 1
    rm -f ~/sb.tmp; sleep 45
done
chmod +x ~/sb.tmp
for attempt in 1 2 3 4 5 6 7 8; do
    if git clone --quiet --depth 50 --branch $install_tag https://github.com/statisticsnorway/statbus.git ~/statbus; then break; fi
    echo "GitHub clone retry \$attempt/8" >&2
    [ "\$attempt" -eq 8 ] && exit 1
    rm -rf ~/statbus; sleep 45
done
mv ~/sb.tmp ~/statbus/sb
cd ~/statbus
install -d -m 0755 caddy/data/custom-certs
install -m 0644 ~/harness-certs/domain.crt caddy/data/custom-certs/domain.crt
install -m 0600 ~/harness-certs/domain.key caddy/data/custom-certs/domain.key
# Same content as vm-bootstrap.sh's env-config fixture for a current-era box.
( umask 077; cat > .env.config <<'ENVCONFIG'
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=standalone
SITE_DOMAIN=statbus-test.local
STATBUS_URL=https://statbus-test.local
BROWSER_REST_URL=https://statbus-test.local
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
TLS_CERT_FILE=/data/custom-certs/domain.crt
TLS_KEY_FILE=/data/custom-certs/domain.key
UPGRADE_CHANNEL=stable
ENVCONFIG
)
cp ~/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT
        _lxd_upload "$script" /root/s2-baseline.sh
        rm -f "$script"
        _lxd_host lxc file push /root/s2-baseline.sh "$base/home/statbus/s2-baseline.sh"
        _lxd_host lxc exec "$base" -- chown statbus:statbus /home/statbus/s2-baseline.sh
        _lxd_host lxc exec "$base" -- sudo -i -u statbus bash /home/statbus/s2-baseline.sh || { _lxd_mark "INSTALL FAILED $install_tag after $(($(date +%s)-start))s"; lxd_capture_failure "$base"; return 1; }
    else
        _lxd_host lxc exec "$base" -- sudo -i -u statbus bash -lc "set -o pipefail; curl -fsSL $installer_url | env $staging STATBUS_INSTALL_VERSION=$install_tag STATBUS_ENV_CONFIG=/home/statbus/install-input.env STATBUS_USERS_FILE=/home/statbus/users.yml STATBUS_MIN_DISK_GB=5 GIT_NETWORK_MAX_ATTEMPTS=8 GIT_NETWORK_RETRY_DELAY_S=45 DOCKER_PULL_MAX_ATTEMPTS=5 DOCKER_PULL_RETRY_DELAY_S=30 bash -s -- --non-interactive" || { _lxd_mark "INSTALL FAILED $install_tag after $(($(date +%s)-start))s"; lxd_capture_failure "$base"; return 1; }
    fi
    _lxd_mark "installer complete $tag in $(($(date +%s)-start))s"
    _lxd_ready "$base"
    _lxd_host lxc exec "$base" -- sudo -i -u statbus bash -lc 'cd ~/statbus && ./sb --version && ./sb ps'
    start=$(date +%s)
    _lxd_host lxc stop "$base" || return
    _lxd_host lxc snapshot "$base" checkpoint || return
    _lxd_mark "snapshot $base/checkpoint $(($(date +%s)-start))s"
}
lxd_base_for_candidate() {
    local tag=$1 checkpoint=${2:-installed-$1-standalone} base rc
    base=$(_lxd_name "$tag-$checkpoint")
    LXD_BASE_OWNED_BY_THIS_BUILD=0
    if _lxd_build_base_for_candidate "$tag" "$checkpoint"; then
        return 0
    else
        rc=$?
    fi
    if [ "$LXD_BASE_OWNED_BY_THIS_BUILD" = 1 ]; then
        _lxd_mark "base build failed: stopping incomplete $base (preserving for inspection)"
        _lxd_host lxc stop "$base" --force || _lxd_mark "WARNING: failed to stop incomplete $base"
    fi
    return "$rc"
}
lxd_fork() {
    local tag=$1 scenario=$2 base name start checkpoint
    checkpoint=$(lxd_checkpoint_for_scenario "$scenario") || return
    base=$(_lxd_name "$tag-$checkpoint"); name="s2-${tag//[^a-zA-Z0-9-]/-}-${scenario//[^a-zA-Z0-9-]/-}"
    [[ "$scenario" =~ ^[a-zA-Z0-9-]+$ ]] || return 2
    _lxd_host lxc info "$base" | grep -qE '^\| checkpoint +\|' || { echo "No checkpoint $base/checkpoint" >&2; return 1; }
    if _lxd_host lxc info "$name" >/dev/null 2>&1; then echo "REFUSE: $name exists. Reset explicitly first." >&2; return 1; fi
    start=$(date +%s); _lxd_host lxc copy "$base/checkpoint" "$name"
    VM_NAME=$name; LXD_OWNED_BY_THIS_RUN=1
    _lxd_mark "copy $base/checkpoint -> $name $(($(date +%s)-start))s"
    if [ "$scenario" = 4-install-40gb-disk ]; then
        _lxd_host lxc config device override "$name" root size=40GiB
        _lxd_mark "$name root Btrfs quota 40GiB"
    fi
    start=$(date +%s); _lxd_host lxc start "$name"
    # First boot's cloud-init rewrites ubuntu.sources back to archive/security
    # hosts, while hardening's package indexes came from mirrors.edge.kernel.org.
    # apt-get update -qq alone left a stale binary pkgcache containing only
    # Docker packages. Restore the mirror, invalidate it, and require Apache.
    _lxd_host lxc exec "$name" -- bash -c 'set -e; if grep -qE "http://(archive|security).ubuntu.com/ubuntu" /etc/apt/sources.list.d/ubuntu.sources; then sed -i -e "s#http://archive.ubuntu.com/ubuntu#https://mirrors.edge.kernel.org/ubuntu#g" -e "s#http://security.ubuntu.com/ubuntu#https://mirrors.edge.kernel.org/ubuntu#g" /etc/apt/sources.list.d/ubuntu.sources; fi; apt-get update -qq; rm -f /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin; apt-cache show apache2 >/dev/null'
    # Earlier prototype snapshots wrote /run/user/0 by expanding $(id -u) as
    # root. Append the actual statbus UID so nested login shells reach its bus.
    _lxd_host lxc exec "$name" -- bash -c 'echo "export XDG_RUNTIME_DIR=/run/user/1001" >> /home/statbus/.profile'
    if [ "$checkpoint" = hardened-nothing-installed ]; then
        local i
        for ((i=0;i<90;i++)); do
            VM_IP=$(_lxd_guest_ip "$name" 2>/dev/null || true)
            [ -n "$VM_IP" ] && break
            sleep 1
        done
        [ -n "$VM_IP" ] || { echo "No guest IP for $name" >&2; return 1; }
        _lxd_prepare_fresh_answers
        _lxd_mark "$name fresh boot IP $VM_IP"
    else
        _lxd_ready "$name"
        _lxd_host lxc exec "$name" -- bash -c 'cp /home/statbus/statbus/.env.config /home/statbus/env-config; chown statbus:statbus /home/statbus/env-config; chmod 0600 /home/statbus/env-config; ln -sfn /home/statbus/env-config /tmp/env-config; ln -sfn /home/statbus/users.yml /tmp/users.yml'
    fi
    _lxd_mark "boot/readiness $name $(($(date +%s)-start))s"
}
lxd_capture_failure() {
    local name=$1 out
    out="$LXD_LOG_DIR/lxd-$1-failure-$(date -u +%Y%m%dT%H%M%S).log"
    _lxd_mark "capture $name -> $out"
    {
        _lxd_host lxc exec "$name" -- sudo -i -u statbus bash -lc 'cd ~/statbus && tail -100 tmp/install-last-run-output.txt; docker compose --profile all ps; docker compose --profile all logs --tail 60' || true
        _lxd_host lxc exec "$name" -- journalctl --no-pager -n 120 -u docker || true
        _lxd_host lxc exec "$name" -- journalctl --user --no-pager -n 100 _UID=1001 || true
    } > "$out" 2>&1
    echo "$out"
}
lxd_reset() {
    local tag=$1 scenario=$2 name="s2-${1//[^a-zA-Z0-9-]/-}-${2//[^a-zA-Z0-9-]/-}" start
    if _lxd_host lxc info "$name" >/dev/null 2>&1; then
        start=$(date +%s); _lxd_host lxc delete "$name" --force
        _lxd_mark "delete $name $(($(date +%s)-start))s"
    fi
    lxd_fork "$tag" "$scenario"
}
# VM-harness-compatible shims for direct scenario commands.
bootstrap_install_test_vm() { lxd_fork "$LXD_CANDIDATE" "${1##statbus-recovery-}"; }
VM_EXEC() { local q; printf -v q '%q ' "$@"; _lxd_host lxc exec "$VM_NAME" -- sudo -i -u statbus bash -c "$q"; }
VM_ROOT_EXEC() { local q; printf -v q '%q ' "$@"; _lxd_host lxc exec "$VM_NAME" -- bash -c "$q"; }
cleanup_vm() {
    [ "${KEEP_VM:-0}" = 1 ] && return 0
    [ "${LXD_OWNED_BY_THIS_RUN:-0}" = 1 ] || return 0
    case "$VM_NAME" in
        "s2-${LXD_CANDIDATE//[^a-zA-Z0-9-]/-}-"*) _lxd_host lxc delete "$VM_NAME" --force ;;
        *) echo "REFUSE: cleanup outside candidate namespace: $VM_NAME" >&2; return 1 ;;
    esac
}
capture_failure_artifacts() { lxd_capture_failure "$VM_NAME"; }
harness_register_log() { _lxd_mark "registered guest log: $1 ${2:-}"; }
_lxd_unit_op() {
    local op=$1 unit=${2:-statbus-upgrade@statbus.service} wait_s=${3:-5} state
    if ! VM_EXEC systemctl --user "$op" "$unit"; then
        VM_EXEC journalctl --user -u "$unit" --no-pager -n 80 >&2 || true
        return 1
    fi
    sleep "$wait_s"
    state=$(VM_EXEC systemctl --user is-active "$unit" 2>/dev/null || true)
    [ "$state" = active ] || {
        echo "LXD unit $unit is $state after $op" >&2
        VM_EXEC journalctl --user -u "$unit" --no-pager -n 80 >&2 || true
        return 1
    }
}
vm_start_unit() { _lxd_unit_op start "$@"; }
vm_restart_unit() { _lxd_unit_op restart "$@"; }
_hcloud_server_ip() { _lxd_guest_ip "$VM_NAME"; }
hcloud() {
    if [ "${1:-}" = server ] && [ "${2:-}" = ip ] && [ "${3:-}" = "$VM_NAME" ]; then
        printf '%s\n' "$VM_IP"
    else
        echo "REFUSE: unsupported hcloud action in LXD scenario: $*" >&2
        return 2
    fi
}
upload_install_script_to_vm() {
    local name=$1 src=$2 dest=$3
    [ "$name" = "$VM_NAME" ] && [[ "$dest" == /tmp/* ]] || return 2
    _lxd_upload "$src" "/root/s2-install-script-$$"
    _lxd_host lxc file push "/root/s2-install-script-$$" "$name$dest"
    _lxd_host lxc exec "$name" -- chmod 0755 "$dest"
    rm -f "$src"
}
VM_SCRIPT_INLINE() {
    local label=$1 path remote; shift
    [[ "$label" =~ ^[a-zA-Z0-9-]+$ ]] || return 2
    path=$(mktemp "$LXD_LOG_DIR/s2-inline-${label}-XXXXXX") || return
    cat > "$path"
    remote="/home/statbus/s2-inline-${label}-$$.sh"
    _lxd_upload "$path" "/root/s2-inline-${label}-$$.sh"
    _lxd_host lxc file push "/root/s2-inline-${label}-$$.sh" "$VM_NAME$remote" >/dev/null 2>&1
    _lxd_host lxc exec "$VM_NAME" -- chmod 0755 "$remote"
    local rc=0
    VM_EXEC bash "$remote" "$@" || rc=$?
    rm -f "$path"
    return "$rc"
}
upload_sb_to_vm() {
    local name=$1
    [ "$name" = "$VM_NAME" ] || return 2
    _lxd_host lxc exec "$name" -- sudo -i -u statbus bash -lc "curl -fL --retry 3 -o /home/statbus/sb-candidate https://github.com/statisticsnorway/statbus/releases/download/$LXD_CANDIDATE/sb-linux-amd64 && chmod 0755 /home/statbus/sb-candidate"
    _lxd_mark "candidate binary downloaded for $name"
    _lxd_host lxc exec "$name" -- bash -c 'cp /home/statbus/sb-candidate /tmp/sb; chmod 0755 /tmp/sb'
    _lxd_mark "candidate binary staged for $name"
    _lxd_host lxc exec "$name" -- mv /home/statbus/statbus/sb /home/statbus/statbus/sb.old
    _lxd_mark "prior binary moved for $name"
    _lxd_host lxc exec "$name" -- install -m 0755 -o statbus -g statbus /tmp/sb /home/statbus/statbus/sb
    _lxd_mark "candidate binary installed for $name"
    # Keep the previous inode in this disposable fork; cleanup is not needed
    # for correctness and must not abort the injected scenario.
}
_run_long_via_tmux() { local command=$3; VM_EXEC bash -lc "$command"; }
_lxd_stage_candidate_install() {
    _wait_for_ssh "$VM_IP" 30
    # HARNESS_ROOT is the tag-pinned checkout reached through the shadow lib,
    # never the moving statbus.org/install.sh or the branch being edited.
    scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/install.sh" "root@$VM_IP:/tmp/statbus-install.sh"
    VM_ROOT_EXEC chmod 0644 /tmp/statbus-install.sh
}
install_statbus_in_vm() {
    local name=$1 log="$HARNESS_ROOT/tmp/install-recovery-$1-install.log" installed commit
    if [ -z "${2:-}" ]; then
        # VM harness's no-version contract: HEAD via the published per-commit
        # image, through install.sh --commit in RESCUE mode. A historical base
        # must become the candidate before a fault is injected, not just rerun
        # its old ./sb install (which hid the boot startup warning's real era).
        commit=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
        [ "$commit" = "$(git -C "$HARNESS_ROOT" rev-parse "$LXD_CANDIDATE^{commit}")" ] || return 2
        _lxd_stage_candidate_install
        VM_SCRIPT_INLINE install-head "$commit" "${HARNESS_DEPLOYMENT_MODE:-standalone}" "${HARNESS_NO_CUSTOM_CERT:-0}" <<'REMOTE' 2>&1 | tee -a "$log"
#!/usr/bin/env bash
set -e
if [ ! -d "$HOME/statbus/.git" ]; then
    for attempt in 1 2 3 4 5 6 7 8; do
        if git clone --depth 50 https://github.com/statisticsnorway/statbus.git "$HOME/statbus"; then break; fi
        [ "$attempt" -lt 8 ] || exit 1
        rm -rf "$HOME/statbus"; sleep 45
    done
fi
if [ "$2" = standalone ] && [ "$3" != 1 ]; then
    install -d -m 0755 "$HOME/statbus/caddy/data/custom-certs"
    install -m 0644 "$HOME/harness-certs/domain.crt" "$HOME/statbus/caddy/data/custom-certs/domain.crt"
    install -m 0600 "$HOME/harness-certs/domain.key" "$HOME/statbus/caddy/data/custom-certs/domain.key"
fi
cp /tmp/env-config "$HOME/statbus/.env.config"
cp /tmp/users.yml "$HOME/statbus/.users.yml"
STATBUS_MIN_DISK_GB=5 GIT_NETWORK_MAX_ATTEMPTS=8 GIT_NETWORK_RETRY_DELAY_S=45 DOCKER_PULL_MAX_ATTEMPTS=5 DOCKER_PULL_RETRY_DELAY_S=30 bash /tmp/statbus-install.sh --commit "$1" --trust-github-user jhf
REMOTE
        return "${PIPESTATUS[0]}"
    fi
    if [ -n "${2:-}" ]; then
        installed=$(VM_EXEC bash -lc 'cd ~/statbus && ./sb --version' 2>/dev/null || true)
        if [ "${LXD_BASELINE_CONSUMED:-0}" = 0 ] && [[ "$installed" == *"${2}"* ]]; then
            LXD_BASELINE_CONSUMED=1
            _lxd_mark "historical baseline ${2} already established by real installer in checkpoint"
            return 0
        fi
    fi
    VM_EXEC bash -lc "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" 2>&1 | tee -a "$log"
    return "${PIPESTATUS[0]}"
}
install_statbus_at_sha() {
    local tag=${3:?tag required} sha=${2:?sha required} log="$HARNESS_ROOT/tmp/install-recovery-${1}-install.log"
    [ "$(git -C "$HARNESS_ROOT" rev-parse "$tag^{commit}")" = "$sha" ] || {
        echo "REFUSE: $tag does not resolve to supplied commit $sha" >&2; return 2;
    }
    VM_EXEC test ! -e /home/statbus/statbus || { echo 'FRESH checkout already exists' >&2; return 70; }
    _lxd_stage_candidate_install
    VM_SCRIPT_INLINE tagged-install "$tag" "${HARNESS_DEPLOYMENT_MODE:-standalone}" "${HARNESS_SITE_DOMAIN:-statbus-test.local}" "${HARNESS_NO_CUSTOM_CERT:-0}" "${HARNESS_INSTALL_PRERELEASE_CHANNEL:-0}" "${HARNESS_INTERACTIVE_ADMIN:-0}" "$VM_NAME" <<'REMOTE' 2>&1 | tee -a "$log"
#!/usr/bin/env bash
set -e
[ ! -e "$HOME/statbus" ] || { echo 'harness: FRESH requires absent ~/statbus'; exit 70; }
( umask 077; {
    printf 'CADDY_DEPLOYMENT_MODE=%s\nSITE_DOMAIN=%s\n' "$2" "$3"
    if [ "$2" = standalone ] && [ "$4" != 1 ]; then
        printf 'TLS_CERT_FILE=/data/custom-certs/domain.crt\nTLS_KEY_FILE=/data/custom-certs/domain.key\n'
    fi
    printf 'DEPLOYMENT_SLOT_NAME=Install Test\nDEPLOYMENT_SLOT_CODE=test\nTRUST_GITHUB_USER=jhf\n'
} > "$HOME/install-input.env" )
case "$(umask)" in *[4567]) echo 'harness: umask strips other-read'; exit 70 ;; esac
export STATBUS_ENV_CONFIG="$HOME/install-input.env"
if [[ "$7" == *-4-install-40gb-disk ]]; then
    unset STATBUS_MIN_DISK_GB
else
    export STATBUS_MIN_DISK_GB=5
fi
if [ "$2" = standalone ] && [ "$4" != 1 ]; then export STATBUS_HARNESS_CERT_STAGING="$HOME/harness-certs"; fi
export STATBUS_INSTALL_VERSION="$1"
if [ "$6" = 1 ]; then
    unset STATBUS_USERS_FILE
    exec expect /tmp/statbus-admin.exp
fi
export STATBUS_USERS_FILE=/tmp/users.yml
if [ "$5" = 1 ]; then
    unset STATBUS_INSTALL_VERSION
    exec bash /tmp/statbus-install.sh --channel prerelease --non-interactive
fi
exec bash /tmp/statbus-install.sh --non-interactive
REMOTE
    return "${PIPESTATUS[0]}"
}
