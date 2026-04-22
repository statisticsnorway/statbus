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

# Host registry: "<name>|<host_fqdn>|<served_domain>"
#   name           short identifier used as CLI arg. By design this IS the
#                  DEPLOYMENT_SLOT_CODE of the host's install — operators think
#                  in deployments, not hardware. Used both as CLI argument
#                  and as the slot_code in systemd unit names
#                  (statbus-upgrade@<name>.service).
#   host_fqdn      SSH target, e.g. rune.statbus.org.
#   served_domain  public domain the host serves, e.g. no.statbus.org.
#
# Each standalone host has exactly one slot by design, so <name> uniquely
# identifies the deployment. To add a new standalone host, append a line
# here plus .github/workflows/{master,deploy}-to-<host>-<name>.yaml
# modeled on -rune-no.yaml.
HOSTS=(
    "no|rune.statbus.org|no.statbus.org"
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
    echo "  import <name> <selection|downloads> [email]"
    echo "                          Schedule BRREG import (selection ships in-repo, downloads needs tmp/ data on host)"
    echo "  reimport <name> <selection|downloads> [email]"
    echo "                          DESTRUCTIVE: wipe DB then schedule fresh BRREG import"
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
# replaced without "text file busy". The unit instance suffix after `@` is
# the deployment user (see cli/cmd/install.go:serviceInstance). On standalone
# hosts the user is always `statbus` (single-tenant convention), so the
# instance is `statbus-upgrade@statbus.service` regardless of slot code.
stop_upgrade_service() {
    local name="$1"
    ssh_host "$name" "systemctl --user stop statbus-upgrade@statbus.service 2>/dev/null || true" 2>&1
}

ensure_service_started() {
    local name="$1"
    ssh_host "$name" "systemctl --user start statbus-upgrade@statbus.service" 2>&1 || true
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
    #                                   start db + snapshot restore +
    #                                   migrate up + JWT secret + users
    #                                   + trusted signers + upgrade svc
    #                                   all idempotently.
    #
    # End state is identical to `dev.sh recreate-database` on a dev box,
    # minus the test-template db (which we never want on prod anyway).
    local target="$1"
    validate_name "$target"

    if [ "$target" = "all" ]; then
        echo "ERROR: wipe all is not supported. Wipe deployments one at a time."
        exit 1
    fi

    local fqdn dom
    fqdn=$(host_fqdn "$target")
    dom=$(served_domain "$target")
    echo "WARNING: This will DELETE the database for the '$target' deployment"
    echo "         (serving $dom, hosted on $fqdn) and recreate it from scratch."
    echo "ALL DATA WILL BE LOST."
    read -p "Type '$target' to confirm: " confirm
    if [ "$confirm" != "$target" ]; then
        echo "Aborted."
        exit 1
    fi

    echo "Wiping $target..."
    ssh_host "$target" "set -e
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
    echo "--- $target wipe complete ---"
}

cmd_inspect() {
    echo "StatBus Standalone Hosts"
    echo "========================"
    printf "%-8s  %-24s  %-22s  %s\n" "NAME" "HOST (SSH)" "SERVES" "DEPLOY BRANCH"
    for entry in "${HOSTS[@]}"; do
        IFS='|' read -r name fqdn dom <<< "$entry"
        # Deploy branch is ops/standalone/deploy/<host-short>-<name> where
        # <host-short> is the first label of the fqdn. rune.statbus.org → rune,
        # so no → ops/standalone/deploy/rune-no (matches the existing workflow
        # filename pair).
        local host_short="${fqdn%%.*}"
        printf "%-8s  %-24s  %-22s  %s\n" \
            "$name" "statbus@$fqdn" "$dom" "ops/standalone/deploy/${host_short}-${name}"
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
    read -p "User email (must exist in public.user on the target): " email </dev/tty
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
cmd_import() {
    local target="$1"
    local variant="${2:-}"
    local email_flag="${3:-}"
    validate_name "$target"

    case "$variant" in
        selection|downloads) ;;
        "") echo "ERROR: import requires variant: selection (small, ships in-repo) or downloads (large, requires tmp/ data on host)" >&2; exit 1 ;;
        *)  echo "ERROR: unknown variant '$variant'. Valid: selection | downloads" >&2; exit 1 ;;
    esac

    if [ "$target" = "all" ]; then
        echo "ERROR: import all is not supported. Import deployments one at a time." >&2
        exit 1
    fi
    local email
    email=$(resolve_user_email "$email_flag")

    local script
    case "$variant" in
        selection) script="./samples/norway/brreg/brreg-import-selection.sh" ;;
        downloads) script="./samples/norway/brreg/brreg-import-downloads-from-tmp.sh" ;;
    esac

    local fqdn dom
    fqdn=$(host_fqdn "$target")
    dom=$(served_domain "$target")
    echo "Scheduling BRREG $variant import on '$target' ($dom) as $email ..."
    ssh_host "$target" "set -e
        cd statbus
        export USER_EMAIL='${email}'
        ${script}" 2>&1
    echo "--- $target $variant import scheduled. Worker will process asynchronously."
    echo "    Watch progress: ./standalone.sh ssh $target  → ./sb psql -c \"SELECT slug, state FROM public.import_job ORDER BY slug\""
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
    validate_name "$target"
    # Validate variant up-front BEFORE the destructive wipe so a typo
    # doesn't cost the operator a wipe + retype the long confirm.
    case "$variant" in
        selection|downloads) ;;
        "") echo "ERROR: reimport requires variant: selection or downloads" >&2; exit 1 ;;
        *)  echo "ERROR: unknown variant '$variant'. Valid: selection | downloads" >&2; exit 1 ;;
    esac
    if [ "$target" = "all" ]; then
        echo "ERROR: reimport all is not supported. Reimport deployments one at a time." >&2
        exit 1
    fi
    # Resolve email up-front so the operator catches a missing flag
    # BEFORE they sit through the wipe's destructive confirm step.
    local email
    email=$(resolve_user_email "$email_flag")

    cmd_wipe "$target"
    echo
    echo "Wipe complete. Scheduling fresh BRREG $variant import as $email ..."
    cmd_import "$target" "$variant" "$email"
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
        # Accept both positional version (`install no v2026.04.0-rc.48`) and
        # --version flag (`install no --version v2026.04.0-rc.48`) — the
        # latter matches install.sh's interface so operators' muscle memory
        # doesn't silently 404 on tag literal "--version".
        sub="$1"; shift
        [ $# -lt 1 ] && { echo "Error: $sub requires a host name or 'all'"; usage; }
        name="$1"; shift
        version=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --version) version="$2"; shift 2 ;;
                --version=*) version="${1#*=}"; shift ;;
                *) version="$1"; shift ;;
            esac
        done
        cmd_install "$name" "$version"
        ;;
    inspect)
        cmd_inspect
        ;;
    wipe)
        [ $# -lt 2 ] && { echo "Error: wipe requires a host name"; usage; }
        cmd_wipe "$2"
        ;;
    import)
        [ $# -lt 3 ] && { echo "Error: import requires <name> <selection|downloads>"; usage; }
        cmd_import "$2" "$3" "${4:-}"
        ;;
    reimport)
        [ $# -lt 3 ] && { echo "Error: reimport requires <name> <selection|downloads>"; usage; }
        cmd_reimport "$2" "$3" "${4:-}"
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
