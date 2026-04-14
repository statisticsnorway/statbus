#!/bin/bash
#
# Cloud fleet management for StatBus on niue.statbus.org
#
# This is an OPERATOR tool, not a product feature.
# ./sb manages a single installation. This script manages the fleet.
#
# Usage:
#   ./cloud.sh status              Show version on all servers
#   ./cloud.sh notify              Tell servers to check for updates (non-disruptive)
#   ./cloud.sh upgrade             Force all servers to apply latest now
#   ./cloud.sh install <server>    Full idempotent install (includes service via root)
#   ./cloud.sh install all         Install ALL servers
#   ./cloud.sh rescue <server>     Alias for install (backwards compat)
#   ./cloud.sh wipe <server>       DESTRUCTIVE: delete DB and recreate from scratch
#
# Escalation levels:
#   notify   — gentle. Servers discover new version. Admin chooses when to upgrade.
#   upgrade  — firm. Servers apply latest NOW. No approval needed.
#   install  — full. Downloads fresh binary, re-runs install, installs service via root.
#   create   — provision. Creates new deployment slot (DNS, user, workflows, etc.)
#   inspect  — read-only. Shows credentials/URLs for all deployment slots.
#   wipe     — destructive. Deletes database and recreates. Data is lost.
#
set -euo pipefail

SERVERS="statbus_demo statbus_no statbus_tcc statbus_ma statbus_ug statbus_et statbus_jo statbus_dev"
HOST="niue.statbus.org"
INSTALL_URL="https://statbus.org/install.sh"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  status              Show version on all servers"
    echo "  notify              Tell servers to check for updates"
    echo "  upgrade             Force all servers to apply latest"
    echo "  install <server>    Full idempotent install (includes service via root)"
    echo "  install all         Install ALL servers"
    echo "  rescue <server>     Alias for install"
    echo "  create <code> <name>  Create new cloud installation"
    echo "  inspect             Show credentials for all installations"
    echo "  wipe <server>       DESTRUCTIVE: delete DB and recreate"
    echo ""
    echo "Servers: $SERVERS"
    exit 1
}

ssh_server() {
    local server="$1"
    shift
    ssh -o ConnectTimeout=10 "${server}@${HOST}" "$@"
}

validate_server() {
    local target="$1"
    if [ "$target" != "all" ] && ! echo "$SERVERS" | grep -qw "$target"; then
        echo "Error: unknown server '$target'"
        echo "Valid servers: $SERVERS"
        exit 1
    fi
}

cmd_status() {
    echo "StatBus Cloud Status"
    echo "===================="
    for server in $SERVERS; do
        printf "  %-16s " "$server:"
        ssh_server "$server" \
            "cd statbus && ./sb --version 2>/dev/null || echo 'UNKNOWN'" 2>/dev/null \
            || echo "SSH FAILED"
    done
}

cmd_notify() {
    echo "Notifying all servers to check for updates..."
    for server in $SERVERS; do
        printf "  %-16s " "$server:"
        ssh_server "$server" "cd statbus && ./sb upgrade discover" 2>/dev/null \
            && echo "notified" || echo "FAILED"
    done
}

cmd_upgrade() {
    echo "Forcing all servers to apply latest..."
    for server in $SERVERS; do
        printf "  %-16s " "$server:"
        ssh_server "$server" "cd statbus && ./sb upgrade apply-latest" 2>/dev/null \
            && echo "scheduled" || echo "FAILED"
    done
}

cmd_install() {
    local target="$1"
    validate_server "$target"

    if [ "$target" = "all" ]; then
        echo "Installing ALL servers"
        echo "======================"
        for server in $SERVERS; do
            echo ""
            echo "--- $server ---"
            cmd_install_one "$server"
        done
    else
        cmd_install_one "$target"
    fi
}

cmd_install_one() {
    # Concurrency safety: both channel branches stop the remote upgrade service
    # via `systemctl --user stop` BEFORE swapping the binary or running the
    # installer. That stop removes the "active" actor from the picture, so when
    # `./sb install` runs remotely it sees either no mutex flag (common) or a
    # stale flag from a crashed upgrade (in which case it instructs the operator
    # to start the service to trigger recoverFromFlag). Either way, there is no
    # race with an in-flight executeUpgrade.
    local server="$1"
    local exit_code=0

    # Check the server's upgrade channel to decide install strategy.
    # Edge channel tracks master (build from source). Others use tagged releases.
    local channel
    channel=$(ssh_server "$server" "cd statbus && ./sb dotenv -f .env.config get UPGRADE_CHANNEL 2>/dev/null" 2>/dev/null || echo "prerelease")

    if [ "$channel" = "edge" ]; then
        echo "Installing $server (edge channel — building from master)..."
        # Edge: pull latest master, rebuild binary with version from git describe.
        # No release binary exists for untagged master commits.
        # Follow the same pattern as install.sh: stop service, build to tmp, move into place.
        ssh_server "$server" "cd statbus && git fetch origin master --quiet && git checkout origin/master --quiet" 2>&1
        ssh_server "$server" "cd statbus && export PATH=/home/linuxbrew/.linuxbrew/bin:\$PATH && ./dev.sh build-sb" 2>&1
        # Stop user-level service before replacing binary.
        # systemd --user restarts it immediately (Restart=always),
        # and the new process holds the binary open → "Text file busy" on mv.
        ssh_server "$server" "systemctl --user stop statbus-upgrade@${server}.service 2>/dev/null || true" 2>&1
        ssh_server "$server" "cd statbus && mv sb-linux-amd64 sb" 2>&1
        # ./sb install detects the service is stopped and restarts it (user-level, no root needed).
        ssh_server "$server" "cd statbus && ./sb install" 2>&1 \
            || exit_code=$?
    else
        echo "Installing $server via $INSTALL_URL ..."
        # Stop the user-level upgrade service before running install.sh.
        # Mirrors the edge-channel behavior above. Without this, an in-flight
        # executeUpgrade in the service could race the install.sh binary swap,
        # and the new install's mutex check would (correctly) block with a
        # "upgrade in progress" error. Stop-first is the cleanest path:
        # install.sh's install step re-enables and starts the service on
        # completion.
        ssh_server "$server" "systemctl --user stop statbus-upgrade@${server}.service 2>/dev/null || true" 2>&1
        # Step 1: Run install.sh as the app user.
        # Exit code 42 = service needs root (not a failure).
        ssh_server "$server" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease" 2>&1 \
            || exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "--- $server install FAILED (exit code $exit_code) ---"
        return 1
    fi

    # Step 3: Regenerate config so VERSION in .env matches the checked-out code.
    # Must use 'up -d' not 'restart' — restart doesn't re-read .env.
    echo "Regenerating config and restarting app..."
    ssh_server "$server" "cd statbus && ./sb config generate && docker compose up -d app" 2>&1

    # Step 4: Final verify — all steps must pass.
    echo "Verifying install..."
    ssh_server "$server" "cd statbus && ./sb install" 2>&1

    echo "--- $server install complete ---"
}

cmd_wipe() {
    local target="$1"
    validate_server "$target"

    if [ "$target" = "all" ]; then
        echo "ERROR: wipe all is not supported. Wipe servers one at a time."
        exit 1
    fi

    echo "WARNING: This will DELETE the database on $target and recreate from scratch."
    echo "ALL DATA WILL BE LOST."
    read -p "Type the server name to confirm: " confirm
    if [ "$confirm" != "$target" ]; then
        echo "Aborted."
        exit 1
    fi

    echo "Wiping $target..."
    ssh_server "$target" "cd statbus && ./dev.sh recreate-database && ./sb start all" 2>&1
    echo "--- $target wipe complete ---"
}

cmd_create() {
    local code="$1"
    local name="$2"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "$SCRIPT_DIR/ops/create-new-statbus-installation.sh" "$code" "$name"
}

cmd_inspect() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "$SCRIPT_DIR/ops/inspect-cloud-installations.sh"
}

# Main
if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    status)
        cmd_status
        ;;
    notify)
        cmd_notify
        ;;
    upgrade)
        cmd_upgrade
        ;;
    install|rescue)
        [ $# -lt 2 ] && { echo "Error: $1 requires a server name or 'all'"; usage; }
        cmd_install "$2"
        ;;
    create)
        [ $# -lt 3 ] && { echo "Error: create requires <code> and <name>"; echo "Example: $0 create pk \"Pakistan StatBus\""; exit 1; }
        cmd_create "$2" "$3"
        ;;
    inspect)
        cmd_inspect
        ;;
    wipe)
        [ $# -lt 2 ] && { echo "Error: wipe requires a server name"; usage; }
        cmd_wipe "$2"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
