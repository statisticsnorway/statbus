#!/bin/bash
#
# Cloud fleet management for StatBus on niue.statbus.org
#
# This is an OPERATOR tool, not a product feature.
# ./sb manages a single installation. This script manages the fleet.
#
# Usage:
#   ./cloud.sh status              Show version, channel, and name on all servers
#   ./cloud.sh notify              Tell servers to check for updates (non-disruptive)
#   ./cloud.sh upgrade             Force all servers to apply latest now (via upgrade service)
#   ./cloud.sh install <target>    Smart install: tries upgrade service first; full bootstrap if unreachable
#   ./cloud.sh install <target> <version>  Pin to specific version — always full bootstrap
#   ./cloud.sh install all         Install ALL servers (smart, in sequence)
#   ./cloud.sh tail <target>       Follow upgrade log; auto-disconnects on completion
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
# ua (Ukraine) and gh (Ghana) were born 2026-08 from
# create-new-statbus-installation.sh as ordinary slots on this host; this
# list must gain every new slot the day it is created — a slot missing
# here is invisible to fleet upgrades (STATBUS-320's Ukraine/Ghana gap).
# tcc was torn down (STATBUS-321 phase 4a): box, user, and containers gone,
# DNS removed. Port offset 4 is free for the next slot.
SERVERS="statbus_dev statbus_demo statbus_et statbus_jo statbus_ma statbus_mw statbus_ug statbus_ua statbus_gh"
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
    echo "  status                     Show version, channel, and name on all servers"
    echo "  health [target]            Upgrade health: service state, last activity, upgrade status"
    echo "  notify                     Tell servers to check for updates (non-disruptive)"
    echo "  upgrade                    Force all servers to apply latest via upgrade service"
    echo "  install <target>           Smart install: upgrade service first, full bootstrap fallback"
    echo "  install <target> <version> Pin to version — always full bootstrap, no fast-path"
    echo "  install all [version]      Install ALL servers in sequence"
    echo "  tail <target>              Follow upgrade log; auto-disconnects on completion"
    echo "  rescue <target>            Alias for install"
    echo "  create <code> <name> <version>  Create new cloud installation at a named release"
    echo "  inspect                    Show credentials for all installations"
    echo "  wipe <server>              DESTRUCTIVE: delete DB and recreate"
    echo ""
    echo "  migrate-down <server> <migration>  RETIRED with the edge channel"
    echo "  migrate-up <server>               RETIRED with the edge channel"
    echo ""
    echo "Servers: $SERVERS"
    echo "or a channel: stable | prerelease"
    exit 1
}

ssh_server() {
    local server="$1"
    shift
    ssh -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "${server}@${HOST}" "$@"
}

# NOTE: there is deliberately NO stop_upgrade_service here (STATBUS-041,
# sibling of STATBUS-040 / the deploy-stop footgun). `systemctl --user
# stop` sends SIGTERM, and an in-flight upgrade process catches TERM,
# cancels its context, and ROLLS BACK — on a wedged slot that restores a
# stale snapshot over the live DB. Both of the old rationales for a
# pre-install stop are false:
#   - mutex: `./sb install` (post-STATBUS-039) REFUSES a genuinely-
#     progressing upgrade (deploy reports failure, operator retries) and
#     TAKES OVER a crash-looping unit (NRestarts >= 3) with a SIGKILL-class
#     quiesce — no handler runs, no rollback fires.
#   - "text file busy": every binary-replacement path is an atomic rename —
#     install.sh places ./sb via curl-to-sb.tmp + mv, and the build-from-
#     source path does `mv sb-linux-amd64 sb`. rename(2) swaps the directory
#     entry while the running process keeps its old inode; ETXTBSY only
#     fires on write-in-place, which no path does.
# The per-slot unit instance is statbus-upgrade@<server>.service (the
# suffix is the deployment user; see cli/cmd/install.go:serviceInstance).

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

# read_server_metadata returns the values used by both status and live channel
# targeting in one SSH round-trip. UPGRADE_CHANNEL comes from the generated .env
# because it contains the live derived value (STATBUS-307); the display name is
# the operator-authored DEPLOYMENT_SLOT_NAME in .env.config.
read_server_metadata() {
    local server="$1"
    ssh_server "$server" '
        cd statbus 2>/dev/null || exit 1
        ver=$(./sb --version 2>/dev/null | head -1)
        channel=$(sed -n "s/^UPGRADE_CHANNEL=//p" .env 2>/dev/null | head -1)
        name=$(sed -n "s/^DEPLOYMENT_SLOT_NAME=//p" .env.config 2>/dev/null | head -1)
        [ -n "$ver" ] && [ -n "$channel" ] && [ -n "$name" ] || exit 1
        printf "%s|%s|%s\n" "$ver" "$channel" "$name"
    '
}

is_channel() {
    [ "$1" = "stable" ] || [ "$1" = "prerelease" ]
}

# resolve_target_servers expands all or a live channel to server names. A box
# whose metadata cannot be read is reported and skipped rather than guessed.
resolve_target_servers() {
    local target="$1"
    if [ "$target" = "all" ]; then
        echo "$SERVERS"
        return
    fi
    if ! is_channel "$target"; then
        validate_server "$target"
        echo "$target"
        return
    fi

    local server metadata channel matches=""
    for server in $SERVERS; do
        if ! metadata=$(read_server_metadata "$server" 2>/dev/null); then
            echo "  $server: channel read failed; skipping" >&2
            continue
        fi
        IFS='|' read -r _ channel _ <<< "$metadata"
        if [ "$channel" = "$target" ]; then
            matches="${matches:+$matches }$server"
        fi
    done
    if [ -z "$matches" ]; then
        echo "Error: no readable servers found on channel '$target'" >&2
        return 1
    fi
    echo "$matches"
}

cmd_status() {
    echo "StatBus Cloud Status"
    echo "===================="
    for server in $SERVERS; do
        local metadata version channel name
        if ! metadata=$(read_server_metadata "$server" 2>/dev/null); then
            printf "  %-16s METADATA READ FAILED\n" "$server:"
            continue
        fi
        IFS='|' read -r version channel name <<< "$metadata"
        version="${version#sb version }"
        version="${version/ (commit / (}"
        printf "  %-16s %-31s %-12s %s\n" "$server:" "$version" "$channel" "$name"
    done
}

# cmd_health_one gathers upgrade-subsystem health for one server in a single
# SSH call. Outputs one formatted line. Designed to run in parallel.
cmd_health_one() {
    local server="$1"
    local result
    result=$(ssh_server "$server" "
        cd statbus 2>/dev/null || { printf 'NO_DIR|||'; exit; }
        ver=\$(./sb --version 2>/dev/null | head -1 || echo 'UNKNOWN')
        svc=\$(systemctl --user is-active 'statbus-upgrade@${server}.service' 2>/dev/null || echo 'unknown')
        hb='tmp/upgrade-heartbeat'
        if [ -f \"\$hb\" ]; then
            hb_ts=\$(cat \"\$hb\" | tr -d '[:space:]')
            now=\$(date +%s); age=\$((now - hb_ts))
            if   [ \"\$age\" -lt 60 ];   then progress=\"\${age}s ago\"
            elif [ \"\$age\" -lt 3600 ]; then progress=\"\$((age/60))m ago\"
            else progress=\"stale \$((age/3600))h\"; fi
        else
            last=\$(journalctl --user -u 'statbus-upgrade@${server}.service' \
                -n 1 -o short-unix --no-pager 2>/dev/null | awk '{print int(\$1)}')
            if [ -n \"\$last\" ] && [ \"\$last\" -gt 0 ] 2>/dev/null; then
                now=\$(date +%s); age=\$((now - last))
                if   [ \"\$age\" -lt 60 ];   then progress=\"\${age}s ago\"
                elif [ \"\$age\" -lt 3600 ]; then progress=\"\$((age/60))m ago\"
                else progress=\"stale \$((age/3600))h\"; fi
            else
                progress='no data'
            fi
        fi
        state=\$(./sb upgrade list 2>/dev/null \
            | grep -oE 'completed|failed|in progress|in_progress|rolled_back|pending' | head -1)
        [ -z \"\$state\" ] && state='none'
        printf '%s|%s|%s|%s' \"\$ver\" \"\$svc\" \"\$progress\" \"\$state\"
    " 2>/dev/null) || result="SSH FAILED|||"

    if [ -z "$result" ] || [ "$result" = "SSH FAILED|||" ]; then
        printf "  %-22s SSH FAILED\n" "$server"
        return
    fi

    local ver svc progress state flag
    IFS='|' read -r ver svc progress state <<< "$result"
    flag=""
    [ "${svc:-unknown}" != "active" ] && flag=" ← service ${svc:-unknown}"
    echo "${state:-}" | grep -qE 'in[_ ]progress' && flag="${flag} ← WEDGED?"
    printf "  %-22s %-12s service=%-10s last=%-18s upgrade=%s%s\n" \
        "$server" "${ver:-UNKNOWN}" "${svc:-unknown}" "${progress:-?}" "${state:-none}" "$flag"
}

# cmd_health shows upgrade health for one or all servers, in parallel.
cmd_health() {
    local target="${1:-all}"
    local targets
    targets=$(resolve_target_servers "$target")
    echo "StatBus Cloud Health"
    echo "===================="
    if [ "$target" = "all" ] || is_channel "$target"; then
        local tmpdir pids=()
        tmpdir=$(mktemp -d)
        for server in $targets; do
            cmd_health_one "$server" > "$tmpdir/$server" &
            pids+=($!)
        done
        wait "${pids[@]}"
        for server in $targets; do
            cat "$tmpdir/$server"
        done
        rm -rf "$tmpdir"
    else
        cmd_health_one "$targets"
    fi
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
    local targets
    targets=$(resolve_target_servers "$target")

    if [ "$target" = "all" ] || is_channel "$target"; then
        echo "Installing $target servers${version:+ (pinned to $version)}"
        echo "======================"
        for server in $targets; do
            echo ""
            echo "--- $server ---"
            cmd_install_one "$server" "$version"
        done
    else
        cmd_install_one "$targets" "$version"
    fi
}

# trust_flag returns the --trust-github-user flag for ./sb install if configured.
trust_flag() {
    local user="${1:-}"
    if [ -n "$user" ]; then
        echo "--trust-github-user $user"
    fi
}

# Migration immutability is a RELEASE-CUT concern, enforced by `./sb release
# prerelease` / `release stable` preflight (checkMigrationImmutability in
# cli/cmd/release.go). The install-time check that used to live here was
# wrong-layer: it diffed git history between two HEADs on the slot, which
# bears no relationship to what's recorded in db.migration. A migrate-down
# (which clears the db.migration row) couldn't satisfy a git-history-based
# check, producing an infinite loop on operators recovering from a known-
# corrected migration. Removed 2026-05-22 after the loop bit a dev recovery.
# Release-cut gate remains authoritative; install just applies forward.

# cmd_migrate_down is RETIRED — see the refusal below for why.
# Takes a migration number — rolls back until that migration is gone.
# This is a manual, explicit, operator-invoked command — the upgrade
# service NEVER runs down migrations.
cmd_migrate_down() {
    local server="$1"
    local migration="$2"

    # EDGE IS RETIRED (King, 2026-08-19), and this command went with it.
    #
    # It was only ever permitted on an edge box, and that was not an arbitrary
    # restriction: rolling a migration BACKWARDS is safe only where migrations
    # are not immutable, and edge was the one channel that applied ungated master
    # commits. Every remaining box follows released tags, where migrations ARE
    # immutable — a released migration that wrote wrong data is corrected by a
    # FORWARD repair migration, never by rolling the released one back.
    #
    # The rollback body is deleted rather than left behind a guard: dead code
    # under a refusal reads as "this could still be right", and this one would be
    # reached for at exactly the wrong moment, on a production box, under
    # pressure.
    echo "Error: cloud.sh migrate-down is retired together with the edge channel."
    echo "  Requested: rollback of migration ${migration:-<none>} on ${server:-<none>}."
    echo "  Released migrations are IMMUTABLE. To correct one, ship a forward repair"
    echo "  migration and release it: ./sb migrate new --description \"fix_...\""
    echo "  See AGENTS.md (STATBUS-172) for how to test a repair against data written"
    echo "  under the corruption, not just against seed state."
    exit 1
}

# cmd_migrate_up is RETIRED — see the refusal below for why.
# Symmetric counterpart to migrate-down. Edge-only.
cmd_migrate_up() {
    local server="$1"

    # Retired with the edge channel (King, 2026-08-19) — the symmetric
    # counterpart to migrate-down above, and edge-only for the same reason.
    #
    # Applying pending migrations is not a thing an operator does to a release
    # box by hand: the upgrade pipeline runs migrations as part of the upgrade it
    # is performing, inside the backup/health-check/rollback envelope. Running
    # them outside that envelope is how a box ends up half-migrated with no
    # snapshot to go back to.
    echo "Error: cloud.sh migrate-up is retired together with the edge channel."
    echo "  Requested on: ${server:-<none>}."
    echo "  Migrations are applied by the upgrade itself, inside its backup and"
    echo "  rollback envelope. To move a box forward, schedule a candidate:"
    echo "    ./sb upgrade register <version> && ./sb upgrade schedule <version>"
    exit 1
}

# cmd_tail_one tails the upgrade service journal for one server and
# auto-disconnects when a terminal state is logged. Prints the final
# upgrade status afterwards.
# Optional $2 = target_version: narrows the exit pattern to that specific
# upgrade so stale recovery log lines for previous versions don't cause
# a premature exit.
cmd_tail_one() {
    local server="$1"
    local target_version="${2:-}"
    # Build the awk exit pattern locally before SSH so we avoid nested-quote
    # hell. The pattern is embedded in the remote awk /.../ regex via double-
    # quote expansion of the outer SSH string. Version strings (sha-*, v*.*)
    # contain no single quotes or shell metacharacters, so expansion is safe.
    local awk_pattern
    if [ -n "$target_version" ]; then
        awk_pattern="Upgrade to ${target_version} .*(completed|failed)|FAILED:"
    else
        awk_pattern="Upgrade to .*(completed|failed)|FAILED:"
    fi
    echo "--- Tailing upgrade log for $server (auto-disconnect on completion) ---"
    ssh_server "$server" \
        "journalctl --user -u 'statbus-upgrade@${server}.service' -o cat -f -n 50 2>&1 | \
         awk '/${awk_pattern}/{print; fflush(); exit} {print; fflush()}'" \
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
    local targets
    targets=$(resolve_target_servers "$target")
    if [ "$target" = "all" ] || is_channel "$target"; then
        local pids=()
        for server in $targets; do
            cmd_tail_one "$server" &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        cmd_tail_one "$targets"
    fi
}

cmd_install_one() {
    # Idempotent install flow:
    #   install → ensure_service_started
    #
    # Re-running `./cloud.sh install <server>` after any partial failure
    # (SSH drop, Ctrl-C, transient error) is safe — every step is rerun-safe.
    # The `./sb install` dispatcher handles the running service itself
    # (STATBUS-039): a stale flag reconciles via StateCrashedUpgrade; a
    # crash-looping unit is taken over with a SIGKILL-class quiesce; a
    # genuinely-progressing upgrade makes install REFUSE — cloud.sh then
    # reports the failure and the operator retries later. Do NOT stop the
    # service first: systemctl stop is SIGTERM, which an in-flight upgrade
    # catches and answers with a rollback (snapshot restore) — the deploy-
    # stop footgun (STATBUS-040/-041). No binary-replacement path needs a
    # stop either (all are atomic renames).
    #
    # ensure_service_started runs at the end (and on the failure-return path)
    # so a cloud.sh exit always leaves the server with the upgrade service
    # running, not stopped.
    local server="$1"
    local version="${2:-}"
    local exit_code=0

    # Resolve trust key user: explicit env var first, then remote .env.config
    # written by a prior successful run — operator sets it once, remembered forever.
    local resolved_trust_user="$CLOUD_TRUST_KEY_USER"
    if [ -z "$resolved_trust_user" ]; then
        resolved_trust_user=$(ssh_server "$server" \
            "cd statbus && ./sb dotenv -f .env.config get TRUST_GITHUB_USER 2>/dev/null" \
            2>/dev/null || true)
    fi

    # Fast path: if no version is pinned, try the upgrade service first.
    # If it accepts the request (exit 0), tail the journal and return.
    # If it fails (service not running, DB down, etc.), fall through to the
    # full bootstrap install below.
    # Version-skew guard: if remote binary != local binary, skip fast-path
    # and always bootstrap (item #2 rc.64 fix — dev's looping service returned
    # 0 on NOTIFY but never completed, blocking indefinitely).
    if [ -z "$version" ]; then
        local remote_commit local_commit
        remote_commit=$(ssh_server "$server" "cd statbus && ./sb --version 2>/dev/null" \
            | grep -oE 'commit [a-f0-9]+' | awk '{print $2}') || remote_commit=""
        local_commit=$(./sb --version 2>/dev/null | grep -oE 'commit [a-f0-9]+' | awk '{print $2}')

        if [ -z "$remote_commit" ] || [ "$remote_commit" != "$local_commit" ]; then
            echo "Version skew detected: remote=$remote_commit local=$local_commit — skipping fast-path, using bootstrap"
            # Fall through to bootstrap block (do NOT enter the upgrade-service fast-path)
        else
            echo "Trying upgrade service on $server..."
            # Capture exit code WITHOUT triggering set -e. Pre-fix: a plain
            # `apply_out=$(ssh ...)` assignment is part of the surrounding
            # `set -euo pipefail` scope, so a non-zero SSH exit kills cloud.sh
            # before line `apply_rc=$?` runs — operator sees only this echo
            # and a bare prompt (anti-fail-fast). The `|| apply_rc=$?` form
            # captures the failure code AND short-circuits set -e so the
            # fall-through to the bootstrap install fires.
            local apply_out apply_rc=0
            apply_out=$(ssh_server "$server" "cd statbus && ./sb upgrade apply-latest" 2>&1) || apply_rc=$?
            echo "$apply_out"
            # Skip-current short-circuit: when apply-latest detects the slot
            # is already at the latest, it prints "Already at <ver> ..." and
            # exits 0 without scheduling — no NOTIFY upgrade_apply, so the
            # daemon doesn't run a pipeline. cmd_tail_one would tail forever
            # waiting for a completion line that won't come. Detect the
            # marker and return cleanly.
            if [ "$apply_rc" -eq 0 ] && echo "$apply_out" | grep -q "^Already at "; then
                return 0
            fi
            if [ "$apply_rc" -eq 0 ]; then
                # Extract target version from apply-latest output, e.g.:
                #   Sent: NOTIFY upgrade_apply, '9bf48bb8'             # commit_short
                #   Sent: NOTIFY upgrade_apply, 'v2026.04.0-rc.55'     # release tag
                # Passed to cmd_tail_one so the awk exit pattern is version-specific,
                # preventing stale recovery lines for previous upgrades from terminating early.
                local target_version
                target_version=$(echo "$apply_out" | grep "upgrade_apply" | grep -oE "'[^']+'" | tr -d "'" | head -1)
                cmd_tail_one "$server" "$target_version"
                return $?
            fi
            echo "Upgrade service not responsive — falling back to full bootstrap install..."
        fi
    fi

    # (The edge install strategy stood here and is retired with the channel —
    # King, 2026-08-19. It checked out origin/master and built `sb` from source
    # when HEAD carried no published binary, which is what an always-latest box
    # required. Every box now installs a NAMED candidate's published binary, so
    # there is one procurement path instead of two, and no box builds from
    # source during a deploy. The per-server channel READ that chose between the
    # two strategies went with it — there is one strategy now, so there is
    # nothing left to choose.)
    if [ -n "$version" ]; then
        # Pinned: verify artifacts for the specific version before touching the server.
        echo "Checking release artifacts for $version are ready..."
        if ! "$SCRIPT_DIR/sb" release check --tag "$version"; then
            echo "--- Release artifacts for $version not ready. Retry later. ---"
            return 1
        fi
        echo "Installing $server at $version via $INSTALL_URL ..."
        ssh_server "$server" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --version $version $(trust_flag "$resolved_trust_user")" 2>&1 \
            || exit_code=$?
    else
        # Gate: verify release artifacts are fully published before touching
        # the server. If CI is still uploading assets or pushing
        # images, abort early — the server stays up and the operator retries.
        # Rc.63: use --channel so the check resolves to the
        # current latest RC instead of treating "prerelease" as a
        # literal tag.
        echo "Checking release artifacts for channel prerelease are ready..."
        if ! "$SCRIPT_DIR/sb" release check --channel prerelease; then
            echo "--- Release artifacts not ready. Retry in ~5 minutes. ---"
            return 1
        fi
        echo "Installing $server via $INSTALL_URL ..."
        # Step 1: Run install.sh as the app user. No pre-stop: install.sh
        # swaps ./sb via atomic rename (sb.tmp + mv, never ETXTBSY), and
        # `./sb install` refuses-or-takes-over a running upgrade itself
        # (STATBUS-039/-041).
        # Exit code 42 = service needs root (not a failure).
        ssh_server "$server" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --channel prerelease $(trust_flag "$resolved_trust_user")" 2>&1 \
            || exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "--- $server install FAILED (exit code $exit_code) ---"
        if [ -z "$resolved_trust_user" ]; then
            echo ""
            echo "If this failed because of an invalid signing key, re-run with:"
            echo "  CLOUD_TRUST_KEY_USER=jhf ./cloud.sh install $server"
            echo ""
        fi
        # Do NOT call ensure_service_started on failure — starting the upgrade
        # service after a broken install can hang (systemctl waiting on a broken
        # binary/DB). The operator re-runs ./cloud.sh install which calls it on success.
        return 1
    fi

    # Persist trust user for future runs so CLOUD_TRUST_KEY_USER need not
    # be set again. Idempotent — safe to re-write the same value.
    if [ -n "$resolved_trust_user" ]; then
        ssh_server "$server" \
            "cd statbus && ./sb dotenv -f .env.config set TRUST_GITHUB_USER '$resolved_trust_user'" \
            2>/dev/null || true
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
    local version="$3"
    exec "$SCRIPT_DIR/ops/create-new-statbus-installation.sh" "$code" "$name" "$version"
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
    health)
        cmd_health "${2:-all}"
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
        [ $# -lt 4 ] && { echo "Error: create requires <code>, <name>, and <version>"; echo "Example: $0 create pk \"Pakistan StatBus\" v2026.08.0-rc.10"; exit 1; }
        cmd_create "$2" "$3" "$4"
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
