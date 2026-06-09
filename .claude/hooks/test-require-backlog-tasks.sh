#!/bin/bash
# test-require-backlog-tasks.sh — smoke tests for the hook.
# Run with: bash .claude/hooks/test-require-backlog-tasks.sh
set -u

HOOK="$(dirname "$0")/require-backlog-tasks.sh"
fail=0
pass=0

assert_decision() {
  local label="$1" expect="$2" payload="$3" out got
  out=$(echo "$payload" | "$HOOK" 2>/dev/null)
  if [[ "$out" == "{}" ]]; then
    got="allow-default"
  else
    got=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "?"')
  fi
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass+1)); echo "ok   ${label}: ${got}"
  else
    fail=$((fail+1)); echo "FAIL ${label}: got '${got}', expected '${expect}'"
  fi
}

# The harness TaskCreate is blocked; the Backlog MCP create is the way.
assert_decision "harness TaskCreate"          "deny"          '{"tool_name":"TaskCreate","tool_input":{"title":"x"}}'
assert_decision "backlog task_create (mcp)"   "allow-default" '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"x"}}'

# Other harness Task* tools are NOT touched by this hook.
assert_decision "TaskUpdate"                  "allow-default" '{"tool_name":"TaskUpdate","tool_input":{}}'
assert_decision "TaskList"                    "allow-default" '{"tool_name":"TaskList","tool_input":{}}'

# Unrelated tools pass through.
assert_decision "Bash"                        "allow-default" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_decision "Agent"                       "allow-default" '{"tool_name":"Agent","tool_input":{"team_name":"statbus"}}'

echo "── ${pass} passed, ${fail} failed"
exit $fail
