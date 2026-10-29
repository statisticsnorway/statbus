#!/usr/bin/env bash
# STATBUS-490: the configuration prompts must say what each answer is for.
# The notification email prompt must say a blank answer is fine and means no
# unattended-upgrade notifications; the GitHub usernames prompt must say it is
# operator/DevOps SSH access to the box, unrelated to StatBus data. A blank
# email answer must let the configuration step complete and save an empty value.
#
# Stages StatBus always needs default to yes ([Y/n]); optional or
# environment-dependent stages default to no ([y/N]). Pressing Enter therefore
# runs a required stage and skips an optional one.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

# Run the real interactive configuration step: blank email, one GitHub user,
# Enter for the rest. Fresh HOME so no existing config is loaded.
transcript="$(printf '\nalice\n\n\n\n' | HOME="$home" SUDO_USER= bash -c '
    source "$1"
    ENV_FILE="$HOME/.setup-ubuntu.env"
    setup_env
' _ "$SCRIPT" 2>&1)"; rc=$?
echo "--- transcript ---"; echo "$transcript"; echo "------------------"

email_prompt="$(grep -i 'notification' <<<"$transcript" | head -1)"
if grep -qi 'blank' <<<"$email_prompt" && grep -qi 'no unattended-upgrade' <<<"$email_prompt"; then
    echo "PASS email prompt says blank is allowed and what it means: $email_prompt"
else
    echo "FAIL email prompt does not state blank is allowed and its meaning: ${email_prompt:-<none>}"; fail=1
fi

ssh_prompt="$(grep -i 'GitHub usernames' <<<"$transcript" | head -1)"
if grep -qi 'operator' <<<"$ssh_prompt" && grep -qi 'DevOps' <<<"$ssh_prompt" && grep -qi 'not .*StatBus data' <<<"$ssh_prompt"; then
    echo "PASS SSH prompt names operator/DevOps access, unrelated to StatBus data: $ssh_prompt"
else
    echo "FAIL SSH prompt does not name its purpose: ${ssh_prompt:-<none>}"; fail=1
fi

if [[ $rc -eq 0 ]] && grep -q '^ADMIN_EMAIL=""' "$home/.setup-ubuntu.env" 2>/dev/null; then
    echo "PASS blank email answer completes configuration and saves ADMIN_EMAIL=\"\""
else
    echo "FAIL blank email answer did not complete cleanly (rc=$rc): $(cat "$home/.setup-ubuntu.env" 2>/dev/null)"; fail=1
fi

# ---------------------------------------------------------------------------
# Stage prompts: required stages default to yes, optional stages to no.
# ---------------------------------------------------------------------------

# required=yes, optional=no. Stage 0 has no prompt (it probes and decides).
declare -A stage_default=(
    [stage_base_system]=y
    [stage_ssh_hardening]=y
    [stage_auto_updates]=y
    [stage_security_tools]=n
    [stage_core_tools]=y
    [stage_user_setup]=n
    [stage_service_account]=y
    [stage_ci_allowlist]=n
)

for fn in "${!stage_default[@]}"; do
    body="$(awk "/^${fn}\\(\\)/,/^}$/" "$SCRIPT")"
    prompt="$(grep 'ask_yes_no "Run this stage?"' <<<"$body" | head -1)"
    if [[ -z "$prompt" ]]; then
        echo "FAIL $fn has no stage prompt"; fail=1; continue
    fi
    if [[ "$prompt" == *'?" y'* ]]; then
        got=y
    else
        got=n
    fi
    if [[ "$got" == "${stage_default[$fn]}" ]]; then
        echo "PASS $fn prompts with default $([[ $got == y ]] && echo '[Y/n]' || echo '[y/N]')"
    else
        echo "FAIL $fn default is '$got', expected '${stage_default[$fn]}': $prompt"; fail=1
    fi
done

# Behaviour of the real ask_yes_no on a bare Enter: the hint is rendered from
# the default, and the default decides whether the stage's `if ! ask_yes_no`
# runs it. A stub read supplies the empty answer and records the prompt.
source "$SCRIPT"
capture_prompt() { # default -> LAST_PROMPT, return value of ask_yes_no
    local default="$1"
    LAST_PROMPT=""
    read() {
        LAST_PROMPT="${3:-}"
        printf -v "${4:-REPLY}" '%s' ''
    }
    if ask_yes_no "Run this stage?" "$default"; then
        local rc=0
    else
        local rc=$?
    fi
    unset -f read
    return "$rc"
}

if capture_prompt y; then enter_rc=0; else enter_rc=$?; fi
if [[ "$enter_rc" -eq 0 && "$LAST_PROMPT" == *"[Y/n]"* ]]; then
    echo "PASS Enter on a required stage runs it and the prompt shows [Y/n]: $LAST_PROMPT"
else
    echo "FAIL Enter on a required stage did not run it (rc=$enter_rc, prompt='$LAST_PROMPT')"; fail=1
fi

if capture_prompt n; then enter_rc=0; else enter_rc=$?; fi
if [[ "$enter_rc" -ne 0 && "$LAST_PROMPT" == *"[y/N]"* ]]; then
    echo "PASS Enter on an optional stage skips it and the prompt shows [y/N]: $LAST_PROMPT"
else
    echo "FAIL Enter on an optional stage did not skip it (rc=$enter_rc, prompt='$LAST_PROMPT')"; fail=1
fi

exit $fail
