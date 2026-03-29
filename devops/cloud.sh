#!/bin/bash
#
# Cloud fleet management for StatBus on niue.statbus.org
#
# This is an OPERATOR tool, not a product feature.
# ./sb manages a single installation. This script manages the fleet.
#
# Usage:
#   ./devops/cloud.sh status              Show version on all servers
#   ./devops/cloud.sh notify              Tell servers to check for updates (non-disruptive)
#   ./devops/cloud.sh upgrade             Force all servers to apply latest now
#   ./devops/cloud.sh install <server>    Full idempotent install (includes daemon via root)
#   ./devops/cloud.sh install all         Install ALL servers
#   ./devops/cloud.sh rescue <server>     Alias for install (backwards compat)
#   ./devops/cloud.sh wipe <server>       DESTRUCTIVE: delete DB and recreate from scratch
#
# Escalation levels:
#   notify   — gentle. Servers discover new version. Admin chooses when to upgrade.
#   upgrade  — firm. Servers apply latest NOW. No approval needed.
#   install  — full. Downloads fresh binary, re-runs install, installs daemon via root.
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
    echo "  install <server>    Full idempotent install (includes daemon via root)"
    echo "  install all         Install ALL servers"
    echo "  rescue <server>     Alias for install"
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
    local server="$1"
    local exit_code=0

    echo "Installing $server via $INSTALL_URL ..."

    # Step 1: Run install.sh as the app user.
    # Exit code 42 = daemon needs root (not a failure).
    ssh_server "$server" \
        "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease" 2>&1 \
        || exit_code=$?

    if [ "$exit_code" -eq 42 ]; then
        # Step 2: Daemon needs root — SSH as root to install the systemd service.
        # The app user home dir is /home/$server (our naming convention on niue).
        echo "Daemon needs root — installing systemd service..."
        ssh -o ConnectTimeout=10 "root@${HOST}" \
            "cd /home/${server}/statbus && ./sb install" 2>&1
    elif [ "$exit_code" -ne 0 ]; then
        echo "--- $server install FAILED (exit code $exit_code) ---"
        return 1
    fi

    # Step 3: Regenerate config so VERSION in .env matches the checked-out code.
    # Restart app so the web UI picks up the new version.
    echo "Regenerating config and restarting app..."
    ssh_server "$server" "cd statbus && ./sb config generate && docker compose restart app" 2>&1

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
    wipe)
        [ $# -lt 2 ] && { echo "Error: wipe requires a server name"; usage; }
        cmd_wipe "$2"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
