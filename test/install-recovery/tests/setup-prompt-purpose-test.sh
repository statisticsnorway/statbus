#!/usr/bin/env bash
# STATBUS-490: the configuration prompts must say what each answer is for.
# The notification email prompt must say a blank answer is fine and means no
# unattended-upgrade notifications; the GitHub usernames prompt must say it is
# operator/DevOps SSH access to the box, unrelated to StatBus data. A blank
# email answer must let the configuration step complete and save an empty value.
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
exit $fail
