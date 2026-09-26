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
    [[ "$destination" == root@"${VM_IP:-UNSET}":/* ]] || { echo "REFUSE: guest SCP destination $destination" >&2; return 2; }
    staging="/root/s2-transfer-$$"
    _lxd_upload "$source" "$staging"
    _lxd_host lxc file push "$staging" "$VM_NAME${destination#*:}"
}
_lxd_guest_ip() {
    _lxd_host lxc exec "$1" -- hostname -I | awk '{for(i=1;i<=NF;i++) if ($i ~ /^10\.111\./) {print $i; exit}}'
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
    local slug=$1 file="$HARNESS_ROOT/test/install-recovery/scenarios/$1.sh" baseline
    [ -f "$file" ] || { echo "Unknown scenario $slug" >&2; return 2; }
    case "$slug" in
        0-happy-*|0-interactive-admin-password|4-install-*|5-install-interrupted-restart|5-install-live-upgrade-wait)
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
lxd_base_for_candidate() {
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
    _lxd_host lxc launch ubuntu:24.04 "$base" --config security.nesting=true --config limits.cpu=2 --config limits.memory=6GiB
    _lxd_upload "$HARNESS_ROOT/ops/setup-ubuntu-lts.sh" /root/s2-setup.sh
    _lxd_host lxc file push /root/s2-setup.sh "$base/root/setup.sh"
    _lxd_host lxc exec "$base" -- bash -c 'printf "ADMIN_EMAIL=test@statbus.org\nGITHUB_USERS=jhf\nEXTRA_LOCALES=\nCADDY_PLUGINS=\n" > /root/.setup-ubuntu.env; mkdir -p /run/sshd'
    _lxd_mark "hardening start $base (SKIP_STAGES=4 as VM harness)"
    _lxd_host lxc exec "$base" -- env SKIP_STAGES=4 bash /root/setup.sh --non-interactive || {
        # The prototype's Stage 0 verifier mistakenly inspected its own backup.
        # Retry only failed setup stages, never suppress an unexplained error.
        _lxd_host lxc exec "$base" -- bash -c 'rm -f /etc/apt/sources.list.d/ubuntu.sources.bak; mkdir -p /run/sshd'
        _lxd_host lxc exec "$base" -- env SKIP_STAGES='1 3 4 5 6 7 8' bash /root/setup.sh --non-interactive
    }
    _lxd_host lxc exec "$base" -- bash -c 'usermod -aG docker statbus; loginctl enable-linger statbus; echo "export XDG_RUNTIME_DIR=/run/user/1001" >> /home/statbus/.profile; systemctl is-active docker'
    _lxd_host lxc exec "$base" -- apt-get update -qq
    lxd_certificates "$base"
    _lxd_mark "hardening complete $base in $(($(date +%s)-start))s"
    if [ "$checkpoint" = hardened-nothing-installed ]; then
        _lxd_host lxc exec "$base" -- test ! -e /home/statbus/statbus
        _lxd_host lxc stop "$base"
        _lxd_host lxc snapshot "$base" checkpoint
        return 0
    fi
    local install_tag=${checkpoint#installed-}
    install_tag=${install_tag%-standalone}
    [[ "$install_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "Invalid checkpoint $checkpoint" >&2; return 2; }
    fixture=$(mktemp "$LXD_LOG_DIR/s2-users-XXXXXX")
    printf '%s\n' '- email: test@statbus.org' '  password: test-install-password-2026' '  role: admin_user' '  display_name: Admin' > "$fixture"
    _lxd_upload "$fixture" /root/s2-users.yml
    rm -f "$fixture"
    _lxd_host lxc file push /root/s2-users.yml "$base/home/statbus/users.yml"
    _lxd_host lxc exec "$base" -- chown statbus:statbus /home/statbus/users.yml
    _lxd_host lxc exec "$base" -- bash -c 'printf "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus-test.local\nTLS_CERT_FILE=/data/custom-certs/domain.crt\nTLS_KEY_FILE=/data/custom-certs/domain.key\nDEPLOYMENT_SLOT_NAME=Install Test\nDEPLOYMENT_SLOT_CODE=test\nTRUST_GITHUB_USER=jhf\n" > /home/statbus/install-input.env; chown statbus:statbus /home/statbus/install-input.env; chmod 600 /home/statbus/install-input.env'
    start=$(date +%s)
    _lxd_mark "REAL tagged installer start $tag $base"
    local installer_url=https://statbus.org/install.sh
    local staging=STATBUS_HARNESS_CERT_STAGING=/home/statbus/harness-certs
    if [ "$install_tag" != "$tag" ]; then
        _lxd_mark "historical target $install_tag via current installer certificate staging seam"
    fi
    _lxd_host lxc exec "$base" -- sudo -i -u statbus bash -lc "set -o pipefail; curl -fsSL $installer_url | env $staging STATBUS_INSTALL_VERSION=$install_tag STATBUS_ENV_CONFIG=/home/statbus/install-input.env STATBUS_USERS_FILE=/home/statbus/users.yml STATBUS_MIN_DISK_GB=5 GIT_NETWORK_MAX_ATTEMPTS=8 GIT_NETWORK_RETRY_DELAY_S=45 DOCKER_PULL_MAX_ATTEMPTS=5 DOCKER_PULL_RETRY_DELAY_S=30 bash -s -- --non-interactive" || { _lxd_mark "INSTALL FAILED $install_tag after $(($(date +%s)-start))s"; lxd_capture_failure "$base"; return 1; }
    _lxd_mark "installer complete $tag in $(($(date +%s)-start))s"
    _lxd_ready "$base"
    _lxd_host lxc exec "$base" -- sudo -i -u statbus bash -lc 'cd ~/statbus && ./sb --version && ./sb ps'
    start=$(date +%s)
    _lxd_host lxc stop "$base"
    _lxd_host lxc snapshot "$base" checkpoint
    _lxd_mark "snapshot $base/checkpoint $(($(date +%s)-start))s"
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
install_statbus_in_vm() {
    local name=$1 log="$HARNESS_ROOT/tmp/install-recovery-$1-install.log" installed
    if VM_EXEC test ! -e /home/statbus/statbus; then
        install_statbus_at_sha "$name" "$(git -C "$HARNESS_ROOT" rev-parse "$LXD_CANDIDATE^{commit}")" "$LXD_CANDIDATE"
        return
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
    local tag=${3:?tag required} sha=${2:?sha required} log="$LXD_LOG_DIR/fresh-${VM_NAME}.log"
    [ "$(git -C "$HARNESS_ROOT" rev-parse "$tag^{commit}")" = "$sha" ] || {
        echo "REFUSE: $tag does not resolve to supplied commit $sha" >&2; return 2;
    }
    VM_EXEC test ! -e /home/statbus/statbus || { echo 'FRESH checkout already exists' >&2; return 70; }
    VM_ROOT_EXEC bash -lc 'printf "%s\n" "- email: test@statbus.org" "  password: test-install-password-2026" "  role: admin_user" "  display_name: Admin" > /home/statbus/users.yml; chown statbus:statbus /home/statbus/users.yml; chmod 0600 /home/statbus/users.yml'
    VM_ROOT_EXEC ln -sfn /home/statbus/users.yml /tmp/users.yml
    VM_ROOT_EXEC bash -lc 'cat > /home/statbus/install-input.env <<EOF
CADDY_DEPLOYMENT_MODE=standalone
SITE_DOMAIN=statbus-test.local
TLS_CERT_FILE=/data/custom-certs/domain.crt
TLS_KEY_FILE=/data/custom-certs/domain.key
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
TRUST_GITHUB_USER=jhf
EOF
chown statbus:statbus /home/statbus/install-input.env; chmod 600 /home/statbus/install-input.env'
    VM_EXEC bash -lc "set -o pipefail; curl -fsSL https://statbus.org/install.sh | env STATBUS_HARNESS_CERT_STAGING=/home/statbus/harness-certs STATBUS_INSTALL_VERSION=$tag STATBUS_USERS_FILE=/home/statbus/users.yml STATBUS_ENV_CONFIG=/home/statbus/install-input.env STATBUS_MIN_DISK_GB=5 bash -s -- --non-interactive" 2>&1 | tee "$log"
    local rc=${PIPESTATUS[0]}
    return "$rc"
}
