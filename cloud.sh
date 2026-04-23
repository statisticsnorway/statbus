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
#   ./cloud.sh upgrade             Force all servers to apply latest now (via upgrade service)
#   ./cloud.sh install <server>    Smart install: tries upgrade service first; full bootstrap if unreachable
#   ./cloud.sh install <server> <version>  Pin to specific version — always full bootstrap
#   ./cloud.sh install all         Install ALL servers (smart, in sequence)
#   ./cloud.sh tail <server|all>   Follow upgrade log; auto-disconnects on completion
#   ./cloud.sh rescue <server>     Alias for install (backwards compat)
#   ./cloud.sh wipe <server>       DESTRUCTIVE: delete DB and recreate from scratch
#
# Escalation levels:
#   notify   — gentle. Servers discover new version. Admin chooses when to upgrade.
#   upgrade  — firm. All servers apply latest NOW via upgrade service (non-disruptive binary).
#   install  — smart. Tries upgrade service first (fast path); falls back to full bootstrap
#              (stop service, replace binary, re-run install) only if service is unreachable.
#              Pinning a version always takes the full bootstrap path.
#   tail     — observe. Streams upgrade service journal; exits automatically on completion.
#   create   — provision. Creates new deployment slot (DNS, user, workflows, etc.)
#   inspect  — read-only. Shows credentials/URLs for all deployment slots.
#   wipe     — destructive. Deletes database and recreates. Data is lost.
#
set -euo pipefail

# DEBUG=1 ./cloud.sh <command> traces every command to stderr via `set -x`.
# Matches the convention in dev.sh.
if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
    set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Multi-tenant cloud slots on niue. `statbus_no` was removed on 2026-04-21
# when Norway migrated to the dedicated standalone box rune.statbus.org;
# standalone hosts are NOT managed by cloud.sh (they use the per-host
# ./sb and the standalone deploy workflows, see doc/CLOUD.md §Standalone).
SERVERS="statbus_dev statbus_demo statbus_et statbus_jo statbus_ma statbus_tcc statbus_ug"
HOST="niue.statbus.org"
INSTALL_URL="https://statbus.org/install.sh"
# GitHub username whose signing key should be trusted on each server.
# Passed as --trust-github-user to ./sb install so the installer handles
# key validation, removal of invalid keys, and re-fetching in one pass.
# No default — install must fail if the wrong key is configured, forcing
# the operator to explicitly provide the fix:
#   CLOUD_TRUST_KEY_USER=jhf ./cloud.sh install all
CLOUD_TRUST_KEY_USER="${CLOUD_TRUST_KEY_USER:-}"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  status                     Show version on all servers"
    echo "  notify                     Tell servers to check for updates (non-disruptive)"
    echo "  upgrade                    Force all servers to apply latest via upgrade service"
    echo "  install <server>           Smart install: upgrade service first, full bootstrap fallback"
    echo "  install <server> <version> Pin to version — always full bootstrap, no fast-path"
    echo "  install all [version]      Install ALL servers in sequence"
    echo "  tail <server|all>          Follow upgrade log; auto-disconnects on completion"
    echo "  rescue <server>            Alias for install"
    echo "  create <code> <name>       Create new cloud installation"
    echo "  inspect                    Show credentials for all installations"
    echo "  wipe <server>              DESTRUCTIVE: delete DB and recreate"
    echo ""
    echo "  migrate-down <server> <migration>  Roll back to before this migration (edge only)"
    echo "  migrate-up <server>               Apply pending migrations (edge only)"
    echo ""
    echo "Servers: $SERVERS"
    exit 1
}

ssh_server() {
    local server="$1"
    shift
    ssh -o ConnectTimeout=10 "${server}@${HOST}" "$@"
}

# Stop the user-level upgrade service so the `./sb` binary can be
# replaced without "text file busy". Idempotent — `systemctl stop` on a
# stopped unit is a safe no-op. Any stale upgrade-in-progress flag left
# on disk is reconciled by `./sb install` itself (StateCrashedUpgrade
# dispatch), so cloud.sh doesn't need to do that here.
stop_upgrade_service() {
    local server="$1"
    ssh_server "$server" "systemctl --user stop statbus-upgrade@${server}.service 2>/dev/null || true" 2>&1
}

# Ensure the user-level upgrade service is running on exit. Idempotent —
# `systemctl start` on a running unit is a no-op. Used at the end of
# `cmd_install_one` (and on its error paths) so that any cloud.sh exit
# leaves the server in a normal "service running" state, not "stopped
# pending operator intervention".
ensure_service_started() {
    local server="$1"
    ssh_server "$server" "systemctl --user start statbus-upgrade@${server}.service" 2>&1 || true
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
    local version="${2:-}"
    validate_server "$target"

    if [ "$target" = "all" ]; then
        echo "Installing ALL servers${version:+ (pinned to $version)}"
        echo "======================"
        for server in $SERVERS; do
            echo ""
            echo "--- $server ---"
            cmd_install_one "$server" "$version"
        done
    else
        cmd_install_one "$target" "$version"
    fi
}

# trust_flag returns the --trust-github-user flag for ./sb install if configured.
trust_flag() {
    if [ -n "$CLOUD_TRUST_KEY_USER" ]; then
        echo "--trust-github-user $CLOUD_TRUST_KEY_USER"
    fi
}

# check_migration_immutability detects if any deployed migration was modified
# between the server's previous HEAD and the new HEAD. Edge-only — release
# channels use tagged versions where the RC preflight already enforces this.
# Returns 0 if clean, 1 if modified (with actionable instructions printed).
check_migration_immutability() {
    local server="$1"
    # Get the previous HEAD (before our checkout) from git reflog.
    local prev_head
    prev_head=$(ssh_server "$server" "cd statbus && git rev-parse 'HEAD@{1}' 2>/dev/null" 2>/dev/null || true)
    if [ -z "$prev_head" ]; then
        return 0  # no reflog (fresh clone) — nothing to check
    fi

    # Diff migrations/ between previous HEAD and current HEAD.
    # Only care about M (modified) and D (deleted), not A (added).
    local modified
    modified=$(ssh_server "$server" \
        "cd statbus && git diff --name-status $prev_head..HEAD -- migrations/ 2>/dev/null | grep -E '^[MD]'" \
        2>/dev/null || true)

    if [ -z "$modified" ]; then
        return 0  # no modifications to existing migrations
    fi

    echo ""
    echo "*** MIGRATION IMMUTABILITY VIOLATION ***"
    echo "The following deployed migration(s) were modified or deleted:"
    echo "$modified" | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "The upgrade service only runs forward (up). To apply the modified"
    echo "migration, you must manually roll back to before it, then re-apply."
    echo ""

    # Extract the earliest modified migration number for the suggested command.
    local earliest
    earliest=$(echo "$modified" | awk -F'[/_]' '{print $2}' | sort | head -1)
    echo "Run:"
    echo "  ./cloud.sh migrate-down $server $earliest"
    echo "Then re-run:"
    echo "  ./cloud.sh install $server"
    echo ""
    return 1
}

# cmd_migrate_down rolls back a specific migration on an edge server.
# Takes a migration number — rolls back until that migration is gone.
# This is a manual, explicit, operator-invoked command — the upgrade
# service NEVER runs down migrations.
cmd_migrate_down() {
    local server="$1"
    local migration="$2"

    if [ -z "$server" ] || [ -z "$migration" ]; then
        echo "Usage: ./cloud.sh migrate-down <server> <migration>"
        echo "Example: ./cloud.sh migrate-down statbus_dev 20260417130648"
        exit 1
    fi

    validate_server "$server"

    local channel
    channel=$(ssh_server "$server" "cd statbus && ./sb dotenv -f .env.config get UPGRADE_CHANNEL 2>/dev/null" 2>/dev/null || echo "prerelease")
    if [ "$channel" != "edge" ]; then
        echo "Error: migrate-down is only supported on edge channel servers."
        echo "  $server is on channel: $channel"
        echo "  Release/prerelease servers use immutable migrations enforced by RC preflight."
        exit 1
    fi

    echo "Rolling back migration $migration on $server..."
    local current
    while true; do
        current=$(ssh_server "$server" \
            "cd statbus && echo 'SELECT MAX(version) FROM public.schema_migrations;' | ./sb psql -t -A" \
            2>/dev/null || true)
        if [ -z "$current" ] || [ "$current" -lt "$migration" ]; then
            echo "Migration $migration is no longer applied."
            break
        fi
        echo "  Rolling back migration $current..."
        ssh_server "$server" "cd statbus && ./sb migrate down" 2>&1
    done
    echo "Done. Re-run: ./cloud.sh install $server"
}

# cmd_migrate_up applies pending migrations on an edge server.
# Symmetric counterpart to migrate-down. Edge-only.
cmd_migrate_up() {
    local server="$1"
    validate_server "$server"

    local channel
    channel=$(ssh_server "$server" "cd statbus && ./sb dotenv -f .env.config get UPGRADE_CHANNEL 2>/dev/null" 2>/dev/null || echo "prerelease")
    if [ "$channel" != "edge" ]; then
        echo "Error: migrate-up is only supported on edge channel servers."
        echo "  $server is on channel: $channel"
        exit 1
    fi

    echo "Applying pending migrations on $server..."
    ssh_server "$server" "cd statbus && ./sb migrate up" 2>&1
    echo "Done."
}

# cmd_tail_one tails the upgrade service journal for one server and
# auto-disconnects when a terminal state is logged. Prints the final
# upgrade status afterwards.
cmd_tail_one() {
    local server="$1"
    echo "--- Tailing upgrade log for $server (auto-disconnect on completion) ---"
    ssh_server "$server" \
        "journalctl --user -u 'statbus-upgrade@${server}.service' -o cat -f -n 50 2>&1 | \
         awk '/Upgrade to .*(completed|failed)|FAILED:/{print; fflush(); exit} {print; fflush()}'" \
        || true
    echo "--- Log tail disconnected for $server ---"
    echo "Final upgrade status on $server:"
    # Poll until the DB reflects the terminal state (service commits the
    # in_progress→completed transition after logging "Installation complete!").
    # Bounded at 8 tries × 2 s = 16 s max; exits early once state clears.
    ssh_server "$server" \
        'cd statbus && i=0; while [ $i -lt 8 ]; do
             out=$(./sb upgrade list 2>&1)
             echo "$out" | head -5 | grep -qE "in[_ ]progress" || { echo "$out"; exit 0; }
             i=$((i+1)); [ $i -lt 8 ] && sleep 2
         done; ./sb upgrade list' 2>&1 || true
}

# cmd_tail tails the upgrade log for one server or all servers in parallel.
cmd_tail() {
    local target="$1"
    validate_server "$target"
    if [ "$target" = "all" ]; then
        local pids=()
        for server in $SERVERS; do
            cmd_tail_one "$server" &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        cmd_tail_one "$target"
    fi
}

cmd_install_one() {
    # Idempotent install flow:
    #   stop_upgrade_service → install → ensure_service_started
    #
    # Re-running `./cloud.sh install <server>` after any partial failure
    # (SSH drop, Ctrl-C, transient error) is safe — every step is rerun-safe.
    # The `./sb install` dispatcher handles stale upgrade flags itself
    # (StateCrashedUpgrade reconciles and re-dispatches), so cloud.sh only
    # needs to stop the service so the binary can be replaced.
    #
    # ensure_service_started runs at the end (and on the failure-return path)
    # so a cloud.sh exit always leaves the server with the upgrade service
    # running, not stopped.
    local server="$1"
    local version="${2:-}"
    local exit_code=0

    # Fast path: if no version is pinned, try the upgrade service first.
    # If it accepts the request (exit 0), tail the journal and return.
    # If it fails (service not running, DB down, etc.), fall through to the
    # full bootstrap install below.
    if [ -z "$version" ]; then
        echo "Trying upgrade service on $server..."
        if ssh_server "$server" "cd statbus && ./sb upgrade apply-latest" 2>&1; then
            cmd_tail_one "$server"
            return $?
        fi
        echo "Upgrade service not responsive — falling back to full bootstrap install..."
    fi

    # Check the server's upgrade channel to decide install strategy.
    # Edge channel tracks master (build from source). Others use tagged releases.
    local channel
    channel=$(ssh_server "$server" "cd statbus && ./sb dotenv -f .env.config get UPGRADE_CHANNEL 2>/dev/null" 2>/dev/null || echo "prerelease")

    if [ "$channel" = "edge" ]; then
        if [ -n "$version" ]; then
            echo "Installing $server (edge — pinned to $version)..."
            # Pinned edge: checkout the specified tag and download its release binary.
            ssh_server "$server" "cd statbus && git fetch origin --tags --force --quiet && git checkout $version --quiet" 2>&1 \
                || { echo "--- $server FAILED: git fetch/checkout $version (exit $?) ---"; \
                     ensure_service_started "$server"; return 1; }
            echo "Downloading release binary for $version..."
            ssh_server "$server" \
                "cd statbus && curl -fsSL https://github.com/statisticsnorway/statbus/releases/download/${version}/sb-linux-amd64 -o sb-linux-amd64 && chmod +x sb-linux-amd64" 2>&1 \
                || { echo "--- $server FAILED: download binary for $version (exit $?) ---"; \
                     ensure_service_started "$server"; return 1; }
        else
            echo "Installing $server (edge channel — building from master)..."
            # Edge: pull latest master. If HEAD is a tagged release with a
            # published binary, download it (faster, no Go toolchain needed).
            # Otherwise fall back to building from source.
            ssh_server "$server" "cd statbus && git fetch origin master --tags --force --quiet && git checkout origin/master --quiet" 2>&1 \
                || { echo "--- $server FAILED: git fetch/checkout master (exit $?) ---"; \
                     ensure_service_started "$server"; return 1; }
            # Check if HEAD is a tagged release with a downloadable binary.
            local head_tag
            head_tag=$(ssh_server "$server" "cd statbus && git describe --exact-match HEAD 2>/dev/null" 2>/dev/null || true)
            if [ -n "$head_tag" ]; then
                echo "HEAD is tagged ($head_tag) — checking for release binary..."
                if "$SCRIPT_DIR/sb" release check --tag "$head_tag" 2>/dev/null; then
                    echo "Release binary available — downloading instead of building."
                    ssh_server "$server" \
                        "cd statbus && curl -fsSL https://github.com/statisticsnorway/statbus/releases/download/${head_tag}/sb-linux-amd64 -o sb-linux-amd64 && chmod +x sb-linux-amd64" 2>&1 \
                        || { echo "--- $server FAILED: download binary for $head_tag (exit $?) ---"; \
                             ensure_service_started "$server"; return 1; }
                else
                    echo "Release binary not ready — building from source..."
                    ssh_server "$server" "cd statbus && export PATH=/home/linuxbrew/.linuxbrew/bin:\$PATH && ./dev.sh build-sb" 2>&1 \
                        || { echo "--- $server FAILED: build from source (exit $?) ---"; \
                             ensure_service_started "$server"; return 1; }
                fi
            else
                echo "HEAD is untagged — building from source..."
                ssh_server "$server" "cd statbus && export PATH=/home/linuxbrew/.linuxbrew/bin:\$PATH && ./dev.sh build-sb" 2>&1 \
                    || { echo "--- $server FAILED: build from source (exit $?) ---"; \
                         ensure_service_started "$server"; return 1; }
            fi
        fi
        # Check for modified migrations before proceeding. Edge channel only.
        if ! check_migration_immutability "$server"; then
            ensure_service_started "$server"
            return 1
        fi

        # Stop user-level service before replacing binary — systemd --user
        # restarts it on exit (Restart=always), and the running process holds
        # the binary open → "text file busy" on mv.
        stop_upgrade_service "$server"
        ssh_server "$server" "cd statbus && mv sb-linux-amd64 sb" 2>&1 \
            || { echo "--- $server FAILED: replace binary (exit $?) ---"; \
                 ensure_service_started "$server"; return 1; }
        # ./sb install detects the service is stopped and restarts it (user-level, no root needed).
        # --trust-github-user validates/repairs the signing key in one pass.
        ssh_server "$server" "cd statbus && ./sb install $(trust_flag)" 2>&1 \
            || exit_code=$?
    else
        if [ -n "$version" ]; then
            # Pinned: verify artifacts for the specific version before stopping.
            echo "Checking release artifacts for $version are ready..."
            if ! "$SCRIPT_DIR/sb" release check --tag "$version"; then
                echo "--- Release artifacts for $version not ready. Retry later. ---"
                return 1
            fi
            echo "Installing $server at $version via $INSTALL_URL ..."
            stop_upgrade_service "$server"
            ssh_server "$server" \
                "curl -fsSL ${INSTALL_URL} | bash -s -- --version $version $(trust_flag)" 2>&1 \
                || exit_code=$?
        else
            # Gate: verify release artifacts are fully published before stopping
            # the running service. If CI is still uploading assets or pushing
            # images, abort early — the server stays up and the operator retries.
            echo "Checking release artifacts are ready..."
            if ! "$SCRIPT_DIR/sb" release check; then
                echo "--- Release artifacts not ready. Retry in ~5 minutes. ---"
                return 1
            fi
            echo "Installing $server via $INSTALL_URL ..."
            # Stop the user-level upgrade service so install.sh can replace the
            # `./sb` binary without hitting "text file busy". install.sh's
            # install step re-enables and starts the service on completion.
            stop_upgrade_service "$server"
            # Step 1: Run install.sh as the app user.
            # Exit code 42 = service needs root (not a failure).
            ssh_server "$server" \
                "curl -fsSL ${INSTALL_URL} | bash -s -- --prerelease $(trust_flag)" 2>&1 \
                || exit_code=$?
        fi
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "--- $server install FAILED (exit code $exit_code) ---"
        if [ -z "$CLOUD_TRUST_KEY_USER" ]; then
            echo ""
            echo "If this failed because of an invalid signing key, re-run with:"
            echo "  CLOUD_TRUST_KEY_USER=jhf ./cloud.sh install $server"
            echo ""
        fi
        ensure_service_started "$server"
        return 1
    fi

    # Regenerate config so VERSION in .env matches the checked-out code.
    # Must use 'up -d' not 'restart' — restart doesn't re-read .env.
    echo "Regenerating config and restarting app..."
    ssh_server "$server" "cd statbus && ./sb config generate && docker compose up -d app" 2>&1

    # Always leave the upgrade service running on success, regardless of
    # whether install's own service-install step fired (e.g., when running
    # without root and the user-level path was used).
    ensure_service_started "$server"

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
    exec "$SCRIPT_DIR/ops/create-new-statbus-installation.sh" "$code" "$name"
}

cmd_inspect() {
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
        cmd_install "$2" "${3:-}"
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
    migrate-down)
        [ $# -lt 3 ] && { echo "Error: migrate-down requires <server> and <migration>"; echo "Example: $0 migrate-down statbus_dev 20260417130648"; exit 1; }
        cmd_migrate_down "$2" "$3"
        ;;
    migrate-up)
        [ $# -lt 2 ] && { echo "Error: migrate-up requires a server name"; exit 1; }
        cmd_migrate_up "$2"
        ;;
    tail)
        [ $# -lt 2 ] && { echo "Error: tail requires a server name or 'all'"; usage; }
        cmd_tail "$2"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
