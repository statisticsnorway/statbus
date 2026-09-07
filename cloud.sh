#!/bin/bash
#
# Unified fleet management for SSB-operated StatBus boxes
#
# This is an OPERATOR tool, not a product feature.
# ./sb manages a single installation. This script manages the fleet.
#
# Usage:
#   ./cloud.sh status              Show version, channel, name, and group for all boxes
#   ./cloud.sh notify [target]     Tell target boxes to check for updates (non-disruptive)
#   ./cloud.sh upgrade [target]    Force target boxes to apply latest now (via upgrade service)
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
#   create   — provision. Creates a deployment slot at a named release.
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

# Unified SSB-operated fleet registry (STATBUS-337 history: standalone.sh was
# merged here and deleted). Fields: code|group|ssh target|public domain.
# Display name and channel are deliberately absent: they are read live from each
# box via ./sb config show so this registry never becomes configuration truth.
FLEET_REGISTRY=(
    "dev|cloud|statbus_dev@niue.statbus.org|dev.statbus.org"
    "demo|cloud|statbus_demo@niue.statbus.org|demo.statbus.org"
    "et|cloud|statbus_et@niue.statbus.org|et.statbus.org"
    "jo|cloud|statbus_jo@niue.statbus.org|jo.statbus.org"
    "ma|cloud|statbus_ma@niue.statbus.org|ma.statbus.org"
    "mw|cloud|statbus_mw@niue.statbus.org|mw.statbus.org"
    "ug|cloud|statbus_ug@niue.statbus.org|ug.statbus.org"
    "ua|cloud|statbus_ua@niue.statbus.org|ua.statbus.org"
    "gh|cloud|statbus_gh@niue.statbus.org|gh.statbus.org"
    "no|standalone|statbus@rune.statbus.org|no.statbus.org"
)
INSTALL_URL="https://statbus.org/install.sh"
# Renamed by STATBUS-337: CLOUD_TRUST_KEY_USER and STANDALONE_TRUST_KEY_USER
# became FLEET_TRUST_KEY_USER. Passed as --trust-github-user to ./sb install.
# No default. Example: FLEET_TRUST_KEY_USER=jhf ./cloud.sh install all
FLEET_TRUST_KEY_USER="${FLEET_TRUST_KEY_USER:-}"

usage() {
    echo "Usage: $0 <command> [args]"
    echo "Targets: all | <code> | stable | prerelease | cloud | standalone"
    echo "Commands: status, health, notify, upgrade, install, rescue, tail, create, wipe, inspect, import, reimport, ssh"
    echo "For group-only verbs, target 'all' runs eligible entries and prints one skip line for each ineligible entry."
    exit 1
}

upgrade_usage() {
    echo "Usage: $0 upgrade [target] [--yes|--force|-y]"
    echo "Force target boxes to apply latest. Prompts for confirmation unless a confirmation flag is supplied."
    echo "Targets: all | <code> | stable | prerelease | cloud | standalone"
}

registry_entry() {
    local code="$1" entry
    for entry in "${FLEET_REGISTRY[@]}"; do
        [ "${entry%%|*}" = "$code" ] && { echo "$entry"; return 0; }
    done
    return 1
}

all_codes() {
    local entry
    for entry in "${FLEET_REGISTRY[@]}"; do echo "${entry%%|*}"; done
}

registry_entries_for_group() {
    local wanted="$1" entry code group rest
    for entry in "${FLEET_REGISTRY[@]}"; do
        IFS='|' read -r code group rest <<< "$entry"
        [ "$group" = "$wanted" ] && echo "$entry"
    done
}

entry_field() {
    local code="$1" field="$2" entry
    entry=$(registry_entry "$code") || return 1
    echo "$entry" | cut -d'|' -f"$field"
}

ssh_transport() {
    local target="$1"; shift
    ssh -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$target" "$@"
}

# The one transport boundary. Tests stub ssh_transport, while every verb calls
# ssh_entry with a registry code and never constructs an SSH address itself.
ssh_entry() {
    local code="$1" target; shift
    target=$(entry_field "$code" 3) || { echo "Error: unknown box '$code'" >&2; return 1; }
    ssh_transport "$target" "$@"
}

entry_group() { entry_field "$1" 2; }
entry_domain() { entry_field "$1" 4; }
entry_ssh_target() { entry_field "$1" 3; }
service_instance() { entry_ssh_target "$1" | cut -d@ -f1; }

validate_code() {
    registry_entry "$1" >/dev/null || { echo "Error: unknown box '$1'" >&2; return 1; }
}

# Metadata is operational truth from the box. `./sb config show` supplies the
# channel and display name. The version comes from the running box binary.
read_server_metadata() {
    local code="$1"
    # shellcheck disable=SC2016 # This script is evaluated on the remote box.
    ssh_entry "$code" '
        cd statbus 2>/dev/null || exit 1
        ver=$(./sb --version 2>/dev/null | head -1)
        config=$(./sb config show 2>/dev/null)
        channel=$(printf "%s\n" "$config" | sed -n "s/^UPGRADE_CHANNEL=//p" | head -1)
        name=$(printf "%s\n" "$config" | sed -n "s/^DEPLOYMENT_SLOT_NAME=//p" | head -1)
        [ -n "$ver" ] && [ -n "$channel" ] && [ -n "$name" ] || exit 1
        printf "%s|%s|%s\n" "$ver" "$channel" "$name"
    '
}

is_channel() { [ "$1" = stable ] || [ "$1" = prerelease ]; }
is_group() { [ "$1" = cloud ] || [ "$1" = standalone ]; }

resolve_target_codes() {
    local target="$1" code metadata channel matches="" unreadable=""
    if [ "$target" = all ]; then all_codes; return; fi
    if is_group "$target"; then
        registry_entries_for_group "$target" | cut -d'|' -f1
        return
    fi
    if ! is_channel "$target"; then validate_code "$target"; echo "$target"; return; fi
    for code in $(all_codes); do
        if ! metadata=$(read_server_metadata "$code" 2>/dev/null); then
            unreadable="${unreadable:+$unreadable }$code"
            continue
        fi
        IFS='|' read -r _ channel _ <<< "$metadata"
        [ "$channel" = "$target" ] && matches="${matches:+$matches }$code"
    done
    if [ -n "$unreadable" ]; then
        echo "Error: cannot resolve channel '$target'; metadata unreadable for: $unreadable" >&2
        return 1
    fi
    [ -n "$matches" ] || { echo "Error: no readable boxes found on channel '$target'" >&2; return 1; }
    tr ' ' '\n' <<< "$matches"
}
resolve_target_servers() { resolve_target_codes "$@"; }

resolve_single_target() {
    local target="$1" targets; targets=$(resolve_target_codes "$target")
    targets="${targets//$'\n'/ }"; local -a resolved=(); read -r -a resolved <<< "$targets"
    [ "${#resolved[@]}" -eq 1 ] || { echo "Error: target '$target' resolves to ${#resolved[@]} boxes; specify a box code" >&2; return 1; }
    echo "${resolved[0]}"
}

verb_group() {
    case "$1" in
        create|wipe|inspect) echo cloud ;;
        import|reimport|ssh) echo standalone ;;
        *) echo all ;;
    esac
}

assert_verb_target_group() {
    local verb="$1" target="$2" eligible actual code
    eligible=$(verb_group "$verb"); [ "$eligible" = all ] && return 0
    [ "$target" = all ] && return 0
    # A group selector is eligible only when it names the declared group. Other
    # selectors are expanded and every registry entry decides independently.
    if is_group "$target"; then
        [ "$target" = "$eligible" ] && return 0
        echo "Error: $verb is only available for $eligible targets; '$target' is $target." >&2
        return 2
    fi
    for code in $(resolve_target_codes "$target"); do
        actual=$(entry_group "$code")
        if [ "$actual" != "$eligible" ]; then
            echo "Error: $verb is only available for $eligible targets; '$code' is $actual." >&2
            return 2
        fi
    done
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
    local instance
    instance=$(service_instance "$server")
    ssh_entry "$server" "systemctl --user start statbus-upgrade@${instance}.service" 2>&1 || true
}

cmd_status() {
    echo "StatBus Fleet Status"
    echo "===================="
    printf "  %-8s %-12s %-31s %-12s %s\n" "CODE" "GROUP" "VERSION" "CHANNEL" "NAME"
    for server in $(all_codes); do
        local metadata version channel name group
        group=$(entry_group "$server")
        if ! metadata=$(read_server_metadata "$server" 2>/dev/null); then
            printf "  %-8s %-12s METADATA READ FAILED\n" "$server" "$group"
            continue
        fi
        IFS='|' read -r version channel name <<< "$metadata"
        version="${version#sb version }"
        version="${version/ (commit / (}"
        printf "  %-8s %-12s %-31s %-12s %s\n" "$server" "$group" "$version" "$channel" "$name"
    done
}

# cmd_health_one gathers upgrade-subsystem health for one server in a single
# SSH call. Outputs one formatted line. Designed to run in parallel.
cmd_health_one() {
    local server="$1" instance result
    instance=$(service_instance "$server")
    result=$(ssh_entry "$server" "
        cd statbus 2>/dev/null || { printf 'NO_DIR|||'; exit; }
        ver=\$(./sb --version 2>/dev/null | head -1 || echo 'UNKNOWN')
        svc=\$(systemctl --user is-active 'statbus-upgrade@${instance}.service' 2>/dev/null || echo 'unknown')
        hb='tmp/upgrade-heartbeat'
        if [ -f \"\$hb\" ]; then
            hb_ts=\$(cat \"\$hb\" | tr -d '[:space:]')
            now=\$(date +%s); age=\$((now - hb_ts))
            if   [ \"\$age\" -lt 60 ];   then progress=\"\${age}s ago\"
            elif [ \"\$age\" -lt 3600 ]; then progress=\"\$((age/60))m ago\"
            else progress=\"stale \$((age/3600))h\"; fi
        else
            last=\$(journalctl --user -u 'statbus-upgrade@${instance}.service' \
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
    echo "StatBus Fleet Health"
    echo "===================="
    if [ "$target" = "all" ] || is_channel "$target" || is_group "$target"; then
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
    local target="${1:-all}" server targets
    targets=$(resolve_target_codes "$target")
    echo "Notifying $target boxes to check for updates..."
    for server in $targets; do
        printf "  %-16s " "$server:"
        ssh_entry "$server" "cd statbus && ./sb upgrade discover" 2>/dev/null \
            && echo "notified" || echo "FAILED"
    done
}

cmd_upgrade() {
    local target="${1:-all}" confirmed="${2:-0}" server targets confirm=""
    targets=$(resolve_target_codes "$target")
    if [ "$confirmed" != 1 ]; then
        echo "WARNING: This will force the selected boxes to apply the latest release immediately."
        echo "Boxes to upgrade: $(tr '\n' ' ' <<< "$targets" | xargs)"
        echo "Use './cloud.sh status' for a read-only version overview first."
        if ! read -r -p "Type 'upgrade' to confirm (or Ctrl-C to abort): " confirm </dev/tty 2>/dev/null \
            || [ "$confirm" != upgrade ]; then
            echo "Aborted."
            return 1
        fi
    fi
    echo "Forcing $target boxes to apply latest..."
    for server in $targets; do
        printf "  %-16s " "$server:"
        ssh_entry "$server" "cd statbus && ./sb upgrade apply-latest" 2>/dev/null \
            && echo "scheduled" || echo "FAILED"
    done
}

cmd_install() {
    local target="$1"
    local version="${2:-}"
    local targets
    targets=$(resolve_target_servers "$target")

    if [ "$target" = "all" ] || is_channel "$target" || is_group "$target"; then
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
    local server="$1" instance
    local target_version="${2:-}"
    instance=$(service_instance "$server")
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
    ssh_entry "$server" \
        "journalctl --user -u 'statbus-upgrade@${instance}.service' -o cat -f -n 50 2>&1 | \
         awk '/${awk_pattern}/{print; fflush(); exit} {print; fflush()}'" \
        || true
    echo "--- Log tail disconnected for $server ---"
    echo "Final upgrade status on $server:"
    # Poll until the DB reflects the terminal state (service commits the
    # in_progress→completed transition after logging "Installation complete!").
    # Bounded at 8 tries × 2 s = 16 s max; exits early once state clears.
    # shellcheck disable=SC2016 # This polling script is evaluated remotely.
    ssh_entry "$server" \
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
    if [ "$target" = "all" ] || is_channel "$target" || is_group "$target"; then
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
    local resolved_trust_user="$FLEET_TRUST_KEY_USER"
    if [ -z "$resolved_trust_user" ]; then
        resolved_trust_user=$(ssh_entry "$server" \
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
        remote_commit=$(ssh_entry "$server" "cd statbus && ./sb --version 2>/dev/null" \
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
            apply_out=$(ssh_entry "$server" "cd statbus && ./sb upgrade apply-latest" 2>&1) || apply_rc=$?
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
        ssh_entry "$server" \
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
        ssh_entry "$server" \
            "curl -fsSL ${INSTALL_URL} | bash -s -- --channel prerelease $(trust_flag "$resolved_trust_user")" 2>&1 \
            || exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "--- $server install FAILED (exit code $exit_code) ---"
        if [ -z "$resolved_trust_user" ]; then
            echo ""
            echo "If this failed because of an invalid signing key, re-run with:"
            echo "  FLEET_TRUST_KEY_USER=jhf ./cloud.sh install $server"
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
        ssh_entry "$server" \
            "cd statbus && ./sb dotenv -f .env.config set TRUST_GITHUB_USER '$resolved_trust_user'" \
            2>/dev/null || true
    fi

    # Regenerate config so VERSION in .env matches the checked-out code.
    # Must use 'up -d' not 'restart' — restart doesn't re-read .env.
    echo "Regenerating config and restarting app..."
    ssh_entry "$server" "cd statbus && ./sb config generate && docker compose up -d app" 2>&1

    # Always leave the upgrade service running on success, regardless of
    # whether install's own service-install step fired (e.g., when running
    # without root and the user-level path was used).
    ensure_service_started "$server"

    echo "--- $server install complete ---"
}

cmd_wipe() {
    local target="$1"
    validate_code "$target"

    if [ "$target" = "all" ]; then
        echo "ERROR: wipe all is not supported. Wipe servers one at a time."
        exit 1
    fi

    echo "WARNING: This will DELETE the database on $target and recreate from scratch."
    echo "ALL DATA WILL BE LOST."
    read -r -p "Type the server name to confirm: " confirm
    if [ "$confirm" != "$target" ]; then
        echo "Aborted."
        exit 1
    fi

    echo "Wiping $target..."
    ssh_entry "$target" "cd statbus && ./dev.sh recreate-database && ./sb start all" 2>&1
    echo "--- $target wipe complete ---"
}

cmd_create_one() {
    local code="$1"
    local name="$2"
    local version="$3"
    "$SCRIPT_DIR/ops/create-new-statbus-installation.sh" "$code" "$name" "$version"
}

cmd_create() {
    local target="$1" name="$2" version="$3" code group ran=0
    if [ "$target" != all ]; then
        cmd_create_one "$target" "$name" "$version"
        return
    fi
    for code in $(all_codes); do
        group=$(entry_group "$code")
        if [ "$group" != cloud ]; then
            echo "$code: skipped (create is only available for cloud targets)"
            continue
        fi
        cmd_create_one "$code" "$name" "$version"
        ran=1
    done
    [ "$ran" -eq 1 ]
}

cmd_inspect() {
    exec "$SCRIPT_DIR/ops/inspect-cloud-installations.sh"
}

cmd_ssh() {
    local target
    target=$(resolve_single_target "$1")
    echo "Connecting to $(entry_ssh_target "$target") ..."
    ssh_entry "$target"
}

cmd_standalone_wipe() {
    # Production-safe DB wipe for standalone hosts. Does NOT use dev.sh —
    # dev.sh assumes the Go toolchain is installed (for the sb-rebuild
    # check) and also calls `./sb build all_except_app` + `./dev.sh
    # create-test-template`, neither of which belong on a pinned-release
    # production host. Instead:
    #
    #   1. ./sb stop all              — stop app/worker/rest/proxy/db
    #   2. docker volume rm <db-data> — blow away the PG data volume
    #   3. ./sb install --non-interactive
    #                                 — 14-step dispatcher handles
    #                                   start db + seed restore +
    #                                   migrate up + JWT secret + users
    #                                   + trusted signers + upgrade svc
    #                                   all idempotently.
    #
    # End state is identical to `dev.sh recreate-database` on a dev box,
    # minus the test-template db (which we never want on prod anyway).
    local target="$1"

    if [ "$target" = "all" ]; then
        echo "ERROR: wipe all is not supported. Wipe deployments one at a time."
        exit 1
    fi

    local resolved_target
    resolved_target=$(resolve_single_target "$target")

    local fqdn dom
    fqdn=$(entry_ssh_target "$resolved_target")
    dom=$(entry_domain "$resolved_target")
    echo "WARNING: This will DELETE the database for the '$resolved_target' deployment"
    echo "         (serving $dom, hosted on $fqdn) and recreate it from scratch."
    echo "ALL DATA WILL BE LOST."
    read -r -p "Type '$resolved_target' to confirm: " confirm
    if [ "$confirm" != "$resolved_target" ]; then
        echo "Aborted."
        exit 1
    fi

    echo "Wiping $resolved_target..."
    ssh_host "$resolved_target" "set -e
        cd statbus
        echo '--- stopping services ---'
        ./sb stop all
        echo '--- removing DB docker volume ---'
        INSTANCE_NAME=\$(./sb dotenv -f .env get COMPOSE_INSTANCE_NAME 2>/dev/null || echo '')
        if [ -z \"\$INSTANCE_NAME\" ]; then
          echo 'ERROR: COMPOSE_INSTANCE_NAME not set in .env — cannot identify DB volume'
          exit 1
        fi
        VOL=\"\${INSTANCE_NAME}-db-data\"
        if docker volume inspect \"\$VOL\" >/dev/null 2>&1; then
          docker volume rm \"\$VOL\"
          echo \"Removed volume \$VOL\"
        else
          echo \"Volume \$VOL already absent\"
        fi
        echo '--- re-running ./sb install (step-table populates empty DB) ---'
        ./sb install --non-interactive" 2>&1
    echo "--- $resolved_target wipe complete ---"
}

# resolve_user_email returns the email to use for cmd_import / cmd_reimport.
# Precedence: explicit --user-email FLAG > STATBUS_REIMPORT_USER_EMAIL env >
# interactive prompt (TTY only). Aborts with a clear message on a closed
# stdin (e.g. piped invocation in CI) so the caller fixes the call site
# rather than silently importing as a default user.
resolve_user_email() {
    local flag_value="${1:-}"
    if [ -n "$flag_value" ]; then
        echo "$flag_value"
        return 0
    fi
    if [ -n "${STATBUS_REIMPORT_USER_EMAIL:-}" ]; then
        echo "$STATBUS_REIMPORT_USER_EMAIL"
        return 0
    fi
    if [ ! -t 0 ]; then
        echo "ERROR: --user-email <addr> required (or set STATBUS_REIMPORT_USER_EMAIL)" >&2
        echo "       The BRREG import script verifies the email exists in public.user;" >&2
        echo "       the import_job rows are then attributed to that user." >&2
        exit 1
    fi
    local email
    read -r -p "User email (must exist in public.user on the target): " email </dev/tty
    if [ -z "$email" ]; then
        echo "Aborted: empty email." >&2
        exit 1
    fi
    echo "$email"
}

# cmd_import schedules BRREG import jobs on the target deployment by
# running the appropriate sample script remotely with USER_EMAIL
# exported. After scheduling, the worker picks up the import_job rows
# via LISTEN and processes them asynchronously; this command does NOT
# wait for completion.
#
# Two variants:
#   selection — small dataset, CSVs ship in-repo under
#               samples/norway/{legal_unit,establishment,legal_relationship}/.
#               Loaded by samples/norway/brreg/brreg-import-selection.sh.
#               No external download needed; runs on a fresh wipe.
#   downloads — full BRREG dataset, CSVs must already be on the target
#               host under ~statbus/statbus/tmp/. Loaded by
#               samples/norway/brreg/brreg-import-downloads-from-tmp.sh.
#               These CSVs are preserved across wipes (host filesystem,
#               not the Docker volume).
#
# Variant is REQUIRED, not defaulted — the two scripts have different
# correctness implications and an operator running the wrong one is a
# real failure mode. Fail loud on missing or unknown variant.
cmd_import_one() {
    local target="$1"
    local variant="${2:-}"
    local email_flag="${3:-}"

    local resolved_target
    resolved_target=$(resolve_single_target "$target")

    case "$variant" in
        selection|downloads) ;;
        "") echo "ERROR: import requires variant: selection (small, ships in-repo) or downloads (large, requires tmp/ data on host)" >&2; exit 1 ;;
        *)  echo "ERROR: unknown variant '$variant'. Valid: selection | downloads" >&2; exit 1 ;;
    esac

    local email
    email=$(resolve_user_email "$email_flag")

    local script
    case "$variant" in
        selection) script="./samples/norway/brreg/brreg-import-selection.sh" ;;
        downloads) script="./samples/norway/brreg/brreg-import-downloads-from-tmp.sh" ;;
    esac

    local fqdn dom
    fqdn=$(entry_ssh_target "$resolved_target")
    dom=$(entry_domain "$resolved_target")
    echo "Scheduling BRREG $variant import on '$resolved_target' ($dom) as $email ..."
    ssh_entry "$resolved_target" "set -e
        cd statbus
        export USER_EMAIL='${email}'
        ${script}" 2>&1
    echo "--- $resolved_target $variant import scheduled. Worker will process asynchronously."
    echo "    Watch progress: ./cloud.sh ssh $resolved_target  → ./sb psql -c \"SELECT slug, state FROM public.import_job ORDER BY slug\""
}

cmd_import() {
    local target="$1" variant="${2:-}" email_flag="${3:-}" code group ran=0
    if [ "$target" != all ]; then
        cmd_import_one "$target" "$variant" "$email_flag"
        return
    fi
    for code in $(all_codes); do
        group=$(entry_group "$code")
        if [ "$group" != standalone ]; then
            echo "$code: skipped (import is only available for standalone targets)"
            continue
        fi
        cmd_import_one "$code" "$variant" "$email_flag"
        ran=1
    done
    [ "$ran" -eq 1 ]
}

# cmd_reimport is shorthand for `wipe <name>` + `import <name>
# <variant>` — the typical flow when the operator wants a clean DB +
# fresh BRREG load in one command (e.g. before a major release that
# invalidates the prior import). The wipe prompt's typed-confirm step
# still runs, so the destructive action is acknowledged.
cmd_reimport() {
    local target="$1"
    local variant="${2:-}"
    local email_flag="${3:-}"
    if [ "$target" = "all" ]; then
        echo "ERROR: reimport all is not supported. Reimport deployments one at a time." >&2
        exit 1
    fi
    local resolved_target
    resolved_target=$(resolve_single_target "$target")
    # Validate variant up-front BEFORE the destructive wipe so a typo
    # doesn't cost the operator a wipe + retype the long confirm.
    case "$variant" in
        selection|downloads) ;;
        "") echo "ERROR: reimport requires variant: selection or downloads" >&2; exit 1 ;;
        *)  echo "ERROR: unknown variant '$variant'. Valid: selection | downloads" >&2; exit 1 ;;
    esac
    # Resolve email up-front so the operator catches a missing flag
    # BEFORE they sit through the wipe's destructive confirm step.
    local email
    email=$(resolve_user_email "$email_flag")

    cmd_standalone_wipe "$resolved_target"
    echo
    echo "Wipe complete. Scheduling fresh BRREG $variant import as $email ..."
    cmd_import "$resolved_target" "$variant" "$email"
}


# Main
# shellcheck disable=SC2317 # return is reachable when sourced by the bash test.
if [ "${STATBUS_CLOUD_LIB_ONLY:-0}" = "1" ]; then return 0 2>/dev/null || exit 0; fi
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
        cmd_notify "${2:-all}"
        ;;
    upgrade)
        shift
        target=all
        confirmed=0
        for arg in "$@"; do
            case "$arg" in
                help|-h|--help) upgrade_usage; exit 0 ;;
                --yes|--force|-y) confirmed=1 ;;
                -*) echo "Unknown argument for upgrade: $arg" >&2; upgrade_usage >&2; exit 1 ;;
                *)
                    [ "$target" = all ] || { echo "Unknown argument for upgrade: $arg" >&2; upgrade_usage >&2; exit 1; }
                    target="$arg"
                    ;;
            esac
        done
        cmd_upgrade "$target" "$confirmed"
        ;;
    install|rescue)
        sub="$1"; shift
        [ $# -lt 1 ] && { echo "Error: $sub requires a server name or 'all'"; usage; }
        target="$1"; shift
        version=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --version)
                    [ $# -ge 2 ] || { echo "Error: --version requires a value" >&2; exit 1; }
                    version="$2"; shift 2
                    ;;
                --version=*) version="${1#*=}"; shift ;;
                *) version="$1"; shift ;;
            esac
        done
        cmd_install "$target" "$version"
        ;;
    create)
        [ $# -lt 4 ] && { echo "Error: create requires <code>, <name>, and <version>"; exit 1; }
        if registry_entry "$2" >/dev/null; then assert_verb_target_group create "$2" || exit $?; fi
        cmd_create "$2" "$3" "$4"
        ;;
    inspect)
        target="${2:-cloud}"
        assert_verb_target_group inspect "$target" || exit $?
        cmd_inspect
        ;;
    wipe)
        [ $# -lt 2 ] && { echo "Error: wipe requires a box code"; usage; }
        assert_verb_target_group wipe "$2" || exit $?
        cmd_wipe "$2"
        ;;
    import)
        [ $# -lt 3 ] && { echo "Error: import requires <target> <selection|downloads>"; usage; }
        assert_verb_target_group import "$2" || exit $?
        cmd_import "$2" "$3" "${4:-}"
        ;;
    reimport)
        [ $# -lt 3 ] && { echo "Error: reimport requires <target> <selection|downloads>"; usage; }
        assert_verb_target_group reimport "$2" || exit $?
        cmd_reimport "$2" "$3" "${4:-}"
        ;;
    ssh)
        [ $# -lt 2 ] && { echo "Error: ssh requires a box code"; usage; }
        assert_verb_target_group ssh "$2" || exit $?
        cmd_ssh "$2"
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
