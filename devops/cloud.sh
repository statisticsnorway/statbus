#!/bin/bash
#
# Cloud fleet management for StatBus on niue.statbus.org
#
# This is an OPERATOR tool, not a product feature.
# ./sb manages a single installation. This script manages the fleet.
#
# Usage:
#   ./devops/cloud.sh status             Show version on all servers
#   ./devops/cloud.sh reset <server>     Lifeline reset on one server (install.sh)
#   ./devops/cloud.sh reset all          Lifeline reset on ALL servers
#
# Three escalation levels for cloud management:
#   Level 1 (discover):  Automatic. Push to master → notify workflow → servers see new version.
#   Level 2 (upgrade):   git push origin master:devops/deploy-to-production → forced upgrade.
#   Level 3 (reset):     This script. Stops daemon, fresh binary, full reinstall.
#
# Levels 1 and 2 are triggered via git push (GitHub workflows).
# Level 3 is this script — for emergencies and routine verification.
#
set -euo pipefail

SERVERS="statbus_demo statbus_no statbus_tcc statbus_ma statbus_ug statbus_et statbus_jo statbus_dev"
HOST="niue.statbus.org"
INSTALL_URL="https://statbus.org/install.sh"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  status             Show version on all servers"
    echo "  reset <server>     Lifeline reset on one server"
    echo "  reset all          Lifeline reset on ALL servers"
    echo ""
    echo "Servers: $SERVERS"
    exit 1
}

cmd_status() {
    echo "StatBus Cloud Status"
    echo "===================="
    for server in $SERVERS; do
        printf "  %-16s " "$server:"
        ssh -o ConnectTimeout=5 "${server}@${HOST}" \
            "cd statbus && ./sb --version 2>/dev/null || echo 'UNKNOWN'" 2>/dev/null \
            || echo "SSH FAILED"
    done
}

cmd_reset() {
    local target="$1"

    if [ "$target" = "all" ]; then
        echo "Resetting ALL servers via install.sh"
        echo "===================================="
        for server in $SERVERS; do
            echo ""
            echo "--- $server ---"
            cmd_reset_one "$server"
        done
    else
        # Verify server name is in the list
        if ! echo "$SERVERS" | grep -qw "$target"; then
            echo "Error: unknown server '$target'"
            echo "Valid servers: $SERVERS"
            exit 1
        fi
        cmd_reset_one "$target"
    fi
}

cmd_reset_one() {
    local server="$1"
    echo "Resetting $server via $INSTALL_URL ..."
    ssh -o ConnectTimeout=10 "${server}@${HOST}" \
        "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease" 2>&1
    echo "--- $server reset complete ---"
}

# Main
if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    status)
        cmd_status
        ;;
    reset)
        if [ $# -lt 2 ]; then
            echo "Error: reset requires a server name or 'all'"
            usage
        fi
        cmd_reset "$2"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
