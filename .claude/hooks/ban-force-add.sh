#!/bin/bash
# ban-force-add.sh — PreToolUse hook on Bash.
#
# Blocks `git add -f` / `git add --force`. Agents routinely use force-add
# to bypass .gitignore when they hit a "file is ignored" error, which
# causes lost code, unwanted commits, and leaked secrets over time.
#
# The correct path when a file needs to be tracked is to UPDATE .gitignore
# (the repo uses a whitelist pattern for /.claude/ already — add files to
# the whitelist instead). Force-add is never the right answer.
#
set -euo pipefail

# DEACTIVATED: this hook is ported for future activation.
# Activation (when the pain arrives): set HOOK_ENABLED_BAN_FORCE_ADD=1 in
# .claude/settings.json's hook registration for this file, or flip the
# default below.
HOOK_ENABLED="${HOOK_ENABLED_BAN_FORCE_ADD:-0}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
    echo "{}"
    exit 0
fi
# ─── live hook logic below runs only when enabled ──────────────────────

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

command=$(jq -r '.tool_input.command // empty' <<<"$payload")

# Token-scan the command for the pattern:
#   [separator or BOL] git [opt: -C <dir>] add [any args...] [-f | --force] [any args...]
#
# A shell separator (;, &&, ||, |) ends the current invocation's scope.

read -ra tokens <<<"$command"

deny=false
i=0
while ((i < ${#tokens[@]})); do
  tok="${tokens[i]}"

  case "$tok" in
    ';'|'&&'|'||'|'|')
      i=$((i + 1))
      continue
      ;;
  esac

  if [[ "$tok" == "git" ]]; then
    j=$((i + 1))
    if [[ "${tokens[j]:-}" == "-C" ]]; then
      j=$((j + 2))
    fi
    if [[ "${tokens[j]:-}" == "add" ]]; then
      k=$((j + 1))
      while ((k < ${#tokens[@]})); do
        arg="${tokens[k]}"
        case "$arg" in
          ';'|'&&'|'||'|'|')
            break
            ;;
          '-f'|'--force')
            deny=true
            break 2
            ;;
        esac
        k=$((k + 1))
      done
    fi
  fi

  i=$((i + 1))
done

if [[ "$deny" == true ]]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: `git add -f` / `git add --force` is banned in this repo.\n\nWHY: agents abuse force-add to bypass .gitignore when they hit a 'file is ignored' error. Over time this leaks local state, test artifacts, and occasionally secrets into the repo; it also produces commits nobody intended.\n\nWHAT TO DO INSTEAD:\n  1. If the file genuinely belongs under version control, update /.gitignore so it is un-ignored by pattern. The repo uses a WHITELIST for /.claude/:\n       /.claude/*\n       !/.claude/commands/\n       !/.claude/hooks/\n       !/.claude/settings.json\n     Add a whitelist entry for your file's directory or extension, then `git -C <path> add <file>` without -f.\n  2. If the file really should NOT be tracked (local state, cache, secret, user-specific override), leave it ignored — do not try to work around the rule.\n  3. If the file is genuinely borderline, ask for a decision — do not force it through.\n\nHook source: .claude/hooks/ban-force-add.sh"
  }
}
EOF
  exit 0
fi

echo "{}"
