#!/usr/bin/env bash
# STATBUS-554: operators choose stages by name. --only-stages runs just the named
# stages, --skip-stages runs all but the named ones, and anything else is refused
# before any stage runs, with the valid names listed: both options together, an
# unknown name, or a stage number (numbers changed meaning whenever a stage moved).
#
# Drives the script's real main() with every stage body replaced by a stand-in
# that records its call.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which makes
# the red half of the evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ALL="https-sources base-system service-account ssh-hardening auto-updates security-tools core-tools user-setup ci-allowlist"
fail=0

# setup <args...>: prints the stages that ran, one line, then the script output.
setup() (
    unset SUDO_USER SKIP_STAGES ONLY_STAGES
    export REBOOT_REQUIRED_FILE="$WORK/reboot-required"
    : > "$WORK/calls"
    # shellcheck source=/dev/null
    source "$SCRIPT"
    CLOUD=true
    show_banner() { :; }
    check_prerequisites() { :; }
    setup_env() { :; }
    configure_server_fqdn() { :; }
    print_run_summary() { :; }
    ran() { echo "$1" >> "$WORK/calls"; }
    stage_https_sources()   { ran https-sources; }
    stage_base_system()     { ran base-system; }
    stage_service_account() { ran service-account; }
    stage_ssh_hardening()   { ran ssh-hardening; }
    stage_auto_updates()    { ran auto-updates; }
    stage_security_tools()  { ran security-tools; }
    stage_core_tools()      { ran core-tools; }
    stage_user_setup()      { ran user-setup; }
    stage_ci_allowlist()    { ran ci-allowlist; }
    main --non-interactive "$@" > "$WORK/out" 2>&1
)
ran_stages() { paste -sd ' ' - < "$WORK/calls"; }

selects() { # <label> <expected stages> <args...>
    local label="$1" expected="$2"
    shift 2
    setup "$@"
    local rc=$? got
    got="$(ran_stages)"
    if [[ "$rc" -eq 0 && "$got" == "$expected" ]]; then
        echo "PASS $label"
    else
        echo "FAIL $label: exit $rc, ran '$got', expected '$expected'"
        sed 's/^/    /' "$WORK/out"
        fail=1
    fi
}

refuses() { # <label> <args...>
    local label="$1"
    shift
    setup "$@"
    local rc=$? got missing=""
    got="$(ran_stages)"
    for slug in $ALL; do
        grep -qw -- "$slug" "$WORK/out" || missing+=" $slug"
    done
    if [[ "$rc" -ne 0 && -z "$got" && -z "$missing" ]]; then
        echo "PASS $label"
    else
        echo "FAIL $label: exit $rc, ran '$got', valid names missing from the message:${missing:- none}"
        sed 's/^/    /' "$WORK/out"
        fail=1
    fi
}

selects "a run without options runs every stage" "$ALL"
selects "--only-stages runs just the named stages, in run order" \
    "service-account security-tools" --only-stages "security-tools service-account"
selects "--only-stages=... form works" "auto-updates" --only-stages=auto-updates
selects "--skip-stages runs every stage but the named ones" \
    "https-sources base-system service-account ssh-hardening auto-updates core-tools user-setup ci-allowlist" \
    --skip-stages security-tools
refuses "a stage number is refused" --skip-stages 4
refuses "an unknown stage name is refused" --only-stages "ssh-hardning"
refuses "--only-stages and --skip-stages together are refused" \
    --only-stages ssh-hardening --skip-stages security-tools
refuses "an empty --only-stages is refused" --only-stages ""

# A stage's required stages must stay selected; the refusal names what to add.
requires_refusal() { # <label> <must name> <args...>
    local label="$1" name="$2"
    shift 2
    setup "$@"
    local rc=$?
    if [[ "$rc" -ne 0 && -z "$(ran_stages)" ]] && grep -q "requires $name" "$WORK/out"; then
        echo "PASS $label"
    else
        echo "FAIL $label: exit $rc, ran '$(ran_stages)', no 'requires $name' in:"
        sed 's/^/    /' "$WORK/out"
        fail=1
    fi
}
requires_refusal "--only-stages without a required stage is refused, naming it" \
    service-account --only-stages "ssh-hardening security-tools"
requires_refusal "--skip-stages of a stage others require is refused, naming it" \
    service-account --skip-stages service-account
selects "--only-stages with the required stage runs both" \
    "service-account ssh-hardening security-tools" --only-stages "ssh-hardening security-tools service-account"

exit $fail
