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
#   ./devops/cloud.sh rescue <server>     Fresh binary + re-install, keeps data (idempotent)
#   ./devops/cloud.sh rescue all          Rescue ALL servers
#   ./devops/cloud.sh wipe <server>       DESTRUCTIVE: delete DB and recreate from scratch
#
# Escalation levels:
#   notify   — gentle. Servers discover new version. Admin chooses when to upgrade.
#   upgrade  — firm. Servers apply latest NOW. No approval needed.
#   rescue   — repair. Downloads fresh binary, re-runs install. Keeps all data.
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
    echo "  rescue <server>     Fresh binary + re-install (keeps data)"
    echo "  rescue all          Rescue ALL servers"
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

cmd_rescue() {
    local target="$1"
    validate_server "$target"

    if [ "$target" = "all" ]; then
        echo "Rescuing ALL servers via install.sh"
        echo "==================================="
        for server in $SERVERS; do
            echo ""
            echo "--- $server ---"
            cmd_rescue_one "$server"
        done
    else
        cmd_rescue_one "$target"
    fi
}

cmd_rescue_one() {
    local server="$1"
    echo "Rescuing $server via $INSTALL_URL ..."
    ssh_server "$server" \
        "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease" 2>&1
    echo "--- $server rescue complete ---"
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
    ssh_server "$target" "cd statbus && ./dev.sh recreate-database" 2>&1
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
    rescue)
        [ $# -lt 2 ] && { echo "Error: rescue requires a server name or 'all'"; usage; }
        cmd_rescue "$2"
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
