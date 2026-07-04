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
# Propagate ERR trap into functions and subshells sourced from this lib.
set -E
# Emit a one-line diagnostic whenever set -e fires so failure logs are
# self-explaining.  $LINENO and $BASH_COMMAND are correct in ERR context;
# they would be wrong inside the EXIT trap (which would report the trap's
# own line, not the failing command's line).
trap 'rc=$?; echo "✗ harness failure: rc=$rc at ${BASH_SOURCE[0]##*/}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

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
        tmux new-session -d -s harden 'bash /tmp/setup.sh --non-interactive --skip-stages=4 > /tmp/harden.log 2>&1; echo \$? > /tmp/harden.exit'
    "
    local max_iter=$(( ${LONG_CMD_MAX_MIN:-45} * 60 / 15 )) i=0 seen=0
    for ((i=0; i<max_iter; i++)); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
            break
        fi
        local cur
        cur=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'wc -l < /tmp/harden.log 2>/dev/null' 2>/dev/null | tr -d ' ') || true
        if [ -n "$cur" ] && [ "$cur" -gt "$seen" ] 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur - seen)) /tmp/harden.log" 2>/dev/null | tee -a "$logfile" || true
            seen="$cur"
        fi
        sleep 15
    done
    if ! ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
        echo "  HARDENING TIMEOUT after ${LONG_CMD_MAX_MIN:-45}min" >&2
        return 1
    fi
    local harden_exit
    harden_exit=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'cat /tmp/harden.exit' 2>/dev/null | tr -d ' \n') || true
    if [ "$harden_exit" != "0" ]; then
        echo "  HARDENING FAILED with exit code: '$harden_exit' (empty = SSH read failure)" >&2
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

    STATBUS_UID=$(ssh "${SSH_OPTS[@]}" root@"$ip" id -u statbus 2>/dev/null) || true
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
    #
    # TRAP (r13 autopsy, 2026-07-05, foreman-verified on a kept VM):
    # `sudo -i -u statbus -- ...` re-quotes the command line ITSELF before
    # handing it to statbus's login shell, and that re-quoting does not
    # reliably protect bare `$VARNAME` references (parens happen to survive
    # via a different escape; a lone `$` does not) — a `$` that must reach
    # the VM as LITERAL TEXT (e.g. building a shell script whose body
    # references `$SOME_VAR` for evaluation at a LATER, unrelated run) can
    # come back silently expanded to empty. Never pass such content as a
    # VM_EXEC/bash -c argument — write it to a local file (heredoc with a
    # QUOTED delimiter) and scp it to the VM instead; see
    # 3-postswap-resume-died-parked.sh's park-callback.sh transfer.
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
#   install_statbus_in_vm <vm_name>                  → run the REAL install.sh --channel edge
#   install_statbus_in_vm <vm_name> v2026.05.0-rc.X  → download from release
# Caller may pre-set SB_INSTALL_EXTRA_ARGS (e.g. "--recovery=auto").
#
# No-version EXIT CONTRACT (STATBUS-060):
#   install.sh exits 0 for BOTH success and rollback (./sb install rc=75 → install.sh
#   prints a rollback banner and exits 0). Catastrophic failures are non-zero.
#   Callers must use the upgrade row state (FINAL_STATE=failed|rolled_back) to
#   distinguish success from rollback — exit code alone is insufficient.
install_statbus_in_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    local extra_args="${SB_INSTALL_EXTRA_ARGS:-}"
    # No-seed mode (opt-in via SB_INSTALL_SKIP_SEED): force a full-migrations-from-tag
    # baseline so a real v<tag>→HEAD migration delta exists for the stall/kill injects
    # (the published seed is dumped at HEAD's migration level and would otherwise
    # collapse the delta). Pure harness-side, NO product change: withhold the
    # origin/db-seed tracked-branch so a RELEASE binary's git-branch seed
    # (db seed fetch → origin/db-seed) finds no ref and falls through to full
    # migrations. Default (unset) preserves the seed shortcut → passing scenarios
    # are unaffected.
    # NOTE: this reaches the RELEASE-binary (versioned) baseline only, whose seed is
    # git-branch-based. A HEAD-binary (no-version) install uses a Docker-image seed
    # (statbus-seed:<short>) that this does NOT disable — such a baseline instead
    # relies on a populated DB (checkSeedRestored's dbHasUserData R5 short-circuit,
    # install.go) so the seed step is skipped. No current no-seed scenario needs a
    # HEAD-binary no-seed baseline.
    local seed_branch_cmd="git remote set-branches --add origin db-seed"
    if [ -n "${SB_INSTALL_SKIP_SEED:-}" ]; then
        seed_branch_cmd="true  # SB_INSTALL_SKIP_SEED: origin/db-seed withheld (release-binary git-branch seed disabled → full migrations)"
    fi
    _check_name_safety "$vm_name" || return 1

    local ip
    ip=$(hcloud server ip "$vm_name")

    local install_script
    install_script=$(mktemp)
    if [ -z "$install_version" ]; then
        # STATBUS-060: run the REAL install.sh (operator path) with --channel edge.
        # This is the genuine operator recovery entrypoint (STATBUS-039: the operator's
        # only action is install.sh). install.sh --channel edge:
        #   RESCUE mode (~/statbus/.git exists): git fetch origin master → checkout
        #     current → procure binary via docker pull/build → ./sb install.
        #   Binary procurement: docker pull ghcr.io/statisticsnorway/statbus-sb:<short>
        #     (fast when image published); falls back to docker build -f cli/Dockerfile.sb
        #     (~3-5 min, no host Go needed).
        # install.sh exits 0 for both success and rollback; see EXIT CONTRACT above.
        #
        # Fork 1A: upload in-repo install.sh (matches HEAD, no curl network hop).
        # Fork 2D: --channel edge provides real binary procurement fidelity.
        # Fork 3: no 75-tolerance at call sites; outcome from upgrade row state only.

        # Upload the in-repo install.sh as /tmp/statbus-install.sh (NOT /tmp/install.sh —
        # the shared section below uploads the wrapper script to /tmp/install.sh and runs
        # `bash /tmp/install.sh`; using the same name would cause the wrapper to call itself).
        _wait_for_ssh "$ip" 30
        if [ -n "${SB_RECOVERY_REUSE_STAGED_BINARY:-}" ]; then
            # Mode B (architect): reuse the already-staged target ./sb (upload_sb_to_vm) instead
            # of install.sh --channel edge. --channel edge git-fetches origin/master + checks out
            # the MOVING tip + procures THAT binary, drifting past the scheduled target when master
            # advances mid-run (non-deterministic; abort scenarios assert binary-unchanged).
            # recoverFromFlag owns the working-tree checkout; on-disk ./sb is already the target →
            # deterministic + target-pinned recovery.
            cat > "$install_script" << SCRIPT
set -e
cd ~/statbus
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT
        else
            scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/install.sh" root@"$ip":/tmp/statbus-install.sh
            ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/statbus-install.sh'

            cat > "$install_script" << SCRIPT
set -e
# If ~/statbus/.git does not exist (no prior install), do a minimal clone first
# so install.sh always enters RESCUE mode (git update + binary procure + ./sb install).
# install.sh --channel edge FRESH would clone ~/statbus itself but would then call
# ./sb install WITHOUT .env.config in place — we must pre-place config files before
# install.sh's ./sb install step. The pre-clone ensures RESCUE mode so we control
# timing: config files land before ./sb install runs. Idempotent for RESCUE callers.
if [ ! -d ~/statbus/.git ]; then
    git clone --depth 50 https://github.com/statisticsnorway/statbus.git ~/statbus
    # Add db-seed refspec so install's own 'git fetch origin db-seed' creates the
    # remote-tracking ref (a single-branch shallow clone restricts the refspec).
    git -C ~/statbus remote set-branches --add origin db-seed
fi
# Pre-place config files: ./sb install (called by install.sh) needs .env.config.
# For RESCUE mode these survive install.sh's 'git checkout -B current origin/master'.
cp /tmp/env-config ~/statbus/.env.config
cp /tmp/users.yml ~/statbus/.users.yml
# Run the real install.sh (uploaded as /tmp/statbus-install.sh to avoid a naming
# conflict with the harness wrapper at /tmp/install.sh). Always in RESCUE mode
# (~/statbus/.git guaranteed above). --channel edge: fetches origin/master, procures
# HEAD binary via docker image (or build fallback), then calls ./sb install.
# Exits 0 for both success and rollback; catastrophic failures are non-zero.
STATBUS_MIN_DISK_GB=5 bash /tmp/statbus-install.sh --channel edge --trust-github-user jhf
SCRIPT
        fi
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
$seed_branch_cmd
cp /tmp/env-config .env.config 2>/dev/null || true
cp /tmp/users.yml .users.yml 2>/dev/null || true
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf $extra_args
SCRIPT
    fi

    # Wait for SSH to be responsive before uploading — bootstrap activity
    # (Homebrew installs, service starts) can leave sshd's accept queue
    # saturated for a few seconds, causing immediate "Operation timed out"
    # on the very next connection.
    _wait_for_ssh "$ip" 30
    scp -O "${SSH_OPTS[@]}" -o LogLevel=VERBOSE "$install_script" root@"$ip":/tmp/install.sh
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" 'chmod 0644 /tmp/install.sh'
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

# install_statbus_at_sha <vm_name> <sha> — fresh install pinned to an EXACT commit.
#
# The upgrade-arc harness (STATBUS-071) needs the baseline A = base_sha EXACTLY:
# the defect branch B is committed off base_sha, so the box must start AT base_sha
# for A→B to be a clean single-migration forward. install_statbus_in_vm cannot do
# this — its empty-version path installs master HEAD (drifts between fire and
# install) and its tag path downloads a release binary (no release is post-086,
# which the register/schedule arc requires). This helper is install.sh --channel
# edge pinned to <sha>: blobless full clone → checkout <sha> → toolchain-free
# binary procurement of statbus-sb:<short> (mirrors sbimage.ProcureShort:
# docker pull → create → cp /sb → rm → chmod) → ./sb install. The per-commit sb
# image was built by the master-push images.yaml run for <short> (the arc's
# image-wait gates on it).
#
# Relies on bootstrap_install_test_vm having already uploaded /tmp/env-config +
# /tmp/users.yml and applied OS setup (docker present). Same EXIT CONTRACT as the
# no-version install_statbus_in_vm: ./sb install rc=75 (rollback) → install exits
# 0; callers decide success from the upgrade/install row state, not the exit code.
install_statbus_at_sha() {
    local vm_name="$1"
    local sha="$2"
    local short="${sha:0:8}"
    _check_name_safety "$vm_name" || return 1
    [ -n "$sha" ] || { echo "ERROR: install_statbus_at_sha requires a commit SHA" >&2; return 1; }

    # NOTE: ephemeral arc-signer trust is injected POST-install by the caller
    # (working-arc.sh), NOT here. A pre-install UPGRADE_TRUSTED_SIGNER_arc is
    # scrubbed by install's checkSignersDone (install.go:1592-1650): it runs
    # `git verify-commit HEAD` against ALL configured signers and DELETES every
    # UPGRADE_TRUSTED_SIGNER_* if HEAD doesn't verify — and the arc key signs
    # B/C, never HEAD=A (=this sha, a master commit jhf signed). So the box is
    # installed with --trust-github-user jhf only (jhf verifies A → survives the
    # scrub); the caller adds arc afterward via config generate + unit restart.

    local ip
    ip=$(hcloud server ip "$vm_name")

    local install_script
    install_script=$(mktemp)
    cat > "$install_script" << SCRIPT
set -e
# Blobless full-history clone so ANY commit is checkoutable (a --depth clone could
# miss base_sha if master advanced); fast — blobs are fetched on demand only.
if [ ! -d ~/statbus/.git ]; then
    git clone --filter=blob:none https://github.com/statisticsnorway/statbus.git ~/statbus
fi
cd ~/statbus
# Pin the tree to base_sha A — deterministic, NO master drift. The fetch is a
# belt-and-suspenders net (the blobless clone already has the full commit graph).
git fetch --filter=blob:none origin ${sha} 2>/dev/null || true
git checkout -q ${sha}
# Toolchain-free binary procurement for A (mirrors install.sh edge /
# sbimage.ProcureShort): pull the per-commit sb image, copy /sb out.
docker pull ghcr.io/statisticsnorway/statbus-sb:${short}
cid=\$(docker create ghcr.io/statisticsnorway/statbus-sb:${short})
docker cp "\$cid":/sb ./sb
docker rm "\$cid"
chmod +x ./sb
# Pre-place config: ./sb install needs .env.config + .users.yml.
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT

    _wait_for_ssh "$ip" 30
    scp -O "${SSH_OPTS[@]}" "$install_script" root@"$ip":/tmp/install.sh
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/install.sh'
    rm -f "$install_script"

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

    # Probe SSH before starting — post-install the VM may be briefly under
    # load (Docker container restarts, service health checks) and sshd's
    # accept queue can be saturated, causing SYN-drops on every new
    # connection.  Waiting here prevents a cascade of chunk failures.
    _wait_for_ssh "$ip" 30

    set -x

    local scp_rc=0
    # Upload via 2 MB chunks to work around the SSH channel-window deadlock on
    # cx23-class targets (Ubuntu 24.04, OpenSSH 9.6p1, kernel 6.8.0-111).
    #
    # Root cause: cx23's sshd fills its 4 MB initial SSH channel window but
    # never sends CHANNEL_WINDOW_ADJUST, permanently stalling every single-pass
    # transfer > 4 MB regardless of protocol (SFTP or legacy scp -O).  The
    # identical sshd on niue (kernel 6.8.0-79) does not exhibit this.
    #
    # Fix: split into 2 MB chunks; each chunk fits within the initial window so
    # no WINDOW_ADJUST exchange is ever needed and the transfer completes.
    # Reassemble with cat on the remote.  Keep -O (legacy wire protocol) to
    # avoid the separate macOS OpenSSH 10.0+ SFTP pipelining deadlock.
    local chunk_dir
    chunk_dir=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; return 1; }
    split -b 2m "$sb_binary" "$chunk_dir/sb-upload-chunk-" 2>>"$scp_log" || scp_rc=$?
    if [ "$scp_rc" -eq 0 ]; then
        local chunk_count=0
        for chunk in "$chunk_dir/sb-upload-chunk-"*; do
            chunk_count=$((chunk_count + 1))
        done
        set +x
        echo "  uploading $(basename "$sb_binary") in ${chunk_count}×2MB chunks (SSH window-adjust workaround)..."
        set -x
        for chunk in "$chunk_dir/sb-upload-chunk-"*; do
            local chunk_name
            chunk_name="$(basename "$chunk")"
            local attempt
            for attempt in 1 2 3; do
                if scp -O "${SSH_OPTS[@]}" -o LogLevel=VERBOSE \
                    "$chunk" root@"$ip":/tmp/"$chunk_name" \
                    2>>"$scp_log"; then
                    break
                fi
                scp_rc=$?
                if [ "$attempt" -eq 3 ]; then
                    set +x
                    echo "  chunk $chunk_name: failed after 3 attempts" >&2
                    set -x
                    break 2
                fi
                set +x
                echo "  chunk $chunk_name: attempt $attempt failed (rc=$scp_rc), waiting 15s before retry..." >&2
                set -x
                sleep 15
                scp_rc=0
            done
        done
    fi
    rm -rf "$chunk_dir"
    if [ "$scp_rc" -eq 0 ]; then
        local assemble_rc=0
        for attempt in 1 2 3; do
            if ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" \
                'cat /tmp/sb-upload-chunk-* > /tmp/sb && rm -f /tmp/sb-upload-chunk-*' \
                2>>"$scp_log"; then
                break
            fi
            assemble_rc=$?
            if [ "$attempt" -eq 3 ]; then
                scp_rc=$assemble_rc
                break
            fi
            set +x
            echo "  assembly attempt $attempt failed (rc=$assemble_rc), waiting 15s..." >&2
            set -x
            sleep 15
            assemble_rc=0
        done
    fi
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
#   ssh root@<ip> journalctl --user -u statbus-upgrade@statbus --no-pager
#   hcloud server delete <name>           — delete when done

# dump_stage_tmux_logs — surface detached-tmux per-stage install logs to stdout
# (→ the scenario's CI log) before the VM is reaped or left up.
#
# Inline-dispatch scenarios run `./sb install` in a DETACHED tmux session that
# writes the install's stdout/stderr to /tmp/<session>.log ON THE VM (see the
# _start_install_with_env-style runners in the scenarios). That file is NOT in
# the CI artifacts, so when an inline install misbehaves (e.g. detects the wrong
# install state and never dispatches the scheduled upgrade, so the inject stall
# never fires) the failure is otherwise undiagnosable from the CI log alone.
#
# Called from cleanup_vm so EVERY scenario benefits automatically, on BOTH
# success and failure, before the VM is deleted (or left running under KEEP_VM).
# Best-effort: a no-op when no stage logs exist or the VM is unreachable; it must
# never fail or slow cleanup beyond one SSH round-trip.
dump_stage_tmux_logs() {
    local vm_name="$1"
    local ip
    ip=$(hcloud server ip "$vm_name" 2>/dev/null) || return 0
    [ -n "$ip" ] && [ "$ip" != "?" ] || return 0
    echo "──────── detached-tmux stage logs (/tmp/stage*.log on $vm_name) ────────"
    ssh "${SSH_OPTS[@]}" root@"$ip" bash -s <<'REMOTE' 2>/dev/null || echo "  (could not retrieve stage logs — VM unreachable?)"
shopt -s nullglob
logs=(/tmp/stage*.log)
if [ ${#logs[@]} -eq 0 ]; then
    echo "  (no /tmp/stage*.log on VM — scenario did not use a detached-tmux install)"
    exit 0
fi
for f in "${logs[@]}"; do
    ex="${f%.log}.exit"
    code="(no .exit file — still running or killed before exit)"
    [ -f "$ex" ] && code="$(cat "$ex" 2>/dev/null)"
    echo ""
    echo "════ $f  [exit: $code] ════"
    cat "$f" 2>/dev/null || echo "  (cat failed)"
done
REMOTE
    echo "──────── end stage logs ────────"
}

# _dump_unit_diagnostics UNIT
# Capture journal + status + sb-version for UNIT to stderr while the VM is
# still alive. Called by vm_restart_unit on failure so diagnostics land in the
# scenario log BEFORE set -e fires the EXIT trap and cleanup_vm reaps the VM.
# Each sub-command is best-effort (|| true); never aborts the caller.
_dump_unit_diagnostics() {
    local unit="${1:-statbus-upgrade@statbus.service}"
    echo "  ── unit diagnostics: $unit ──" >&2
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID journalctl --user -xeu '$unit' --no-pager | tail -120" >&2 || true
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID systemctl --user status '$unit' --no-pager" >&2 || true
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus -- bash -c 'cd ~/statbus && ./sb --version 2>/dev/null || true; git rev-parse HEAD 2>/dev/null || true'" >&2 || true
    echo "  ── end unit diagnostics ──" >&2
}

# _vm_unit_op OP UNIT [WAIT_S]
# Internal: issue `systemctl --user OP UNIT` on the VM, wait WAIT_S seconds,
# then check is-active. On any failure (command non-zero OR unit not active)
# dumps diagnostics via _dump_unit_diagnostics before returning non-zero.
# Does NOT call exit — let the caller / set -e decide.
_vm_unit_op() {
    local op="$1"
    local unit="${2:-statbus-upgrade@statbus.service}"
    local wait_s="${3:-5}"

    if ! VM_EXEC systemctl --user "$op" "$unit"; then
        echo "  ✗ systemctl --user $op $unit returned non-zero — capturing diagnostics:" >&2
        _dump_unit_diagnostics "$unit"
        return 1
    fi
    sleep "$wait_s"
    local state
    state=$(VM_EXEC systemctl --user is-active "$unit" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$state" != "active" ]; then
        echo "  ✗ unit $unit not active after $op (state=$state) — capturing diagnostics:" >&2
        _dump_unit_diagnostics "$unit"
        return 1
    fi
    return 0
}

# vm_restart_unit UNIT [WAIT_S]
# Restart a stopped-or-running unit. Dumps diagnostics on failure before
# returning non-zero so logs survive before cleanup_vm reaps the VM.
vm_restart_unit() { _vm_unit_op restart "$@"; }

# vm_start_unit UNIT [WAIT_S]
# Start a stopped unit. Use instead of vm_restart_unit when the unit is
# already stopped (avoids a redundant stop step). Same diagnostic behaviour.
vm_start_unit() { _vm_unit_op start "$@"; }

cleanup_vm() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1

    # Surface detached-tmux stage logs (success OR failure) BEFORE reaping/leaving
    # the VM. Best-effort; a no-op for scenarios that never used a tmux install.
    dump_stage_tmux_logs "$vm_name"

    if [ "${KEEP_VM:-0}" = "1" ] || [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ]; then
        local ip
        ip=$(hcloud server ip "$vm_name" 2>/dev/null || echo "?")
        local reason="KEEP_VM=1"
        [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ] && reason="KEEP_VM_ON_FAILURE=1"
        echo "$reason — leaving $vm_name running for post-mortem (€0.0072/hr)"
        echo "  ssh root@$ip"
        echo "  ssh statbus@$ip"
        echo "  journalctl: ssh root@$ip journalctl --user -u statbus-upgrade@statbus --no-pager -n 200"
        echo "  upload logs: /tmp/upload-sb-scp-*.log  /tmp/upload-sb-ssh-*.log"
        echo "  Delete when done: hcloud server delete $vm_name"
        return 0
    fi
    echo "Deleting VM: $vm_name"
    hcloud server delete "$vm_name" 2>/dev/null || true
}
