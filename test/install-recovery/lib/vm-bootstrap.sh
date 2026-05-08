#!/bin/bash
# vm-bootstrap.sh — Multipass VM bootstrap helper for install recovery tests.
#
# Sourced by test/install-recovery/scenarios/*.sh. Provides:
#
#   bootstrap_install_test_vm <vm_name> [install_version]
#       Launch a fresh Ubuntu 24.04 VM, harden it, create the statbus user,
#       set up linger so systemctl --user works under sudo -i. When the
#       function returns, the VM is ready for `./sb install` to run.
#
#       install_version: empty (default) → uses locally-built `sb` binary
#                        v2026.05.0-rc.X → downloads that release on the VM
#
#   $VM_EXEC                Bash command prefix to run as statbus user with
#                           full login shell (sources .profile → XDG_RUNTIME_DIR
#                           is set so systemctl --user works).
#
#   $STATBUS_UID            Numeric UID of the statbus user inside the VM.
#
# Mirrors the bootstrap logic in dev.sh's `test-install` command (which
# stays untouched; this is intentionally duplicated to avoid risking a
# regression in the established stable-release pre-flight gate). Once the
# new harness is proven, the duplication can be eliminated by extracting
# both call sites to share this file.

set -euo pipefail

# Resolve workspace root (statbus/) regardless of where scripts are sourced from.
HARNESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$HARNESS_LIB_DIR/../../.." && pwd)"

bootstrap_install_test_vm() {
    local vm_name="$1"
    local install_version="${2:-}"

    if ! command -v multipass >/dev/null 2>&1; then
        echo "ERROR: multipass is not installed. Install it: brew install multipass" >&2
        return 1
    fi

    # Cleanup any previous test VM with the same name (idempotent).
    if multipass info "$vm_name" >/dev/null 2>&1; then
        echo "Cleaning up previous test VM: $vm_name"
        multipass delete "$vm_name" 2>/dev/null || true
        multipass purge 2>/dev/null || true
    fi

    local sb_binary=""
    if [ -z "$install_version" ]; then
        # Build the sb binary for Linux (matching the VM architecture).
        local host_arch
        host_arch=$(uname -m)
        local build_target
        case "$host_arch" in
            x86_64)        build_target="linux/amd64" ;;
            arm64|aarch64) build_target="linux/arm64" ;;
            *)             echo "Unsupported architecture: $host_arch" >&2; return 1 ;;
        esac
        echo "Building sb for $build_target..."
        (cd "$HARNESS_ROOT" && ./dev.sh build-sb "$build_target")
        sb_binary="${HARNESS_ROOT}/sb-${build_target//\//-}"  # e.g. sb-linux-arm64
    fi

    echo "Launching Ubuntu 24.04 VM ($vm_name)..."
    # MULTIPASS_BRIDGE workaround: when macOS vmnet-shared is broken (commonly
    # after network swaps — VPN connect/disconnect, hotel/train wifi, etc.),
    # the default NAT bridge has no host-side IP and VMs are unreachable
    # via `multipass exec` ("No route to host"). Setting MULTIPASS_BRIDGE=en0
    # (or any active interface from `multipass networks`) adds a second NIC
    # in bridged mode that DOES work. No-op when unset (uses default vmnet-shared).
    local network_args=()
    if [ -n "${MULTIPASS_BRIDGE:-}" ]; then
        echo "  using bridged network: --network $MULTIPASS_BRIDGE"
        network_args=(--network "$MULTIPASS_BRIDGE")
    fi
    multipass launch 24.04 --name "$vm_name" --cpus 2 --memory 4G --disk 10G --timeout 600 "${network_args[@]}"

    echo "Waiting for VM to be ready..."
    multipass exec "$vm_name" -- cloud-init status --wait 2>/dev/null || true

    echo "Transferring files..."
    if [ -n "$sb_binary" ]; then
        multipass transfer "$sb_binary" "$vm_name":/tmp/sb
    fi
    multipass transfer "$HARNESS_ROOT/ops/setup-ubuntu-lts-24.sh" "$vm_name":/tmp/setup.sh

    # Standard test config. Slot=test, mode=development.
    local env_config_file
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
    multipass transfer "$env_config_file" "$vm_name":/tmp/env-config
    rm -f "$env_config_file"

    local users_file
    users_file=$(mktemp)
    cat > "$users_file" << 'USERS'
- email: test@statbus.org
  password: test-install-password-2026
  role: admin_user
  display_name: Admin
USERS
    multipass transfer "$users_file" "$vm_name":/tmp/users.yml
    rm -f "$users_file"

    # Hardening config for non-interactive setup-ubuntu-lts-24.sh.
    multipass exec "$vm_name" -- sudo bash -c 'cat > /root/.setup-ubuntu.env << EOF
ADMIN_EMAIL="test@statbus.org"
GITHUB_USERS="jhf"
EXTRA_LOCALES=""
CADDY_PLUGINS=""
EOF'

    echo "=== Stage: Hardening ==="
    mkdir -p "${HARNESS_ROOT}/tmp"
    multipass exec "$vm_name" -- sudo bash /tmp/setup.sh --non-interactive 2>&1 \
        | tee "${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-bootstrap.log"

    # Create dedicated statbus user (after hardening installs Docker so
    # the docker group exists).
    multipass exec "$vm_name" -- sudo useradd -m -s /bin/bash -G docker statbus

    # Linger so the user-level systemd manager runs without an active login.
    multipass exec "$vm_name" -- sudo loginctl enable-linger statbus

    # Set XDG_RUNTIME_DIR in the statbus user's .profile so `sudo -i -u statbus`
    # gets a working systemd --user session (PAM doesn't set this for sudo).
    multipass exec "$vm_name" -- sudo bash -c \
        'echo "export XDG_RUNTIME_DIR=/run/user/\$(id -u)" >> /home/statbus/.profile'

    # Wait for the user manager to be ready (~100ms typically).
    STATBUS_UID=$(multipass exec "$vm_name" -- id -u statbus)
    local i
    for i in $(seq 1 20); do
        multipass exec "$vm_name" -- sudo -u statbus \
            XDG_RUNTIME_DIR=/run/user/"$STATBUS_UID" \
            systemctl --user is-system-running 2>/dev/null | grep -qE "running|degraded" && break
        sleep 0.1
    done

    # Globally accessible exec helper. Sources .profile via -i so XDG_RUNTIME_DIR
    # is set before any systemctl --user invocation.
    VM_EXEC="multipass exec $vm_name -- sudo -i -u statbus"

    echo "Verifying systemctl --user via sudo -i -u statbus..."
    $VM_EXEC systemctl --user is-system-running || true

    echo "VM $vm_name bootstrap complete."
}

# Run install inside a bootstrapped VM. Two modes:
#   install_statbus_in_vm <vm_name>                  → use locally-built /tmp/sb
#   install_statbus_in_vm <vm_name> v2026.05.0-rc.X  → download from release
#
# Caller may pre-set $SB_INSTALL_EXTRA_ARGS (e.g. "--recovery=auto") — these
# are appended to ./sb install.
install_statbus_in_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    local extra_args="${SB_INSTALL_EXTRA_ARGS:-}"

    local install_script
    install_script=$(mktemp)
    if [ -z "$install_version" ]; then
        cat > "$install_script" << SCRIPT
set -e
mkdir -p ~/statbus
cd ~/statbus
cp /tmp/sb ./sb
chmod +x ./sb
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
cp /tmp/env-config .env.config 2>/dev/null || true
cp /tmp/users.yml .users.yml 2>/dev/null || true
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf $extra_args
SCRIPT
    fi

    multipass transfer "$install_script" "$vm_name":/tmp/install.sh
    rm -f "$install_script"

    multipass exec "$vm_name" -- sudo -i -u statbus bash /tmp/install.sh 2>&1 \
        | tee -a "${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"
    return ${PIPESTATUS[0]}
}

# Cleanup helper — safe to call multiple times. Honors $KEEP_VM=1 to leave
# the VM running for debugging.
cleanup_vm() {
    local vm_name="$1"
    if [ "${KEEP_VM:-0}" = "1" ]; then
        echo "KEEP_VM=1 — leaving $vm_name running for debugging."
        echo "  Connect: multipass shell $vm_name"
        echo "  Statbus user: multipass exec $vm_name -- sudo -i -u statbus"
        return 0
    fi
    echo "Cleaning up VM: $vm_name"
    multipass delete "$vm_name" 2>/dev/null || true
    multipass purge 2>/dev/null || true
}
