#!/usr/bin/env bash
# STATBUS-554: a full setup run on a plain box must succeed on its first run.
# Stages act on things earlier stages create: ssh-hardening installs keys for the
# service account, core-tools grants that account Docker access, user-setup adds
# devops to the docker group. The run order must put each creator first.
#
# This drives the script's real main() with every stage body replaced by a stand-in
# that records its call and fails when what it acts on does not exist yet, starting
# from a box with neither the service account nor Docker. The dependencies below
# are the facts about the stage bodies, written here independently of the script's
# own declarations, so a wrong declaration fails this test too.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which makes
# the red half of the evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT

run_full_setup() (
    unset SUDO_USER SKIP_STAGES ONLY_STAGES
    export REBOOT_REQUIRED_FILE="$BOX/reboot-required"
    # shellcheck source=/dev/null
    source "$SCRIPT"
    NON_INTERACTIVE=true
    CLOUD=true
    SERVICE_USER=statbus
    show_banner() { :; }
    check_prerequisites() { :; }
    setup_env() { :; }
    configure_server_fqdn() { :; }
    print_run_summary() { :; }

    ran() { echo "$1" >> "$BOX/calls"; }
    needs() { # <stage> <thing on the box>
        [[ -e "$BOX/$2" ]] && return 0
        FAILED_VERIFICATIONS+=("$1 ran before $2 existed")
        echo "$1 ran before $2 existed"
        return 1
    }
    stage_https_sources()   { ran https-sources; }
    stage_base_system()     { ran base-system; }
    stage_service_account() { ran service-account; touch "$BOX/statbus"; }
    stage_ssh_hardening()   { ran ssh-hardening; needs ssh-hardening statbus; }
    stage_auto_updates()    { ran auto-updates; }
    stage_security_tools()  { ran security-tools; }
    stage_core_tools()      { ran core-tools; touch "$BOX/docker"; needs core-tools statbus; }
    stage_user_setup()      { ran user-setup; needs user-setup docker; }
    stage_ci_allowlist()    { ran ci-allowlist; }

    main --non-interactive
)

out="$(run_full_setup 2>&1)"
rc=$?
fail=0
if [[ "$rc" -eq 0 ]]; then
    echo "PASS a full run on a box without statbus or Docker exits 0"
else
    echo "FAIL a full run on a box without statbus or Docker exits $rc:"
    grep -E 'ran before' <<<"$out" | sed 's/^/    /'
    fail=1
fi

expected="https-sources base-system service-account ssh-hardening auto-updates security-tools core-tools user-setup ci-allowlist"
got="$(paste -sd ' ' - < "$BOX/calls" 2>/dev/null)"
if [[ "$got" == "$expected" ]]; then
    echo "PASS every stage ran once, in the agreed order"
else
    echo "FAIL stage order: expected '$expected', got '$got'"
    fail=1
fi
exit $fail
