#!/bin/bash
# vm-bootstrap.sh — Hetzner Cloud bootstrap helper for install recovery tests.
#
# Provisions ephemeral Hetzner Cloud VMs (CX23, IPv4, hel1) for the per-scenario
# harness. Replaces the previous Multipass-on-macOS implementation, which kept
# breaking on vmnet bridge state (no recovery without `sudo reboot`).
#
# Sourced by test/install-recovery/scenarios/*.sh. Provides:
#
#   bootstrap_install_test_vm <vm_name> [install_version]
#       Provision a fresh Hetzner CX23 VM, run the project hardening script,
#       create the statbus user, set up linger so systemctl --user works.
#       Sets globals VM_IP, VM_EXEC, STATBUS_UID.
#
#       install_version: empty → uses locally-built `sb` binary
#                        v2026.05.0-rc.X → downloaded inside the VM
#
#   install_statbus_in_vm <vm_name> [install_version]
#       Run `./sb install` inside an already-bootstrapped VM. Returns the
#       install command's exit status.
#
#   reset_vm_state <vm_name>
#       Reimage the existing VM via `hcloud server rebuild` (~30s, same IP)
#       and re-run hardening. Use between scenarios in approach-B to amortise
#       a single 1-hour billing window across the whole harness run. State
#       reset is at the OS-disk level — no leftover postgres/docker state.
#
#   cleanup_vm <vm_name>
#       Delete the VM. KEEP_VM=1 leaves it running (€0.0072/hr) for debugging.
#
#   $VM_EXEC            ssh prefix to run as the statbus user inside the VM.
#                       Sources .profile so XDG_RUNTIME_DIR is set for
#                       systemctl --user.
#   $VM_IP              VM's public IPv4 address.
#   $STATBUS_UID        Numeric UID of the statbus user inside the VM.
#
# Cost model: one CX23 in hel1 = €0.0064/hr + €0.0008/hr for primary IPv4 =
# €0.0072/hr. Hetzner bills hourly with 1-hour minimum (no per-minute), so
# the cost-optimal pattern is one VM per harness run with reset_vm_state
# between scenarios. KEEP_VM=1 charges €0.17/day if you forget to clean up.
#
# Safety: all VM operations refuse names not starting with $HCLOUD_NAME_PREFIX
# (default "statbus-recovery-"). This protects the production niue VM, which
# lives in the same Hetzner project as the test VMs.

set -euo pipefail

HARNESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$HARNESS_LIB_DIR/../../.." && pwd)"

# Load HCLOUD_TOKEN from .env.credentials if not in env.
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    if [ -f "$HARNESS_ROOT/.env.credentials" ]; then
        # shellcheck disable=SC2046
        export $(grep '^HCLOUD_TOKEN=' "$HARNESS_ROOT/.env.credentials" | head -1)
    fi
fi
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo "ERROR: HCLOUD_TOKEN not set; expected in env or .env.credentials" >&2
    return 1 2>/dev/null || exit 1
fi

HCLOUD_SERVER_TYPE="${HCLOUD_SERVER_TYPE:-cx23}"
HCLOUD_LOCATION="${HCLOUD_LOCATION:-hel1}"
HCLOUD_IMAGE="${HCLOUD_IMAGE:-ubuntu-24.04}"
HCLOUD_SSH_KEY="${HCLOUD_SSH_KEY:-jorgen@veridit.no}"
HCLOUD_NAME_PREFIX="${HCLOUD_NAME_PREFIX:-statbus-recovery-}"

mkdir -p "$HARNESS_ROOT/tmp"

# Shared ssh options for ephemeral test VMs. Host-key verification is
# explicitly OFF — these VMs live for minutes and Hetzner recycles IPv4s
# across instances, so accept-new fails the first time an IP gets reused.
# Threat model: MITM on first connect to a freshly-provisioned Hetzner VM
# inside Hetzner's hel1 datacenter. Negligible for a test harness whose
# secrets are confined to a throwaway VM that gets deleted on completion.
#
# Keepalives matter: `./sb install` can pull GB of docker images with no
# stdout for minutes at a time. Without keepalives, intermediate NAT /
# firewall middleboxes drop the TCP connection, sshd back-end keeps
# running on the VM, and we get exit 255 with a partial transcript.
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o LogLevel=ERROR
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=10
    -o ControlMaster=no
    -o ControlPath=none
)

_check_name_safety() {
    local name="$1"
    case "$name" in
        "$HCLOUD_NAME_PREFIX"*) return 0 ;;
        *)
            echo "REFUSE: VM name '$name' does not start with prefix '$HCLOUD_NAME_PREFIX'." >&2
            echo "       Safety guard prevents accidental deletion of production VMs (niue etc) in the same Hetzner project." >&2
            return 1
            ;;
    esac
}

_wait_for_ssh() {
    local ip="$1" max="${2:-90}"
    local i
    for i in $(seq 1 "$max"); do
        if ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=2 root@"$ip" echo ok 2>/dev/null | grep -q "^ok$"; then
            echo "  SSH up after ${i}s"
            return 0
        fi
        sleep 1
    done
    echo "  SSH did not come up within ${max}s" >&2
    return 1
}

# Run a long shell command on the VM inside a detached tmux session, then
# poll for completion via reconnecting ssh. Survives mobile/flaky links —
# even if every individual ssh roundtrip fails, the next one resumes from
# the logfile on the VM. The bash command itself runs as the statbus user.
#
# Usage:
#   _run_long_via_tmux <ip> <session-name> <bash-command>
# Side effects:
#   /tmp/<session>.log   — full stdout+stderr
#   /tmp/<session>.exit  — exit code of the bash command (written after)
# Returns:
#   the bash command's exit code (or 254 if we couldn't even poll)
#
# Tunable: LONG_CMD_MAX_MIN (default 45) — overall time budget in minutes.
_run_long_via_tmux() {
    local ip="$1" session="$2" cmd="$3"
    local max_min="${LONG_CMD_MAX_MIN:-45}"
    local poll_secs=15
    local max_iter=$(( max_min * 60 / poll_secs ))

    # Ensure tmux is installed (idempotent — installed by hardening normally).
    ssh "${SSH_OPTS[@]}" root@"$ip" \
        'command -v tmux >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1' \
        || true

    # Launch the command in a detached tmux session running as statbus.
    # Wrap with exit-code capture: bash -c '<cmd>; echo $? > /tmp/<session>.exit'
    # The outer redirection > /tmp/<session>.log captures everything.
    ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/${session}.exit /tmp/${session}.log
        sudo -u statbus tmux new-session -d -s ${session} \\
            'bash -lc \"( ${cmd} ) > /tmp/${session}.log 2>&1; echo \\\$? > /tmp/${session}.exit\"'
    " || {
        echo "  ERROR: could not start tmux session ${session} on $ip" >&2
        return 254
    }

    # Poll for completion. Each poll is a fresh ssh, so transient drops don't
    # block progress. Show recent log tail so it doesn't look like nothing's
    # happening.
    local i seen_lines=0
    for ((i = 0; i < max_iter; i++)); do
        # Test for completion sentinel.
        if ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/${session}.exit" 2>/dev/null; then
            break
        fi
        # Show new log lines since last check (line-count tracking).
        local cur_lines
        cur_lines=$(ssh "${SSH_OPTS[@]}" root@"$ip" "wc -l < /tmp/${session}.log 2>/dev/null" 2>/dev/null | tr -d ' ')
        if [ -n "$cur_lines" ] && [ "$cur_lines" -gt "$seen_lines" ] 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur_lines - seen_lines)) /tmp/${session}.log" 2>/dev/null
            seen_lines="$cur_lines"
        fi
        sleep "$poll_secs"
    done

    # Fetch any remaining log tail.
    local cur_lines
    cur_lines=$(ssh "${SSH_OPTS[@]}" root@"$ip" "wc -l < /tmp/${session}.log 2>/dev/null" 2>/dev/null | tr -d ' ')
    if [ -n "$cur_lines" ] && [ "$cur_lines" -gt "$seen_lines" ] 2>/dev/null; then
        ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur_lines - seen_lines)) /tmp/${session}.log" 2>/dev/null
    fi

    # Did it actually finish?
    if ! ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/${session}.exit" 2>/dev/null; then
        echo "  TIMEOUT after ${max_min}min — tmux session '${session}' still running." >&2
        echo "    Attach for live view: ssh root@$ip 'sudo -u statbus tmux attach -t ${session}'" >&2
        return 254
    fi

    local exit_code
    exit_code=$(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/${session}.exit" 2>/dev/null | tr -d ' \n')
    [ -z "$exit_code" ] && exit_code=255
    return "$exit_code"
}

# Run the project hardening + statbus user setup on a freshly-booted VM.
# Idempotent — safe to call again after a rebuild.
_apply_hardening() {
    local ip="$1" sb_binary="${2:-}"

    echo "  waiting for cloud-init..."
    ssh "${SSH_OPTS[@]}" root@"$ip" 'cloud-init status --wait' 2>/dev/null || true

    echo "  transferring setup files..."
    [ -n "$sb_binary" ] && {
        scp -O "${SSH_OPTS[@]}" "$sb_binary" root@"$ip":/tmp/sb
        ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/sb'
    }
    scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/ops/setup-ubuntu-lts-24.sh" root@"$ip":/tmp/setup.sh
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/setup.sh'

    local env_config_file users_file
    env_config_file=$(mktemp)
    cat > "$env_config_file" << 'ENVCONFIG'
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=development
SITE_DOMAIN=statbus-test.local
STATBUS_URL=https://statbus-test.local
BROWSER_REST_URL=https://statbus-test.local
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
UPGRADE_CHANNEL=stable
ENVCONFIG
    scp -O "${SSH_OPTS[@]}" "$env_config_file" root@"$ip":/tmp/env-config
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/env-config'
    rm -f "$env_config_file"

    users_file=$(mktemp)
    cat > "$users_file" << 'USERS'
- email: test@statbus.org
  password: test-install-password-2026
  role: admin_user
  display_name: Admin
USERS
    scp -O "${SSH_OPTS[@]}" "$users_file" root@"$ip":/tmp/users.yml
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/users.yml'
    rm -f "$users_file"

    ssh "${SSH_OPTS[@]}" root@"$ip" 'cat > /root/.setup-ubuntu.env << EOF
ADMIN_EMAIL="test@statbus.org"
GITHUB_USERS="jhf"
EXTRA_LOCALES=""
CADDY_PLUGINS=""
EOF'

    echo "  === Stage: Hardening (detached tmux for survivability) ==="
    local logfile="$HARNESS_ROOT/tmp/install-recovery-${VM_NAME:-unknown}-bootstrap.log"
    # Hardening runs as root, not statbus. Override the helper's user briefly
    # by running it directly (tmux must run AS root here since /tmp/setup.sh
    # needs root, and the statbus user doesn't exist yet at this point).
    ssh "${SSH_OPTS[@]}" root@"$ip" \
        'command -v tmux >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1' \
        || true
    ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/harden.exit /tmp/harden.log
        tmux new-session -d -s harden 'bash /tmp/setup.sh --non-interactive > /tmp/harden.log 2>&1; echo \$? > /tmp/harden.exit'
    "
    local max_iter=$(( ${LONG_CMD_MAX_MIN:-45} * 60 / 15 )) i=0 seen=0
    for ((i=0; i<max_iter; i++)); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
            break
        fi
        local cur
        cur=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'wc -l < /tmp/harden.log 2>/dev/null' 2>/dev/null | tr -d ' ')
        if [ -n "$cur" ] && [ "$cur" -gt "$seen" ] 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur - seen)) /tmp/harden.log" 2>/dev/null | tee -a "$logfile"
            seen="$cur"
        fi
        sleep 15
    done
    if ! ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
        echo "  HARDENING TIMEOUT after ${LONG_CMD_MAX_MIN:-45}min" >&2
        return 1
    fi
    local harden_exit
    harden_exit=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'cat /tmp/harden.exit' 2>/dev/null | tr -d ' \n')
    if [ "$harden_exit" != "0" ]; then
        echo "  HARDENING FAILED with exit code: $harden_exit" >&2
        return 1
    fi

    echo "  creating statbus user + linger..."
    ssh "${SSH_OPTS[@]}" root@"$ip" '
        useradd -m -s /bin/bash -G docker statbus 2>/dev/null || true
        usermod -aG docker statbus 2>/dev/null || true
        loginctl enable-linger statbus 2>/dev/null || true
        grep -q XDG_RUNTIME_DIR /home/statbus/.profile 2>/dev/null \
            || echo "export XDG_RUNTIME_DIR=/run/user/\$(id -u)" >> /home/statbus/.profile
    '

    echo "  fetching personal SSH keys from GitHub (ed25519 only)..."
    ssh "${SSH_OPTS[@]}" root@"$ip" '
        # Root authorized_keys (already seeded by Hetzner for statbus-ci; append personal keys)
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys

        # Statbus user authorized_keys
        mkdir -p /home/statbus/.ssh && chmod 700 /home/statbus/.ssh
        touch /home/statbus/.ssh/authorized_keys && chmod 600 /home/statbus/.ssh/authorized_keys
        chown statbus:statbus /home/statbus/.ssh /home/statbus/.ssh/authorized_keys

        # jhf
        if keys=$(curl -sf https://github.com/jhf.keys | grep '"'"'^ssh-ed25519'"'"'); then
            echo "$keys" >> /root/.ssh/authorized_keys
            echo "$keys" >> /home/statbus/.ssh/authorized_keys
        else
            echo "WARNING: could not fetch jhf GitHub keys (network blip); skipping" >&2
        fi

        # hhssb
        if keys=$(curl -sf https://github.com/hhssb.keys | grep '"'"'^ssh-ed25519'"'"'); then
            echo "$keys" >> /root/.ssh/authorized_keys
            echo "$keys" >> /home/statbus/.ssh/authorized_keys
        else
            echo "WARNING: could not fetch hhssb GitHub keys (network blip); skipping" >&2
        fi

        # Propagate CI key: Hetzner seeds the statbus-ci key to root only.
        # After the curl loops above, root has: Hetzner CI key + personal keys.
        # Copy everything to statbus and dedup so `ssh statbus@vm` works from
        # CI and from any key that can reach root (canonical operator model:
        # the same key that reaches root also reaches the statbus operator user).
        sort -u /root/.ssh/authorized_keys > /tmp/.ak_merge
        cat /tmp/.ak_merge > /home/statbus/.ssh/authorized_keys
        rm -f /tmp/.ak_merge
        chown statbus:statbus /home/statbus/.ssh/authorized_keys
        chmod 600 /home/statbus/.ssh/authorized_keys
    '

    STATBUS_UID=$(ssh "${SSH_OPTS[@]}" root@"$ip" id -u statbus)
    local i
    for i in $(seq 1 20); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID systemctl --user is-system-running" 2>/dev/null | grep -qE "running|degraded"; then
            break
        fi
        sleep 0.5
    done

    # Per-VM exec function. CALLERS MUST USE `VM_EXEC ...` (not `$VM_EXEC`).
    # OpenSSH joins multi-arg commands with bare spaces and DOES NOT
    # re-quote — so `$VM_EXEC bash -c "long string"` arrives on the VM
    # as `bash -c long -s -m 3 ...` (mangled). The function path uses
    # printf %q to escape each arg before assembling one quoted remote
    # command string for ssh.
    VM_IP="$ip"
}

VM_EXEC() {
    local quoted_args
    quoted_args=$(printf '%q ' "$@")
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus -- $quoted_args"
}

bootstrap_install_test_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    _check_name_safety "$vm_name" || return 1
    VM_NAME="$vm_name"

    if ! command -v hcloud >/dev/null 2>&1; then
        echo "ERROR: hcloud CLI not installed. brew install hcloud" >&2
        return 1
    fi

    # Build sb binary locally if no release was specified.
    # CI sets STATBUS_SB_BINARY to a pre-extracted binary (avoids a fresh build).
    local sb_binary=""
    if [ -z "$install_version" ]; then
        if [ -n "${STATBUS_SB_BINARY:-}" ]; then
            if [ ! -f "$STATBUS_SB_BINARY" ]; then
                echo "ERROR: STATBUS_SB_BINARY is set but file does not exist: $STATBUS_SB_BINARY" >&2
                return 1
            fi
            sb_binary="$STATBUS_SB_BINARY"
            echo "Using pre-built sb binary: $sb_binary"
        else
            local build_target="linux/amd64"  # Hetzner CX23 is x86_64
            echo "Building sb for $build_target..."
            (cd "$HARNESS_ROOT" && ./dev.sh build-sb "$build_target")
            sb_binary="${HARNESS_ROOT}/sb-${build_target//\//-}"
        fi
    fi

    # Refuse if the VM already exists — another test-install run may be in progress.
    if hcloud server describe "$vm_name" >/dev/null 2>&1; then
        echo "ERROR: VM '$vm_name' already exists. Another test-install run may be in progress (CI or local)." >&2
        echo "  Inspect:  hcloud server describe $vm_name" >&2
        echo "  If stale: hcloud server delete $vm_name" >&2
        return 1
    fi

    echo "Provisioning Hetzner $HCLOUD_SERVER_TYPE in $HCLOUD_LOCATION: $vm_name"
    hcloud server create \
        --name "$vm_name" \
        --type "$HCLOUD_SERVER_TYPE" \
        --image "$HCLOUD_IMAGE" \
        --location "$HCLOUD_LOCATION" \
        --ssh-key "$HCLOUD_SSH_KEY" \
        > /dev/null

    VM_IP=$(hcloud server ip "$vm_name")
    echo "  VM_IP=$VM_IP"

    _wait_for_ssh "$VM_IP" 90
    _apply_hardening "$VM_IP" "$sb_binary"

    echo "VM $vm_name bootstrap complete."
}

# Reset VM to fresh OS state using hcloud server rebuild. Same server, same
# IP, fresh disk image. ~30s + hardening. The cheap path for approach-B.
reset_vm_state() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1
    VM_NAME="$vm_name"

    if ! hcloud server describe "$vm_name" >/dev/null 2>&1; then
        echo "ERROR: $vm_name does not exist; cannot reset. Call bootstrap_install_test_vm first." >&2
        return 1
    fi

    echo "Reimaging $vm_name to fresh $HCLOUD_IMAGE (server id and IP preserved)..."
    hcloud server rebuild "$vm_name" --image "$HCLOUD_IMAGE" > /dev/null

    VM_IP=$(hcloud server ip "$vm_name")
    echo "  VM_IP=$VM_IP (unchanged)"

    # Caller pre-built sb_binary is already cached in $HARNESS_ROOT —
    # rebuild only wipes the VM disk, not the host workspace.
    local sb_binary=""
    local build_target="linux/amd64"
    sb_binary="${HARNESS_ROOT}/sb-${build_target//\//-}"
    [ -f "$sb_binary" ] || sb_binary=""

    _wait_for_ssh "$VM_IP" 90
    _apply_hardening "$VM_IP" "$sb_binary"

    echo "VM $vm_name reset complete."
}

# Run install inside a bootstrapped VM.
#   install_statbus_in_vm <vm_name>                  → use locally-built /tmp/sb
#   install_statbus_in_vm <vm_name> v2026.05.0-rc.X  → download from release
# Caller may pre-set SB_INSTALL_EXTRA_ARGS (e.g. "--recovery=auto").
install_statbus_in_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    local extra_args="${SB_INSTALL_EXTRA_ARGS:-}"
    _check_name_safety "$vm_name" || return 1

    local ip
    ip=$(hcloud server ip "$vm_name")

    local install_script
    install_script=$(mktemp)
    if [ -z "$install_version" ]; then
        # Use the local repo's HEAD. ./sb install verifies signatures against
        # HEAD via `git verify-commit`, so the VM needs a real .git directory
        # at the matching commit — not just the binary. GitHub allows fetch
        # by SHA, so a shallow clone of master + targeted fetch is enough.
        local local_commit
        local_commit=$(cd "$HARNESS_ROOT" && git rev-parse HEAD)

        # upload_sb_to_vm: builds if absent, scps to /tmp/sb, chmods 0755,
        # and atomically swaps into ~/statbus/sb via mv-then-cp (no ETXTBSY
        # even when the upgrade service is running from Phase 1).
        upload_sb_to_vm "$vm_name" || { rm -f "$install_script"; return 1; }

        cat > "$install_script" << SCRIPT
set -e
if [ ! -d ~/statbus/.git ]; then
    git clone --depth 50 https://github.com/statisticsnorway/statbus.git ~/statbus
fi
cd ~/statbus
# Extend the tracked-branch list to include db-seed so the install's own
# 'git fetch origin db-seed' creates refs/remotes/origin/db-seed (a single-
# branch clone — see the tagged-version branch below — would otherwise
# fetch the data but never create the remote-tracking ref, leaving the
# seed shortcut silently disabled and forcing migrations-from-scratch).
# Idempotent — safe to add repeatedly across scenarios that reuse the VM.
git remote set-branches --add origin db-seed
if ! git cat-file -e $local_commit 2>/dev/null; then
    echo "Fetching local HEAD commit $local_commit from origin..."
    git fetch --depth 1 origin $local_commit || {
        echo "FATAL: commit $local_commit is not on origin. Push it before running the harness." >&2
        exit 1
    }
fi
git checkout $local_commit
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf $extra_args
SCRIPT
    else
        cat > "$install_script" << SCRIPT
set -e
VM_ARCH=\$(uname -m)
case "\$VM_ARCH" in
    x86_64)        GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *)             echo "Unsupported: \$VM_ARCH"; exit 1 ;;
esac
SB_URL="https://github.com/statisticsnorway/statbus/releases/download/${install_version}/sb-linux-\${GOARCH}"
curl -fsSL "\$SB_URL" -o ~/sb.tmp
chmod +x ~/sb.tmp
if [ ! -d ~/statbus/.git ]; then
    git clone --depth 1 --branch ${install_version} https://github.com/statisticsnorway/statbus.git ~/statbus
fi
mv ~/sb.tmp ~/statbus/sb
cd ~/statbus
# A '--depth 1 --branch <tag>' clone is implicitly single-branch — the
# refspec is narrowed to just the tag's branch, so a subsequent
# 'git fetch origin db-seed' downloads data but does NOT create
# refs/remotes/origin/db-seed. ./sb install's seed-fetch step then sees
# 'fatal: invalid object name origin/db-seed' on the git-show that
# follows, falls back to migrations-from-scratch (~30 min on a fresh DB),
# and any harness scenario spends its time replaying migrations instead
# of exercising the recovery code path under test. Extending the
# tracked-branch list before the install fixes the ref creation.
git remote set-branches --add origin db-seed
cp /tmp/env-config .env.config 2>/dev/null || true
cp /tmp/users.yml .users.yml 2>/dev/null || true
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf $extra_args
SCRIPT
    fi

    scp -O "${SSH_OPTS[@]}" "$install_script" root@"$ip":/tmp/install.sh
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/install.sh'
    rm -f "$install_script"

    # Run the install in a detached tmux session as statbus, poll for
    # completion. Survives mobile-internet drops — even if every poll
    # roundtrip fails, the install keeps running on the VM and we resume
    # from the logfile on next poll success.
    local install_log="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"
    _run_long_via_tmux "$ip" "install" "bash /tmp/install.sh" \
        | tee -a "$install_log"
    return ${PIPESTATUS[0]}
}

# Upload the local HEAD sb binary to /tmp/sb on the VM.
#
# Needed by any scenario that bootstraps WITH an INSTALL_VERSION (the
# version-branch bootstrap does NOT upload /tmp/sb — it fetches the
# release binary directly into ~/statbus/sb) but then runs a custom
# inline install script whose first action is `cp /tmp/sb ./sb`.  Without
# this upload that cp fails, set -e exits the subshell before ./sb install
# ever runs, and no migrate/upgrade process appears.
#
# install_statbus_in_vm's no-version branch already does this upload
# internally (vm-bootstrap.sh lines 472-484).  Scenarios that bypass
# install_statbus_in_vm with their own inline scripts call this helper
# explicitly instead.
#
# Always rebuilds sb-linux-amd64 from the current HEAD unless STATBUS_SB_BINARY
# is set (CI pre-extraction bypass).  The "build if absent" gate was dropped
# because a stale binary (built from an older commit) embeds an older commitSHA
# via ldflags; stalenessGuard in cli/cmd/root.go:85 detects the mismatch and
# triggers self-heal rebuild+re-exec on the VM — but the VM has no Go, so
# exit 127 aborts the scenario before the inject site is ever reached.
# Rebuilding here adds ~10-15s (CGO_ENABLED=0 cross-compile) once per
# upload_sb_to_vm call, which is negligible vs the ~10-15 min scenario wall-clock.
# STATBUS_SB_BINARY overrides the binary path (used by CI pre-extraction).
upload_sb_to_vm() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1
    local ip
    ip=$(hcloud server ip "$vm_name")
    local sb_binary="${STATBUS_SB_BINARY:-}"
    if [ -z "$sb_binary" ]; then
        echo "  Building sb-linux-amd64 from HEAD (always rebuild to prevent staleness)..."
        (cd "$HARNESS_ROOT" && ./dev.sh build-sb linux/amd64)
        sb_binary="${HARNESS_ROOT}/sb-linux-amd64"
    fi
    if [ ! -f "$sb_binary" ]; then
        echo "FATAL: sb binary not found at $sb_binary after build attempt" >&2
        return 1
    fi

    # Instrument every scp/ssh below so failures are unmissable.
    # Two-layer capture:
    #  (a) LogLevel=VERBOSE on each call — SSH_OPTS has LogLevel=ERROR which
    #      suppresses transport-layer error messages (e.g. "Connection reset
    #      by peer" at INFO/VERBOSE) before they reach stderr.  Override to
    #      VERBOSE so the full SSH diagnostic appears.
    #  (b) 2>>"$log" captures ALL remaining stderr, including scp-protocol
    #      errors that bypass the SSH log level.
    # set -x traces every command + its expansion; yes, noisy — that's the
    # point right now.
    local scp_log="/tmp/upload-sb-scp-$$.log"
    local ssh_log="/tmp/upload-sb-ssh-$$.log"
    echo "  upload_sb_to_vm: stderr → $scp_log (scp) / $ssh_log (ssh)"
    set -x

    local scp_rc=0
    # -O forces the legacy SCP wire protocol instead of the SFTP subsystem.
    # macOS OpenSSH 10.0+ defaults to SFTP-based scp; its channel flow-control
    # implementation deadlocks at ~4–5 MB on Mac→Linux transfers, silently
    # leaving a partial file.  The legacy -O path uses a direct pipe and
    # transfers reliably at any size.  Empirically verified: scp without -O
    # stalls at ~5 MB; scp -O transfers the full 14 MB binary in one pass.
    scp -O "${SSH_OPTS[@]}" -o LogLevel=VERBOSE "$sb_binary" root@"$ip":/tmp/sb \
        2>"$scp_log" || scp_rc=$?
    if [ "$scp_rc" -ne 0 ]; then
        set +x
        echo "SCP FAILED (exit $scp_rc) uploading $(basename "$sb_binary") → root@${ip}:/tmp/sb" >&2
        echo "  Full stderr ($scp_log):" >&2
        cat "$scp_log" >&2
        return 1
    fi

    local chmod_rc=0
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" 'chmod 0755 /tmp/sb' \
        2>"$ssh_log" || chmod_rc=$?
    if [ "$chmod_rc" -ne 0 ]; then
        set +x
        echo "SSH chmod FAILED (exit $chmod_rc)" >&2
        cat "$ssh_log" >&2
        return 1
    fi

    # Atomically swap the binary into ~/statbus/sb using the production
    # mv-then-cp pattern (mirrors replaceBinaryOnDisk in service.go):
    #   mv changes the OLD inode's path — the running process keeps reading
    #   its old inode and exits normally.
    #   cp writes to a FRESH inode at the ./sb path — no ETXTBSY.
    # Without this, a naive `cp /tmp/sb ./sb` in the install script hits
    # ETXTBSY whenever the statbus-upgrade service is running (Phase 1
    # leaves the service up; Phase 3's script runs while it's still live).
    local swap_rc=0
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" '
        dst=/home/statbus/statbus/sb
        if [ -f "$dst" ]; then
            mv "$dst" "${dst}.old" 2>/dev/null || true
        fi
        cp /tmp/sb "$dst"
        chmod +x "$dst"
        chown statbus:statbus "$dst"
        rm -f "${dst}.old"
    ' 2>>"$ssh_log" || swap_rc=$?
    if [ "$swap_rc" -ne 0 ]; then
        set +x
        echo "SSH atomic-swap FAILED (exit $swap_rc)" >&2
        echo "  Full stderr ($ssh_log):" >&2
        cat "$ssh_log" >&2
        return 1
    fi

    set +x
    echo "  /tmp/sb uploaded and atomically swapped into ~/statbus/sb ($vm_name)"
}

# Upload a harness install-script to the VM and chmod 0755 so that
# `sudo -u statbus bash /tmp/install-*.sh` can read it.
#
# Background: mktemp creates files with mode 0600; scp preserves that
# mode; the remote file therefore lands as root:root 0600. The statbus
# user cannot READ it, so `bash /tmp/install-*.sh` exits 126 (Permission
# denied) even though the invocation uses the `bash` prefix.  Forcing
# 0755 after scp makes the file world-readable and statbus-executable.
#
# Usage:
#   upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-cNN.sh
#
# The helper removes the local temp file after upload (replaces the
# caller's `rm -f "$INSTALL_SCRIPT"` pattern).
upload_install_script_to_vm() {
    local vm_name="$1"
    local src_path="$2"
    local dest_path="$3"
    _check_name_safety "$vm_name" || return 1
    local ip
    ip=$(hcloud server ip "$vm_name")
    scp -O "${SSH_OPTS[@]}" "$src_path" root@"$ip":"$dest_path"
    ssh "${SSH_OPTS[@]}" root@"$ip" "chmod 0755 $dest_path"
    rm -f "$src_path"
    echo "  $dest_path uploaded to VM ($vm_name)"
}

# Cleanup helper. KEEP_VM=1 leaves the VM running for debugging — accrues
# €0.0072/hr until you `hcloud server delete <name>`.
#
# KEEP_VM_ON_FAILURE=1 is an alias intended for diagnostic runs where you
# expect the scenario to fail and want the VM preserved for post-mortem.
# Semantically equivalent to KEEP_VM=1 — both unconditionally skip deletion
# when set.  Use KEEP_VM_ON_FAILURE=1 to make intent explicit in CI logs or
# local one-off debug runs; cleanup_vm does not receive the exit code so it
# cannot distinguish failure from success — that distinction is in the
# operator's hands.
#
# Post-mortem helpers:
#   ssh root@<ip>                         — root shell
#   ssh statbus@<ip>                      — operator user (has systemd bus)
#   ssh root@<ip> journalctl --user -u statbus-upgrade@test --no-pager
#   hcloud server delete <name>           — delete when done
cleanup_vm() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1
    if [ "${KEEP_VM:-0}" = "1" ] || [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ]; then
        local ip
        ip=$(hcloud server ip "$vm_name" 2>/dev/null || echo "?")
        local reason="KEEP_VM=1"
        [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ] && reason="KEEP_VM_ON_FAILURE=1"
        echo "$reason — leaving $vm_name running for post-mortem (€0.0072/hr)"
        echo "  ssh root@$ip"
        echo "  ssh statbus@$ip"
        echo "  journalctl: ssh root@$ip journalctl --user -u statbus-upgrade@test --no-pager -n 200"
        echo "  upload logs: /tmp/upload-sb-scp-*.log  /tmp/upload-sb-ssh-*.log"
        echo "  Delete when done: hcloud server delete $vm_name"
        return 0
    fi
    echo "Deleting VM: $vm_name"
    hcloud server delete "$vm_name" 2>/dev/null || true
}
