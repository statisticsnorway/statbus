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
[ -z "${LXD_SSH_KEY_FILE:-}" ] || LXD_SSH_OPTS+=(-i "$LXD_SSH_KEY_FILE")
# shellcheck disable=SC2034 # Sourced assertions consume this variable.
# Nonempty because bash 3.2 with nounset treats an empty array expansion as unbound.
SSH_OPTS=(-o BatchMode=yes)
# Resolved BEFORE any PATH modification below: once the executable ssh/hcloud
# shim directory is prepended to PATH, a bare `ssh` (even via `command ssh`,
# which still does a PATH lookup) resolves to THIS FILE's own shim instead of
# the real binary — the fleet host connection (_lxd_host, talks to LXD_HOST,
# never a guest) would then wrongly route through the guest-only ssh shim and
# get refused ("does not match fork IP"). Pin the absolute real path once,
# here, before that happens (STATBUS-425 M3a: found and fixed by testing this
# live, not merely written and trusted). Idempotent and cross-process-safe:
# run-smoke.sh sources this file once, then runs the SCENARIO as a genuinely
# separate `bash script.sh` child (not `source`), which inherits the
# already-shimmed PATH and re-sources this same file again (via
# vm-bootstrap.sh's HARNESS_LXD_BACKEND branch) — a second unconditional
# `command -v ssh` there would resolve to the FIRST sourcing's shim, not the
# real binary, corrupting every "real" ssh call transitively (caught live
# rerunning the full smoke flow end-to-end before trusting this). Exporting
# _LXD_REAL_SSH makes every re-sourcing, in any descendant process, reuse the
# one true absolute path resolved by the very first sourcing.
if [ -z "${_LXD_REAL_SSH:-}" ]; then
    _LXD_REAL_SSH=$(command -v ssh)
    export _LXD_REAL_SSH
fi
_lxd_host() { local q; printf -v q '%q ' "$@"; LC_ALL=C "$_LXD_REAL_SSH" "${LXD_SSH_OPTS[@]}" "$LXD_HOST" "$q"; }
# Six arcs call `timeout N ssh ...` / `hcloud server ip ...` directly (their
# Hetzner-era mechanism for a bounded remote command). `timeout` execve()s a
# FRESH process for its argument, which loses every bash FUNCTION shim (ssh(),
# scp(), hcloud() below) — those intercept only a direct shell call, never one
# reached through another binary's exec (STATBUS-425 M3a review finding;
# verified live: `timeout 5 ssh host cmd` tries the real network even with an
# `ssh() { ... }` function defined in the same shell). A real EXECUTABLE
# script on PATH survives an execve chain; a function shim does not. Generate
# one once per sourcing, using the REAL ssh binary's absolute path resolved
# above (never a bare `ssh` inside the generated script itself, which would
# resolve back through this same PATH-prepended dir and recurse). VM_NAME and
# VM_IP must be EXPORTED, not merely set, for a genuinely separate process to
# see them.
LXD_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lxd-ssh-shim-XXXXXX")
trap 'rm -rf "$LXD_SHIM_DIR"' EXIT
cat > "$LXD_SHIM_DIR/ssh" << SHIM
#!/usr/bin/env bash
set -euo pipefail
host=''
option=''
while [ "\$#" -gt 0 ]; do
    option=\$1; shift
    case "\$option" in
        -o|-i|-p|-F) shift ;;
        -*) ;;
        *@*) host=\$option; break ;;
        *) echo "Unexpected SSH argument: \$option" >&2; exit 2 ;;
    esac
done
[ "\${host#*@}" = "\${VM_IP:-UNSET}" ] || { echo "REFUSE: guest SSH destination \$host does not match fork IP" >&2; exit 2; }
# Single-escape, matching _lxd_host's own printf -v q '%q ' "\$@" exactly: the
# remote side re-parses this one %q-quoted string back into its original
# tokens (verified live: a naive re-escape of an already-%q string here
# corrupted every space/semicolon in the arc's remote command).
q=\$(printf '%q ' lxc exec "\$VM_NAME" -- bash -lc "\$*")
case "\$host" in
    root@*) exec "$_LXD_REAL_SSH" $(printf '%q ' "${LXD_SSH_OPTS[@]}") "\$LXD_HOST" "\$q" ;;
    statbus@*)
        q=\$(printf '%q ' lxc exec "\$VM_NAME" -- sudo -u statbus -H env XDG_RUNTIME_DIR=/run/user/1001 bash -c "\$*")
        exec "$_LXD_REAL_SSH" $(printf '%q ' "${LXD_SSH_OPTS[@]}") "\$LXD_HOST" "\$q" ;;
    *) exit 2 ;;
esac
SHIM
cat > "$LXD_SHIM_DIR/hcloud" << 'SHIM'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = server ] && [ "${2:-}" = ip ] && [ "${3:-}" = "${VM_NAME:-}" ]; then
    printf '%s\n' "${VM_IP:-}"
else
    echo "REFUSE: unsupported hcloud action in LXD scenario: $*" >&2
    exit 2
fi
SHIM
chmod +x "$LXD_SHIM_DIR/ssh" "$LXD_SHIM_DIR/hcloud"
export PATH="$LXD_SHIM_DIR:$PATH"
export LXD_HOST
# `declare -x` marks the variable exported once; every later PLAIN assignment
# (VM_NAME=$name, VM_IP=$ip — both already unqualified throughout this file)
# then auto-exports too, with no need to touch each call site. The executable
# ssh/hcloud shim above (and any other subprocess a scenario/arc spawns) is a
# genuinely separate process and can only see VM_NAME/VM_IP if they cross
# that boundary as real environment, not just shell-local variables.
declare -x VM_NAME VM_IP
LXD_BASE_PREFIX=${LXD_BASE_PREFIX:-s2-base}
LXD_FORK_PREFIX=${LXD_FORK_PREFIX:-s2}
_lxd_name() {
    [[ "$LXD_BASE_PREFIX" =~ ^[a-z][a-z0-9-]{0,12}$ ]] || { echo "Invalid LXD_BASE_PREFIX: $LXD_BASE_PREFIX" >&2; return 2; }
    printf '%s-%s' "$LXD_BASE_PREFIX" "${1//[^a-zA-Z0-9-]/-}"
}
_lxd_mark() { printf '%s | %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
# Pure selector: read instance names on stdin and print only other candidate
# bases. Parse the tag BEFORE any checkpoint suffix, which itself may contain
# a historical release name unrelated to the base's owning candidate.
_lxd_bases_to_prune() {
    local tag=$1 safe=${1//[^a-zA-Z0-9-]/-} name base_tag
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || return 2
    while IFS= read -r name; do
        if [[ "$name" =~ ^(fleet|s2)-base-(v[0-9]+-[0-9]+-[0-9]+-rc-[0-9]+)(-[a-zA-Z0-9-]+)?$ ]]; then
            base_tag=${BASH_REMATCH[2]}
            [ "$base_tag" = "$safe" ] || printf '%s\n' "$name"
        fi
    done
}
_lxd_prune_other_bases() {
    local tag=$1 selector
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || return 2
    # CI/driver acquired an occupancy marker (marker.sh) before entering here.
    # The flock serializes this destructive catalog maintenance with reaper
    # and ramp-up. "Active" is directory-non-empty: smoke, the fault driver
    # and arc jobs each hold their OWN marker file concurrently (STATBUS-425
    # M2'); a single marker file would let the first job to finish delete the
    # file while a sibling job is still running.
    selector=$(declare -f _lxd_bases_to_prune)
    _lxd_host flock /root/fleet-run.lock bash -c "$selector"$'
set -euo pipefail
active=$(ls -A /root/fleet-active 2>/dev/null || true)
# review H3: a bare `A && B && C` statement list is NOT a guard under
# set -e. Per bash'\''s errexit exception, the shell exits on the FAILURE
# of the last command in an && list, but a failure of an EARLIER member
# (here, an empty $active, meaning nobody holds an occupancy marker while
# pruning is about to run) makes the whole list evaluate false WITHOUT
# tripping errexit, because it is not itself the final element. Execution
# then fell through to the destructive loop below regardless. Verified
# live before this fix: this exact three-clause line with $active empty
# printed nothing and returned 0, continuing to `names=$(lxc list ...)`.
# The `|| { ...; exit 1; }` form used everywhere else in this codebase
# (up.sh, harden-host.sh) is the one shape that is actually a guard.
[ -n "$active" ] && [ ! -e /root/fleet-reaping ] && [ ! -e /root/fleet-hardening.active ] || {
    echo "REFUSE: no active occupancy marker, or reaper/hardening active; refusing to prune" >&2
    exit 1
}
names=$(lxc list -c n --format csv)
while IFS= read -r name; do
    echo "prune superseded base $name"
    lxc delete "$name" --force
done < <(_lxd_bases_to_prune "$1" <<< "$names")
' _ "$tag"
}
_lxd_upload() { command scp -q "${LXD_SSH_OPTS[@]}" "$1" "$LXD_HOST:$2"; }
# `lxc file push` talks to a per-instance forkfile helper that LXD 5.21 exits
# after 10s idle (lxd/main_forkfile.go). A push that connects while that helper
# is exiting fails with "error receiving version packet ... forkfile.sock ...
# connection reset by peer" (rc.15 LXD run 36433435451, 5-install-stage-c).
# Errors naming forkfile.sock (that race, or a helper socket gone missing) are
# retried, at most 3 attempts in all: a push spawns a fresh helper, and every
# call site is an idempotent overwrite. Any other failure surfaces at once.
_lxd_push() {
    local attempt err
    for attempt in 1 2 3; do
        if err=$(_lxd_host lxc file push "$@" 2>&1); then
            [ -z "$err" ] || printf '%s\n' "$err" >&2
            return 0
        fi
        printf '%s\n' "$err" >&2
        case "$err" in *forkfile.sock*) ;; *) return 1 ;; esac
        [ "$attempt" -lt 3 ] || { _lxd_mark "lxc file push: forkfile helper error persisted after 3 attempts"; return 1; }
        _lxd_mark "lxc file push hit the forkfile idle-exit race (attempt $attempt/3); retrying"
        sleep 1
    done
}
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
    _lxd_push "$staging" "$VM_NAME${destination#*:}"
}
# harness_real_ssh [ssh-args...] — deploy-status-proof-arc.sh's genuine sshd
# requirement (STATBUS-425 M3a): that arc's whole point is proving a REAL
# ssh -> sshdo -> forced-command gate, so it must reach the fork's actual
# sshd, never lxd-backend.sh's own ssh() shim above (which reroutes every
# ordinary `ssh root@$VM_IP ...` call through `lxc exec`, silently defeating
# the proof — the probe would "pass" against a gate it never touched).
# ProxyJump through the fleet host: the fork's LXD-bridge IP (VM_IP, e.g.
# 10.x.x.x) is not routable from the CI runner, only from LXD_HOST itself.
# `-F none` is required, not optional — an ambient ~/.ssh/config on the
# runner (Include/ProxyJump/Host-block defaults) could otherwise silently
# change the transport this arc is trying to prove (verified live: a local
# ControlMaster reuse masked a real auth failure during prototyping).
# IdentitiesOnly is the CALLER's responsibility (probe_ssh's own -i pins the
# ephemeral probe key) — this function must not decide identity policy for
# every caller, only the routing. Host-key checking for the GUEST itself is
# baked in here (StrictHostKeyChecking=no/UserKnownHostsFile=/dev/null): a
# fresh fork's host key is never known ahead of time and SSH_OPTS on this
# backend is a nonempty-only placeholder (see its own comment above), not a
# real per-call option set the way it is on the Hetzner backend.
harness_real_ssh() {
    "$_LXD_REAL_SSH" -F none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ProxyCommand="$_LXD_REAL_SSH -F none -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${LXD_SSH_KEY_FILE:+-i $LXD_SSH_KEY_FILE} $LXD_HOST" "$@"
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
    _lxd_push /root/s2-env-config "$VM_NAME/tmp/env-config"
    _lxd_host lxc exec "$VM_NAME" -- chown statbus:statbus /tmp/env-config
    _lxd_host lxc exec "$VM_NAME" -- chmod 0600 /tmp/env-config
    rm -f "$fixture"
    # Recovery arcs opt into authenticated GitHub access by exporting
    # GITHUB_TOKEN in their workflow step (never happy install/upgrade proofs,
    # which stay anonymous by construction - unchanged). Anonymous GitHub API
    # rate limits (60 req/h) are a real risk once faults and arcs run
    # concurrently on one box IP (STATBUS-425 review §1i.3). Mirrors
    # vm-bootstrap.sh's harness_render_github_token exactly: post-361 code
    # (which this LXD path only ever targets - it installs the current
    # candidate's own release, never a pre-361 era) reads GITHUB_TOKEN from
    # .env.credentials, never .env.config.
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        fixture=$(mktemp "$LXD_LOG_DIR/s2-cred-XXXXXX")
        printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN" > "$fixture"
        _lxd_upload "$fixture" /root/s2-env-credentials
        _lxd_push /root/s2-env-credentials "$VM_NAME/tmp/env-credentials"
        _lxd_host lxc exec "$VM_NAME" -- chown statbus:statbus /tmp/env-credentials
        _lxd_host lxc exec "$VM_NAME" -- chmod 0600 /tmp/env-credentials
        rm -f "$fixture"
    fi
    fixture=$(mktemp "$LXD_LOG_DIR/s2-users-XXXXXX")
    printf '%s\n' '- email: test@statbus.org' '  password: test-install-password-2026' '  role: admin_user' '  display_name: Admin' > "$fixture"
    _lxd_upload "$fixture" /root/s2-users.yml
    _lxd_push /root/s2-users.yml "$VM_NAME/tmp/users.yml"
    _lxd_host lxc exec "$VM_NAME" -- chmod 0644 /tmp/users.yml
    rm -f "$fixture"
}
_lxd_build_base_for_candidate() {
    local tag=$1 checkpoint=${2:-installed-$1-standalone} base start fixture channel
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || { echo "Invalid candidate tag: $tag" >&2; return 2; }
    # The historical-baseline install (below) must match what the calling
    # scenario declares (0-happy-upgrade.sh sets HARNESS_UPGRADE_CHANNEL=
    # prerelease; the fault fleet's own fallback build leaves the harness
    # default of stable), not silently hard-code stable regardless of caller
    # (review §1a.5: the Norway prerelease hop must genuinely be a prerelease
    # box, not merely announced as one after an explicit `register`).
    channel=${HARNESS_UPGRADE_CHANNEL:-stable}
    case "$channel" in stable|prerelease) ;; *) echo "Invalid HARNESS_UPGRADE_CHANNEL: $channel" >&2; return 2 ;; esac
    base=$(_lxd_name "$tag-$checkpoint")
    if _lxd_host lxc info "$base" 2>/dev/null | grep -qE '^\| checkpoint +\|'; then
        if [ "$(_lxd_host lxc config get "$base" image.version)" != 26.04 ]; then
            echo "REFUSE: $base/checkpoint predates Ubuntu 26.04; replace only after its active fleet drains." >&2
            return 1
        fi
        # A cached base built for one channel must not be silently reused for
        # the other: 0-happy-upgrade's prerelease hop and the fault fleet's
        # stable fallback build the SAME checkpoint name from the SAME tag,
        # but different .env.config content (review §1a.5). Bases built
        # before this key carries no opinion and are trusted as-is (their
        # single caller at the time was always stable).
        local cached_channel
        cached_channel=$(_lxd_host lxc config get "$base" user.statbus.channel 2>/dev/null || true)
        if [ -n "$cached_channel" ] && [ "$cached_channel" != "$channel" ]; then
            echo "REFUSE: $base/checkpoint was built for channel=$cached_channel, this build wants channel=$channel" >&2
            return 1
        fi
        _lxd_mark "$base/checkpoint exists, reusing candidate catalog entry (channel=${cached_channel:-$channel})"; return 0
    fi
    if _lxd_host lxc info "$base" >/dev/null 2>&1; then
        echo "REFUSE: unsnapshotted base $base exists. Inspect or delete explicitly before retry." >&2; return 1
    fi
    start=$(date +%s)
    _lxd_mark "launch $base ubuntu:26.04 nesting=true cpu=2 memory=6GiB"
    _lxd_host lxc launch ubuntu:26.04 "$base" --config security.nesting=true --config limits.cpu=2 --config limits.memory=6GiB || return
    LXD_BASE_OWNED_BY_THIS_BUILD=1
    _lxd_upload "$HARNESS_ROOT/ops/setup-ubuntu-lts.sh" /root/s2-setup.sh || return
    _lxd_push /root/s2-setup.sh "$base/root/setup.sh" || return
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
    # review B3: a non-stable identity carries a "-pre" suffix (see
    # run-smoke.sh's prerelease checkpoint name) so it cannot collide with
    # the fault fleet's stable-named checkpoint of the SAME baseline tag.
    # Strip it before "-standalone" so the underlying release tag parses the
    # same as it always has.
    install_tag=${install_tag%-pre}
    install_tag=${install_tag%-standalone}
    [[ "$install_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "Invalid checkpoint $checkpoint" >&2; return 2; }
    fixture=$(mktemp "$LXD_LOG_DIR/s2-users-XXXXXX")
    printf '%s\n' '- email: test@statbus.org' '  password: test-install-password-2026' '  role: admin_user' '  display_name: Admin' > "$fixture"
    _lxd_upload "$fixture" /root/s2-users.yml || return
    rm -f "$fixture"
    _lxd_push /root/s2-users.yml "$base/home/statbus/users.yml"
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
UPGRADE_CHANNEL=$channel
ENVCONFIG
)
cp ~/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT
        _lxd_upload "$script" /root/s2-baseline.sh
        rm -f "$script"
        _lxd_push /root/s2-baseline.sh "$base/home/statbus/s2-baseline.sh"
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
    _lxd_host lxc config set "$base" user.statbus.channel "$channel" || return
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
    local tag=$1 scenario=$2 base name checkpoint provenance
    checkpoint=$(lxd_checkpoint_for_scenario "$scenario") || return
    [[ "$LXD_FORK_PREFIX" =~ ^[a-z][a-z0-9-]{0,12}$ ]] || return 2
    base=$(_lxd_name "$tag-$checkpoint"); name="$LXD_FORK_PREFIX-${tag//[^a-zA-Z0-9-]/-}-${scenario//[^a-zA-Z0-9-]/-}"
    [[ "$scenario" =~ ^[a-zA-Z0-9-]+$ ]] || return 2
    provenance=$(_lxd_host lxc config get "$base" user.statbus.candidate 2>/dev/null || true)
    if [ -n "$provenance" ] && [ "$provenance" != "$tag" ]; then
        echo "REFUSE: $base/checkpoint carries provenance candidate=$provenance, expected $tag" >&2
        return 1
    fi
    if [ -n "$provenance" ]; then
        _lxd_mark "$base/checkpoint provenance: candidate=$provenance producer=$(_lxd_host lxc config get "$base" user.statbus.producer 2>/dev/null || echo unknown) run_id=$(_lxd_host lxc config get "$base" user.statbus.run_id 2>/dev/null || echo unknown)"
    fi
    _lxd_fork_from_base "$base" "$name" "$checkpoint"
}
# _lxd_fork_from_base <base> <name> <checkpoint-kind> — the mechanical half of
# lxd_fork (copy checkpoint -> boot -> ready), factored out so
# bootstrap_install_test_vm's arc path (which has no scenario file to resolve
# a base/name from) can drive the exact same guest-boot sequence directly.
# checkpoint-kind is "hardened-nothing-installed" or anything else (installed
# base); only that distinction changes what happens after boot.
_lxd_fork_from_base() {
    local base=$1 name=$2 checkpoint=$3 start
    # Provenance is a forensic log, not a hard gate here (M4 wires an
    # orchestrator-dispatch flag that refuses a fleet/arc self-build; this is
    # the read half, landed with the write half in lxd_snapshot_installed).
    # A base with no provenance key predates this or was built by the
    # fallback path (_lxd_build_base_for_candidate) - expected and not an error.
    _lxd_host lxc info "$base" | grep -qE '^\| checkpoint +\|' || { echo "No checkpoint $base/checkpoint" >&2; return 1; }
    if _lxd_host lxc info "$name" >/dev/null 2>&1; then echo "REFUSE: $name exists. Reset explicitly first." >&2; return 1; fi
    start=$(date +%s); _lxd_host lxc copy "$base/checkpoint" "$name"
    VM_NAME=$name; LXD_OWNED_BY_THIS_RUN=1
    _lxd_mark "copy $base/checkpoint -> $name $(($(date +%s)-start))s"
    start=$(date +%s); _lxd_host lxc start "$name"
    _lxd_host lxc exec "$name" -- cloud-init status --wait
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
        # Container ID, image and creation time answer "was the container
        # RECREATED (new ID/CreatedAt) or merely restarted" from the artifact
        # alone, without a live box to inspect (STATBUS-425 review §1h,
        # tmp/crollback-rc16-rootcause.md: only install logs were uploaded,
        # so this exact question was unanswerable after the fact).
        _lxd_host lxc exec "$name" -- docker ps -a --format '{{.ID}} {{.Image}} {{.Names}} {{.CreatedAt}} {{.Status}}' || true
        _lxd_host lxc exec "$name" -- journalctl --no-pager -n 120 -u docker || true
        _lxd_host lxc exec "$name" -- journalctl --user --no-pager -n 100 _UID=1001 || true
    } > "$out" 2>&1
    echo "$out"
}
lxd_reset() {
    local tag=$1 scenario=$2 name="$LXD_FORK_PREFIX-${1//[^a-zA-Z0-9-]/-}-${2//[^a-zA-Z0-9-]/-}" start
    if _lxd_host lxc info "$name" >/dev/null 2>&1; then
        start=$(date +%s); _lxd_host lxc delete "$name" --force
        _lxd_mark "delete $name $(($(date +%s)-start))s"
    fi
    lxd_fork "$tag" "$scenario"
}
lxd_snapshot_installed() {
    local tag=$1 name=$2 base run_id live fork_prefix_pattern
    [ "$tag" = "$LXD_CANDIDATE" ] || return 2
    [ "$name" = "$VM_NAME" ] && [ "${LXD_OWNED_BY_THIS_RUN:-0}" = 1 ] || return 2
    run_id=${GITHUB_RUN_ID:-manual}
    [[ "$run_id" =~ ^[a-zA-Z0-9._-]+$ ]] || return 2
    base=$(_lxd_name "$tag-installed-$tag-standalone")
    fork_prefix_pattern="$LXD_FORK_PREFIX-${tag//[^a-zA-Z0-9-]/-}-"
    # Rerun-safe: a `gh run rerun` of an infra flake must not be permanently
    # stuck behind "base already exists" until a human deletes it by hand
    # (review §1a.3). Serialize the check-and-replace under the same host
    # flock the pruning path uses, and only ever replace a base that has a
    # live fork of THIS candidate currently RUNNING OTHER than the caller's
    # own source fork ($name): lxd_snapshot_installed is called WHILE its own
    # fork is running by design (it copies the running fork, see below), so
    # without excluding self the probe always finds at least $name RUNNING
    # and permanently refuses every rerun, including the very first attempt
    # (review §B2: verified live against a real running fork, not just
    # offline — the probe subshell's own stdout, not the `calls` mock array,
    # is what a caller observes, since command substitution runs in a
    # subshell bash arrays cannot see into).
    live=$(_lxd_host flock /root/fleet-run.lock bash -c '
set -euo pipefail
base=$1 prefix=$2 self=$3
if lxc info "$base" >/dev/null 2>&1; then
    running=$(lxc list -c n,s --format csv | awk -F, -v p="$prefix" -v self="$self" "\$1!=self && index(\$1,p)==1 && \$2==\"RUNNING\" {print \$1}")
    if [ -n "$running" ]; then
        printf "%s\n" "$running"
    else
        lxc delete "$base" --force
    fi
fi
' _ "$base" "$fork_prefix_pattern" "$name") || return
    if [ -n "$live" ]; then
        echo "REFUSE: smoke checkpoint $base already exists and live forks of $tag are still RUNNING (will not replace): $live" >&2
        return 1
    fi
    # Copy the RUNNING fork, never stop-then-start it: `/tmp` is tmpfs on these
    # guests (systemd tmp.mount), so a restart would wipe /tmp/env-config
    # before the scenario's separate Phase 2 (operator tuning) reads it back.
    # `lxc copy` of a running instance produces an independent stopped copy
    # without touching the source's live filesystem or process state.
    _lxd_ready "$name" || return
    _lxd_host lxc copy "$name" "$base" || return
    # Snapshot as "checkpoint-pending", NOT "checkpoint": this call runs
    # before the scenario's Phase 2 (operator tuning) assertions, so if Phase
    # 2 fails after this point a real checkpoint must not already exist for a
    # RED smoke run (review §1a.2). lxd_promote_checkpoint renames pending ->
    # checkpoint as literally the scenario's last act, after every assertion
    # has passed. lxd_fork and lxd_base_for_candidate only ever look for a
    # snapshot named "checkpoint" (see their grep), so a pending-only base is
    # invisible to every fork/reuse path until promoted.
    _lxd_host lxc snapshot "$base" checkpoint-pending || return
    _lxd_host lxc config set "$base" user.statbus.candidate "$tag" || return
    _lxd_host lxc config set "$base" user.statbus.producer smoke || return
    _lxd_host lxc config set "$base" user.statbus.run_id "$run_id" || return
    _lxd_mark "smoke created $base/checkpoint-pending from real install $name (source left running)"
}
# Called as the scenario's LAST act, after every Phase 2 assertion has
# passed. Turns a provisional checkpoint into the one forks/base-reuse will
# actually see. A scenario that fails after lxd_snapshot_installed but before
# this call leaves only checkpoint-pending: no fork accepts it, and the next
# attempt's rerun-safe replace (above) cleans it up.
lxd_promote_checkpoint() {
    local tag=$1 base
    [ "$tag" = "$LXD_CANDIDATE" ] || return 2
    base=$(_lxd_name "$tag-installed-$tag-standalone")
    _lxd_host lxc info "$base" | grep -qE '^\| checkpoint-pending +\|' || {
        echo "REFUSE: $base has no checkpoint-pending snapshot to promote" >&2
        return 1
    }
    _lxd_host lxc rename "$base/checkpoint-pending" "$base/checkpoint" || return
    _lxd_mark "smoke promoted $base/checkpoint-pending -> checkpoint"
}
# VM-harness-compatible shims for direct scenario commands.
#
# arc_prepare_box (arc-helpers.sh) calls bootstrap_install_test_vm "$VM_NAME" ""
# — the VM harness's no-version contract: provision only, install happens
# separately via install_statbus_at_sha (below). Arc VM names (statbus-arc-*)
# never carry the statbus-recovery- prefix scenarios use, and have no backing
# scenario/<name>.sh file for lxd_checkpoint_for_scenario to resolve — the
# original shim below (unconditional ${1##statbus-recovery-} + scenario-slug
# fork) silently broke every arc (STATBUS-425 M3a review finding). An
# empty/absent second arg is the same "provision only, no scenario, no
# install yet" signal the VM harness itself uses; fork the plain
# hardened-nothing-installed base under a name derived from the arc's own
# VM_NAME, bypassing scenario resolution entirely.
bootstrap_install_test_vm() {
    if [ -z "${2:-}" ]; then
        [[ "$LXD_FORK_PREFIX" =~ ^[a-z][a-z0-9-]{0,12}$ ]] || return 2
        local slug=${1#statbus-arc-}
        [[ "$slug" =~ ^[a-zA-Z0-9-]+$ ]] || return 2
        local base name
        base=$(_lxd_name "$LXD_CANDIDATE-hardened-nothing-installed")
        name="$LXD_FORK_PREFIX-${LXD_CANDIDATE//[^a-zA-Z0-9-]/-}-arc-${slug}"
        _lxd_fork_from_base "$base" "$name" hardened-nothing-installed
        return
    fi
    lxd_fork "$LXD_CANDIDATE" "${1##statbus-recovery-}"
}
VM_EXEC() { local q; printf -v q '%q ' "$@"; _lxd_host lxc exec "$VM_NAME" -- sudo -i -u statbus bash -c "$q"; }
VM_ROOT_EXEC() { local q; printf -v q '%q ' "$@"; _lxd_host lxc exec "$VM_NAME" -- bash -c "$q"; }
cleanup_vm() {
    # review H1: the VM-harness cleanup_vm captures diagnostics on a nonzero
    # scenario rc before it deletes the box (vm-bootstrap.sh's cleanup_vm,
    # scenario_rc=${2:-${rc:-0}}). This LXD one deleted unconditionally, so
    # every red smoke/fault/arc scenario's `tmp/lxd-*-failure-*.log` (the
    # upload glob test-smoke.yaml already carries) was empty — a real
    # regression against Hetzner, not merely a missing nicety: the docker-ps
    # diagnostic added to lxd_capture_failure was unreachable from any
    # scenario-level failure, only from a builder's own install failure.
    # Every caller's trap is 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' (the
    # VM-harness shape scenarios/arcs already use) - $1 here IS that
    # positional VM_NAME echo, never the exit status, so the failure signal
    # this function needs is the global $rc the SAME trap set one clause
    # earlier, exactly as vm-bootstrap.sh's cleanup_vm defaults to it.
    local scenario_rc=${rc:-0}
    [ "${KEEP_VM:-0}" = 1 ] && return 0
    [ "${LXD_OWNED_BY_THIS_RUN:-0}" = 1 ] || return 0
    case "$VM_NAME" in
        "$LXD_FORK_PREFIX-${LXD_CANDIDATE//[^a-zA-Z0-9-]/-}-"*)
            [ "$scenario_rc" = 0 ] || lxd_capture_failure "$VM_NAME" || true
            _lxd_host lxc delete "$VM_NAME" --force
            ;;
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
    _lxd_push "/root/s2-install-script-$$" "$name$dest"
    _lxd_host lxc exec "$name" -- chmod 0755 "$dest"
    rm -f "$src"
}
VM_SCRIPT() {
    local local_path=$1 remote_path; shift
    remote_path="/tmp/vm-script-$(basename "$local_path")-$$.sh"
    _lxd_upload "$local_path" "/root/s2-vm-script-$$.sh"
    _lxd_push "/root/s2-vm-script-$$.sh" "$VM_NAME$remote_path"
    _lxd_host lxc exec "$VM_NAME" -- chmod 0755 "$remote_path"
    VM_EXEC bash "$remote_path" "$@"
}
VM_SCRIPT_INLINE() {
    local label=$1 path remote; shift
    [[ "$label" =~ ^[a-zA-Z0-9-]+$ ]] || return 2
    path=$(mktemp "$LXD_LOG_DIR/s2-inline-${label}-XXXXXX") || return
    cat > "$path"
    remote="/home/statbus/s2-inline-${label}-$$.sh"
    _lxd_upload "$path" "/root/s2-inline-${label}-$$.sh"
    _lxd_push "/root/s2-inline-${label}-$$.sh" "$VM_NAME$remote" >/dev/null 2>&1
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
_lxd_install_exit() {
    local rc=$1
    if [ "$rc" -ne 0 ]; then
        echo "  FAILURE CLASS: remote-stage-failed[install] exit=$rc" >&2
    fi
    return "$rc"
}
install_statbus_in_vm() {
    local name=$1 log="$HARNESS_ROOT/tmp/install-recovery-$1-install.log" installed commit rc
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
if [ -f /tmp/env-credentials ]; then
    install -m 0600 /tmp/env-credentials "$HOME/statbus/.env.credentials"
fi
cp /tmp/users.yml "$HOME/statbus/.users.yml"
STATBUS_MIN_DISK_GB=5 GIT_NETWORK_MAX_ATTEMPTS=8 GIT_NETWORK_RETRY_DELAY_S=45 DOCKER_PULL_MAX_ATTEMPTS=5 DOCKER_PULL_RETRY_DELAY_S=30 bash /tmp/statbus-install.sh --commit "$1" --trust-github-user jhf
REMOTE
        rc=${PIPESTATUS[0]}
        _lxd_install_exit "$rc"
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
    rc=${PIPESTATUS[0]}
    _lxd_install_exit "$rc"
}
install_statbus_at_sha() {
    local name=$1 sha=$2 tag=${3:-} log="$HARNESS_ROOT/tmp/install-recovery-${1}-install.log" rc
    if [ -n "$tag" ]; then
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
export STATBUS_MIN_DISK_GB=5
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
        rc=${PIPESTATUS[0]}
        _lxd_install_exit "$rc"
        return
    fi
    # Two-arg form: arc-helpers.sh's arc_prepare_box calls
    # install_statbus_at_sha "$VM_NAME" "$BASE_SHA" (STATBUS-071's contract —
    # no release-tag argument at all; the VM harness's implementation
    # (vm-bootstrap.sh) makes $3 optional and installs A via the toolchain-free
    # per-commit statbus-sb image when absent). The original LXD shim required
    # $3 unconditionally (`${3:?tag required}`), so every arc hit "tag
    # required" here before ever reaching an assertion (STATBUS-425 M3a review
    # finding). Every arc except cross-version-rename-handoff-arc.sh runs
    # BASE_SHA=the candidate's own commit; that one pins a historical release
    # commit instead (PRE_RENAME_BASE_SHA). Branch on which case this is: a
    # release tag pointing exactly at $sha selects the historical-release
    # install path (that release's own sb-linux asset + its own install.sh,
    # matching _lxd_build_base_for_candidate's historical branch); otherwise
    # $sha must be the candidate itself, installed via its per-commit image
    # (matches install_statbus_in_vm's no-version branch exactly).
    VM_EXEC test ! -e /home/statbus/statbus || { echo 'FRESH checkout already exists' >&2; return 70; }
    local sha_tag
    sha_tag=$(git -C "$HARNESS_ROOT" tag --points-at "$sha" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' | head -n1 || true)
    if [ -n "$sha_tag" ] && [ "$sha_tag" != "$LXD_CANDIDATE" ]; then
        _lxd_mark "arc install_statbus_at_sha: historical base $sha_tag (${sha:0:8}) via its own released sb"
        _lxd_stage_candidate_install
        VM_SCRIPT_INLINE arc-historical-install "$sha_tag" "${HARNESS_DEPLOYMENT_MODE:-standalone}" "${HARNESS_NO_CUSTOM_CERT:-0}" <<REMOTE 2>&1 | tee -a "$log"
#!/usr/bin/env bash
set -e
for attempt in 1 2 3 4 5 6 7 8; do
    if curl -fsSL https://github.com/statisticsnorway/statbus/releases/download/$sha_tag/sb-linux-amd64 -o ~/sb.tmp; then break; fi
    echo "GitHub sb-linux download retry \$attempt/8" >&2
    [ "\$attempt" -eq 8 ] && exit 1
    rm -f ~/sb.tmp; sleep 45
done
chmod +x ~/sb.tmp
for attempt in 1 2 3 4 5 6 7 8; do
    if git clone --quiet --depth 50 --branch $sha_tag https://github.com/statisticsnorway/statbus.git ~/statbus; then break; fi
    echo "GitHub clone retry \$attempt/8" >&2
    [ "\$attempt" -eq 8 ] && exit 1
    rm -rf ~/statbus; sleep 45
done
mv ~/sb.tmp ~/statbus/sb
cd ~/statbus
if [ "\$2" = standalone ] && [ "\$3" != 1 ]; then
    install -d -m 0755 caddy/data/custom-certs
    install -m 0644 ~/harness-certs/domain.crt caddy/data/custom-certs/domain.crt
    install -m 0600 ~/harness-certs/domain.key caddy/data/custom-certs/domain.key
fi
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
REMOTE
        rc=${PIPESTATUS[0]}
        _lxd_install_exit "$rc"
        return
    fi
    [ "$sha" = "$(git -C "$HARNESS_ROOT" rev-parse "$LXD_CANDIDATE^{commit}")" ] || {
        echo "REFUSE: install_statbus_at_sha with no tag needs sha=candidate commit or a release-tagged historical commit; got ${sha:0:8} (candidate ${LXD_CANDIDATE})" >&2
        return 2
    }
    _lxd_stage_candidate_install
    VM_SCRIPT_INLINE arc-head-install "$sha" "${HARNESS_DEPLOYMENT_MODE:-standalone}" "${HARNESS_NO_CUSTOM_CERT:-0}" <<'REMOTE' 2>&1 | tee -a "$log"
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
if [ -f /tmp/env-credentials ]; then
    install -m 0600 /tmp/env-credentials "$HOME/statbus/.env.credentials"
fi
cp /tmp/users.yml "$HOME/statbus/.users.yml"
STATBUS_MIN_DISK_GB=5 GIT_NETWORK_MAX_ATTEMPTS=8 GIT_NETWORK_RETRY_DELAY_S=45 DOCKER_PULL_MAX_ATTEMPTS=5 DOCKER_PULL_RETRY_DELAY_S=30 bash /tmp/statbus-install.sh --commit "$1" --trust-github-user jhf
REMOTE
    rc=${PIPESTATUS[0]}
    _lxd_install_exit "$rc"
}
