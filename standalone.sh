#!/bin/bash
#
# Standalone fleet management for StatBus on dedicated hosts.
#
# This is an OPERATOR tool, not a product feature. Parallel to ./cloud.sh
# (which manages niue's multi-tenant slots) — ./standalone.sh manages
# hosts that run a single StatBus install under the `statbus` service
# account (created by setup-ubuntu-lts-24.sh Stage 7).
#
# Usage:
#   ./standalone.sh status              Show version on all standalone hosts
#   ./standalone.sh notify              Tell hosts to check for updates
#   ./standalone.sh upgrade             Force all hosts to apply latest
#   ./standalone.sh install <name>      Install (downloads binary, re-runs install)
#   ./standalone.sh install all         Install ALL hosts
#   ./standalone.sh rescue <name>       Alias for install (backwards compat)
#   ./standalone.sh wipe <name>         DESTRUCTIVE: delete DB and recreate
#   ./standalone.sh inspect             Show urls, slot codes, and deploy branches
#   ./standalone.sh ssh <name>          Open interactive shell as statbus@<host>
#
# Provisioning a NEW standalone host is a one-time manual job — OS install,
# setup-ubuntu-lts-24.sh, then bootstrap. See doc/hetzner-bootstrap.md and
# doc/setup-ubuntu-lts-24.md. Once the host has a `statbus` service account
# reachable over SSH, register it in HOSTS below.
#
# Differences vs cloud.sh:
#   - cloud.sh: N slots per host (niue.statbus.org), user = statbus_<slot>
#   - standalone.sh: 1 StatBus per host, user = statbus, service unit is
#     statbus-upgrade@<slot_code>.service (slot_code is the DEPLOYMENT_SLOT_CODE
#     from the host's .env.config, NOT the host short name).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Host registry: "<name>|<host_fqdn>|<served_domain>|<slot_code>"
#   name           short identifier used as CLI arg (e.g. "rune-no")
#   host_fqdn      SSH target; always <name before dash>.statbus.org by
#                  convention but stored explicitly for flexibility
#   served_domain  public domain the host serves (e.g. no.statbus.org)
#   slot_code      DEPLOYMENT_SLOT_CODE; used in systemd unit names
#                  (statbus-upgrade@<slot_code>.service)
#
# To add a new standalone host: append a line here, plus .github/workflows/
# {master,deploy}-to-<name>.yaml modeled on -rune-no.yaml.
HOSTS=(
    "rune-no|rune.statbus.org|no.statbus.org|no"
)

# GitHub username whose signing key should be trusted on each host.
# Passed as --trust-github-user to ./sb install. No default — install
# must fail if the wrong key is configured, forcing the operator to be
# explicit:
#   STANDALONE_TRUST_KEY_USER=jhf ./standalone.sh install all
STANDALONE_TRUST_KEY_USER="${STANDALONE_TRUST_KEY_USER:-}"

INSTALL_URL="https://statbus.org/install.sh"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  status                  Show version on all standalone hosts"
    echo "  notify                  Tell hosts to check for updates"
    echo "  upgrade                 Force all hosts to apply latest"
    echo "  install <name> [ver]    Install host (optionally pin to specific version)"
    echo "  install all [ver]       Install ALL hosts (optionally pin)"
    echo "  rescue <name>           Alias for install"
    echo "  inspect                 Show urls, slot codes, and deploy branches"
    echo "  wipe <name>             DESTRUCTIVE: delete DB and recreate"
    echo "  ssh <name>              Open interactive shell as statbus@<host>"
    echo ""
    echo "Registered hosts:"
    for entry in "${HOSTS[@]}"; do
        printf "  %s\n" "${entry%%|*}"
    done
    exit 1
}

# Host lookup helpers. Given a name, return specific fields.
host_fqdn() {
    local name="$1"
    for entry in "${HOSTS[@]}"; do
        if [ "${entry%%|*}" = "$name" ]; then
            echo "$entry" | cut -d'|' -f2
            return 0
        fi
    done
    return 1
}

served_domain() {
    local name="$1"
    for entry in "${HOSTS[@]}"; do
        if [ "${entry%%|*}" = "$name" ]; then
            echo "$entry" | cut -d'|' -f3
            return 0
        fi
    done
    return 1
}

slot_code() {
    local name="$1"
    for entry in "${HOSTS[@]}"; do
        if [ "${entry%%|*}" = "$name" ]; then
            echo "$entry" | cut -d'|' -f4
            return 0
        fi
    done
    return 1
}

all_names() {
    for entry in "${HOSTS[@]}"; do
        echo "${entry%%|*}"
    done
}

validate_name() {
    local target="$1"
    if [ "$target" = "all" ]; then return 0; fi
    for entry in "${HOSTS[@]}"; do
        if [ "${entry%%|*}" = "$target" ]; then return 0; fi
    done
    echo "Error: unknown host '$target'"
    echo "Registered hosts: $(all_names | tr '\n' ' ')"
    exit 1
}

ssh_host() {
    local name="$1"; shift
    local fqdn
    fqdn=$(host_fqdn "$name") || { echo "Error: no fqdn for $name" >&2; return 1; }
    ssh -o ConnectTimeout=10 "statbus@${fqdn}" "$@"
}

# Stop the user-level upgrade service on the target host so ./sb can be
# replaced without "text file busy". The unit is statbus-upgrade@<slot_code>.service
# (slot_code from the host's .env.config — queried once per call).
stop_upgrade_service() {
    local name="$1"
    local slot
    slot=$(slot_code "$name")
    ssh_host "$name" "systemctl --user stop statbus-upgrade@${slot}.service 2>/dev/null || true" 2>&1
}

ensure_service_started() {
    local name="$1"
    local slot
    slot=$(slot_code "$name")
    ssh_host "$name" "systemctl --user start statbus-upgrade@${slot}.service" 2>&1 || true
}

trust_flag() {
    if [ -n "$STANDALONE_TRUST_KEY_USER" ]; then
        echo "--trust-github-user $STANDALONE_TRUST_KEY_USER"
    fi
}

cmd_status() {
    echo "StatBus Standalone Status"
    echo "========================="
    for name in $(all_names); do
        printf "  %-16s " "$name:"
        ssh_host "$name" \
            "cd statbus && ./sb --version 2>/dev/null || echo 'UNKNOWN'" 2>/dev/null \
            || echo "SSH FAILED"
    done
}

cmd_notify() {
    echo "Notifying all hosts to check for updates..."
    for name in $(all_names); do
        printf "  %-16s " "$name:"
        ssh_host "$name" "cd statbus && ./sb upgrade discover" 2>/dev/null \
            && echo "notified" || echo "FAILED"
    done
}

cmd_upgrade() {
    echo "Forcing all hosts to apply latest..."
    for name in $(all_names); do
        printf "  %-16s " "$name:"
        ssh_host "$name" "cd statbus && ./sb upgrade apply-latest" 2>/dev/null \
            && echo "scheduled" || echo "FAILED"
    done
}

cmd_install_one() {
    # Idempotent install flow:
    #   stop_upgrade_service → install.sh | bash → ensure_service_started
    #
    # Re-running ./standalone.sh install <name> after any partial failure
    # (SSH drop, Ctrl-C, transient error) is safe — every step is rerun-safe.
    # ./sb install's dispatcher handles stale upgrade flags itself
    # (StateCrashedUpgrade reconciles and re-dispatches), so this script
    # only needs to stop the service so the binary can be replaced.
    local name="$1"
    local version="${2:-}"
    local exit_code=0

    if [ -n "$version" ]; then
        echo "Checking release artifacts for $version are ready..."
        if ! "$SCRIPT_DIR/sb" release check --tag "$version" 2>/dev/null; then
            echo "--- Release artifacts for $version not ready. Retry later. ---"
            return 1
        fi
        echo "Installing $name at $version via $INSTALL_URL ..."
        stop_upgrade_service "$name"
        ssh_host "$name" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --version $version $(trust_flag)" 2>&1 \
            || exit_code=$?
    else
        echo "Checking release artifacts are ready..."
        if ! "$SCRIPT_DIR/sb" release check 2>/dev/null; then
            echo "--- Release artifacts not ready. Retry in ~5 minutes. ---"
            return 1
        fi
        echo "Installing $name via $INSTALL_URL (--prerelease) ..."
        stop_upgrade_service "$name"
        ssh_host "$name" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease $(trust_flag)" 2>&1 \
            || exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "--- $name install FAILED (exit code $exit_code) ---"
        if [ -z "$STANDALONE_TRUST_KEY_USER" ]; then
            echo ""
            echo "If this failed because of an invalid signing key, re-run with:"
            echo "  STANDALONE_TRUST_KEY_USER=jhf ./standalone.sh install $name"
            echo ""
        fi
        ensure_service_started "$name"
        return 1
    fi

    # Regenerate config so VERSION in .env matches the checked-out code.
    # Must use 'up -d' not 'restart' — restart doesn't re-read .env.
    echo "Regenerating config and restarting app..."
    ssh_host "$name" "cd statbus && ./sb config generate && docker compose up -d app" 2>&1

    ensure_service_started "$name"

    echo "--- $name install complete ---"
}

cmd_install() {
    local target="$1"
    local version="${2:-}"
    validate_name "$target"

    if [ "$target" = "all" ]; then
        echo "Installing ALL standalone hosts${version:+ (pinned to $version)}"
        echo "==============================="
        for name in $(all_names); do
            echo ""
            echo "--- $name ---"
            cmd_install_one "$name" "$version"
        done
    else
        cmd_install_one "$target" "$version"
    fi
}

cmd_wipe() {
    local target="$1"
    validate_name "$target"

    if [ "$target" = "all" ]; then
        echo "ERROR: wipe all is not supported. Wipe hosts one at a time."
        exit 1
    fi

    echo "WARNING: This will DELETE the database on $target ($(served_domain "$target")) and recreate from scratch."
    echo "ALL DATA WILL BE LOST."
    read -p "Type the host name to confirm: " confirm
    if [ "$confirm" != "$target" ]; then
        echo "Aborted."
        exit 1
    fi

    echo "Wiping $target..."
    ssh_host "$target" "cd statbus && ./dev.sh recreate-database && ./sb start all" 2>&1
    echo "--- $target wipe complete ---"
}

cmd_inspect() {
    echo "StatBus Standalone Hosts"
    echo "========================"
    printf "%-14s  %-24s  %-22s  %-6s  %s\n" "NAME" "HOST (SSH)" "SERVES" "SLOT" "DEPLOY BRANCH"
    for entry in "${HOSTS[@]}"; do
        IFS='|' read -r name fqdn dom slot <<< "$entry"
        printf "%-14s  %-24s  %-22s  %-6s  %s\n" \
            "$name" "statbus@$fqdn" "$dom" "$slot" "ops/standalone/deploy/$name"
    done
}

cmd_ssh() {
    local target="$1"
    validate_name "$target"
    local fqdn
    fqdn=$(host_fqdn "$target")
    echo "Connecting to statbus@${fqdn} ..."
    exec ssh "statbus@${fqdn}"
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
        [ $# -lt 2 ] && { echo "Error: $1 requires a host name or 'all'"; usage; }
        cmd_install "$2" "${3:-}"
        ;;
    inspect)
        cmd_inspect
        ;;
    wipe)
        [ $# -lt 2 ] && { echo "Error: wipe requires a host name"; usage; }
        cmd_wipe "$2"
        ;;
    ssh)
        [ $# -lt 2 ] && { echo "Error: ssh requires a host name"; usage; }
        cmd_ssh "$2"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
