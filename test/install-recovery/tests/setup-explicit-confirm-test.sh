#!/usr/bin/env bash
# STATBUS-540: confirming SSH access needs an explicit answer.
#
# Field report (Uganda, 2026-10-30, Stage 2): the prompt read
# "Did that connect? [y/N]". An operator who pressed Enter passed the check
# without confirming anything. Owner ruling 2026-10-30: that question has no
# default. It shows [y/n] and an empty answer re-asks until the operator types
# yes or no (or answers yes by running --non-interactive).
#
# This drives the real ask_yes_no from ops/setup-ubuntu-lts.sh through a
# pseudo-terminal, because bash only writes a `read -p` prompt when stdin is a
# terminal; the prompt text is therefore observed, not assumed. Every other
# question keeps its y/n default.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see the red half.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

if ! grep -q '^ask_yes_no()' "$SCRIPT"; then
    nope "the script defines ask_yes_no"
    exit 1
fi
if ! command -v script >/dev/null 2>&1; then
    nope "util-linux 'script' is available to drive a terminal prompt"
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/setup-explicit-confirm.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cat > "$work/ask.sh" <<'EOS'
source "$1"
ask_yes_no "Did that connect?" none
EOS

reask='Please type yes or no; this needs an explicit answer.'

run_confirm() { # input-lines -> sets rc and out, prompt observed through a pty
    local input=$1 cmd
    cmd="bash $(printf '%q' "$work/ask.sh") $(printf '%q' "$SCRIPT")"
    out=$(printf '%s' "$input" | script -q -e -c "$cmd" /dev/null 2>&1)
    rc=$?
    out=$(printf '%s\n' "$out" | tr -d '\r')
}

occurrences() { grep -oF "$1" <<<"$out" | wc -l; }

# 1. Empty answer then yes: one re-ask, then yes.
run_confirm $'\ny\n'
if [ "$rc" -eq 0 ]; then
    pass "empty then yes: the confirmation returns yes"
else
    nope "empty then yes: expected yes (rc=$rc), got: $out"
fi
if [ "$(occurrences 'Did that connect? [y/n]:')" -eq 2 ]; then
    pass "empty then yes: the prompt shows [y/n] and is asked again once"
else
    nope "empty then yes: expected the [y/n] prompt twice, got: $out"
fi
if [ "$(occurrences "$reask")" -eq 1 ]; then
    pass "empty then yes: the empty answer is rejected with the explicit-answer message"
else
    nope "empty then yes: expected one '$reask', got: $out"
fi
if grep -Eq '\[y/N\]|\[Y/n\]' <<<"$out"; then
    nope "empty then yes: the question must not show a default hint: $out"
else
    pass "empty then yes: no default hint is shown"
fi

# 2. Empty answer then no: one re-ask, then no.
run_confirm $'\nn\n'
if [ "$rc" -eq 1 ]; then
    pass "empty then no: the confirmation returns no"
else
    nope "empty then no: expected no (rc=$rc), got: $out"
fi
if [ "$(occurrences 'Did that connect? [y/n]:')" -eq 2 ] && [ "$(occurrences "$reask")" -eq 1 ]; then
    pass "empty then no: one re-ask, then the answer is taken"
else
    nope "empty then no: expected one re-ask with the [y/n] prompt twice, got: $out"
fi

# 3. Non-interactive runs still answer yes without asking.
out=$(NON_INTERACTIVE=true bash -c '
    source "$1"
    ask_yes_no "Did that connect?" none
' _ "$SCRIPT" </dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'Did that connect?' <<<"$out"; then
    pass "non-interactive: answers yes without asking"
else
    nope "non-interactive: expected yes with no prompt (rc=$rc), got: $out"
fi

# 4. Every other question keeps its default: an empty answer is still taken.
out=$(printf '\n' | bash -c '
    source "$1"
    ask_yes_no "Continue with the default?" n
' _ "$SCRIPT" 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
    pass "other questions: an empty answer still takes the n default"
else
    nope "other questions: expected the n default to answer no (rc=$rc), got: $out"
fi
out=$(printf '\n' | bash -c '
    source "$1"
    ask_yes_no "Continue with the default?" y
' _ "$SCRIPT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "other questions: an empty answer still takes the y default"
else
    nope "other questions: expected the y default to answer yes (rc=$rc), got: $out"
fi

# 5. Only the SSH access confirmation uses the explicit form.
if [ "$(grep -cE '^[[:space:]]*(if ! )?ask_yes_no .*[[:space:]]none(;|$)' "$SCRIPT")" -eq 1 ] && grep -q 'ask_yes_no "Did that connect?" none' "$SCRIPT"; then
    pass "only 'Did that connect?' has no default"
else
    nope "expected exactly one ask_yes_no call with default none, and it is 'Did that connect?'"
fi

exit $fail
