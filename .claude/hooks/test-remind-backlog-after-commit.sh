#!/bin/bash
# test-remind-backlog-after-commit.sh — behavioral checks for
# remind-backlog-after-commit.sh. Run directly: exits 0 all-green, 1 on any
# failure, printing per-case verdicts.

set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/remind-backlog-after-commit.sh"
fail=0

check() {
  local name="$1" payload="$2" want="$3" env_prefix="${4:-}"
  local out fired
  out=$(echo "$payload" | env $env_prefix "$HOOK")
  if jq -e '.hookSpecificOutput.additionalContext' <<<"$out" >/dev/null 2>&1; then
    fired="FIRE"
  else
    fired="NO-FIRE"
  fi
  if [[ "$fired" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name — want $want, got $fired (output: $out)"
    fail=1
  fi
}

check "plain git commit fires" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}' FIRE
check "git -C commit fires" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /some/dir commit -m x"}}' FIRE
check "compound add+commit fires" \
  '{"tool_name":"Bash","tool_input":{"command":"git add a.go && git commit -m x && git push"}}' FIRE
check "backlog-sync commit skips" \
  '{"tool_name":"Bash","tool_input":{"command":"git add .backlog/tasks/ && git commit -m board"}}' NO-FIRE
check "non-commit git skips" \
  '{"tool_name":"Bash","tool_input":{"command":"git log --oneline"}}' NO-FIRE
check "prose mentioning commit skips" \
  '{"tool_name":"Bash","tool_input":{"command":"echo please commit this via git later"}}' NO-FIRE
check "git commit-msg hook path skips" \
  '{"tool_name":"Bash","tool_input":{"command":"cat .githooks/commit-msg"}}' NO-FIRE
check "non-Bash tool skips" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x"}}' NO-FIRE
check "env kill-switch disables" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' NO-FIRE \
  "HOOK_ENABLED_REMIND_BACKLOG_AFTER_COMMIT=0"

exit $fail
