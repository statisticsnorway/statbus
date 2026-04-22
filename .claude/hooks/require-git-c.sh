#!/bin/bash
# require-git-c.sh — PreToolUse hook on Bash.
#
# Requires `git -C <path>` on every git command — no bare `git`.
#
# WHY: bare `git` runs against whichever branch owns the process's cwd,
# which may not be what the agent intends. Explicit -C <path> names the
# target, prevents silent mistakes, and makes the command self-documenting.
#
# Two checks:
#   1. -C must be present on every git command (except read-only helpers:
#      git help, git version, git config --global).
#   2. If -C is present and this repo has nested worktrees, verify the -C
#      path matches the worktree containing any path argument that lives
#      inside a worktree directory. (Data-driven from `git worktree list`
#      — no per-worktree maintenance; currently statbus has no nested
#      worktrees so this check is always a no-op.)
#
# Read-only subcommand exemption: log, show, diff, status, blame, etc. skip
# check 2 — read-only ops don't mutate, so wrong-worktree -C is harmless.
#
set -euo pipefail

# DEACTIVATED: this hook is ported for future activation.
# Activation (when the pain arrives): set HOOK_ENABLED_REQUIRE_GIT_C=1 in
# .claude/settings.json's hook registration for this file, or flip the
# default below.
HOOK_ENABLED="${HOOK_ENABLED_REQUIRE_GIT_C:-0}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
    echo "{}"
    exit 0
fi
# ─── live hook logic below runs only when enabled ──────────────────────

INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // empty')"

if [[ "$TOOL" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

CMD="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"

emit_deny() {
  local _reason="$1"
  local _escaped
  _escaped=$(jq -Rn --arg r "$_reason" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
}

# Skip if not a git command
echo "$CMD" | grep -qE -- '(^|\||\;|\&\&)\s*git\s' || { echo "{}"; exit 0; }

# Allow git commands that don't operate on a repo
echo "$CMD" | grep -qE -- 'git\s+(help|version|--version|config\s+--global)' && { echo "{}"; exit 0; }

# Derive the project root from this hook's location (.claude/hooks/ → project root).
# Override with CLAUDE_PROJECT_DIR if your layout differs.
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# ── Check 2: worktree-path mismatch ──────────────────────────────────────
# Only fires if -C is present. Data-driven from `git worktree list`.
# Currently statbus has no nested worktrees, so this is always a no-op.
if echo "$CMD" | grep -qE -- 'git\s+(-[a-zA-Z]*\s+)*-C\s'; then
  WORKTREE_RELS=$(git -C "$REPO" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { print $2 }' \
    | grep -vxF -- "$REPO" \
    | sed -E "s|^${REPO}/||" || true)

  GIT_SEGS=$(echo "$CMD" | grep -oE -- 'git[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-C[[:space:]]+[^;|&]*')

  while IFS= read -r GIT_SEG; do
    [ -z "$GIT_SEG" ] && continue

    if [[ "$GIT_SEG" == *-C\ * ]]; then
      C_PATH_TAIL="${GIT_SEG#*-C }"
      C_PATH="${C_PATH_TAIL%% *}"
    else
      C_PATH=""
    fi

    SEG_ARGS=$(echo "$GIT_SEG" | sed -E 's|-C[[:space:]]+[^[:space:]]+||')

    # Read-only subcommand pass-through.
    SUBCMD=""
    read -r -a SEG_TOKS <<< "$SEG_ARGS"
    skip_next=0
    for tok in "${SEG_TOKS[@]}"; do
      if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
      case "$tok" in
        git) continue ;;
        -c|--git-dir|--work-tree|--namespace) skip_next=1; continue ;;
        -*) continue ;;
        *) SUBCMD="$tok"; break ;;
      esac
    done

    IS_READONLY=0
    case "$SUBCMD" in
      log|show|diff|blame|cat-file|rev-parse|ls-files|ls-tree|ls-remote|\
      check-ignore|check-attr|status|describe|name-rev|rev-list|shortlog|\
      fsck|count-objects|verify-pack|verify-commit|verify-tag|reflog|grep|\
      archive|for-each-ref|symbolic-ref|show-ref|show-branch|whatchanged|help)
        IS_READONLY=1
        ;;
      stash|bisect|notes|worktree)
        SECOND_TOK=""
        found_subcmd=0
        for tok in "${SEG_TOKS[@]}"; do
          if [ "$found_subcmd" = "1" ]; then
            case "$tok" in -*) continue ;; *) SECOND_TOK="$tok"; break ;; esac
          fi
          [ "$tok" = "$SUBCMD" ] && found_subcmd=1
        done
        case "$SUBCMD $SECOND_TOK" in
          "stash list"|"stash show")           IS_READONLY=1 ;;
          "bisect log"|"bisect visualize"|"bisect view") IS_READONLY=1 ;;
          "notes show"|"notes list")           IS_READONLY=1 ;;
          "worktree list")                     IS_READONLY=1 ;;
        esac
        ;;
    esac

    [ "$IS_READONLY" = "1" ] && continue

    for WT_REL in $WORKTREE_RELS; do
      WT_ESC=$(printf '%s' "$WT_REL" | sed 's|\.|\\.|g')
      if echo "$SEG_ARGS" | grep -qE -- "(^|[[:space:]]|/)${WT_ESC}/[^[:space:]]"; then
        case "$C_PATH" in
          *"/$WT_REL"|*"/$WT_REL/") : ;;
          *)
            emit_deny "BLOCKED: git command references \`${WT_REL}/<file>\` but -C targets a different path.

Offending invocation: ${GIT_SEG}
Its -C path: ${C_PATH}

WHY: \`${WT_REL}/\` is a separate git worktree on its own branch. Operations
targeting it must use \`git -C ${REPO}/${WT_REL} ...\` — not a sibling -C path.

WHAT TO DO:
  git -C ${REPO}/${WT_REL} status
  git -C ${REPO}/${WT_REL} diff <file>
  git -C ${REPO}/${WT_REL} add <file>

Hook source: .claude/hooks/require-git-c.sh"
            exit 0
            ;;
        esac
      fi
    done
  done <<< "$GIT_SEGS"

  echo "{}"
  exit 0
fi

# Check 1: -C not present — deny bare git
emit_deny "BLOCKED: bare \`git\` without \`-C <path>\` is not allowed.

WHY: bare \`git\` runs against the working directory's branch, which may
not be what you intend. Explicit \`-C <path>\` names the target, prevents
silent mistakes, and makes the command self-documenting.

WHAT TO DO:
  git -C ${REPO} status          # operate on project root
  git -C ${REPO} add <file>
  git -C ${REPO} commit -m '...'
  git -C ${REPO} log --oneline

Always specify the target path. There is no safe default.

Command that tripped this rule: ${CMD:0:200}

Hook source: .claude/hooks/require-git-c.sh"
exit 0
