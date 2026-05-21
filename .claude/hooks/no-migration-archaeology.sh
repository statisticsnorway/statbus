#!/bin/bash
# no-migration-archaeology.sh — PreToolUse hook on the Bash tool.
#
# Blocks alphabetical (oldest-first) search of migrations/ which teaches
# wrong patterns. Migration filenames sort alphabetically by 14-digit
# timestamp, so naive `grep PATTERN migrations/*.sql` returns the OLDEST
# match first. Reading that and assuming it reflects current behavior is
# how teammates in this project have repeatedly proposed fixes against
# stale schema when columns/tables/procs get renamed over time.
#
# Canonical: doc/db/*.md for current schema/proc state. The doc/db/
# directory holds dumped \d output and function bodies reflecting the
# CURRENT database after all migrations are applied. Always grep there
# for "what does the code do now."
#
# When migration archaeology IS needed (e.g. to find when a rename
# happened), the hook allows reverse-iteration patterns:
#   - `ls -r migrations/*.sql` (newest first)
#   - `sort -r` / `--reverse` / `| tac` anywhere in the pipeline
#   - `| tail` on alphabetically-sorted output
#   - Specific timestamp-prefixed file picks (no glob)

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

command=$(jq -r '.tool_input.command // empty' <<<"$payload")
normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

# ── reverse-treatment detection ──
# Any of these markers in the command = caller has acknowledged ordering
# matters and is asking for newest-first.
has_reverse_treatment() {
  local cmd="$1"
  # sort with -r flag (in any combination), --reverse long form, | tac, | tail
  if echo "$cmd" | grep -qE '\bsort\b[^|;&]*-[a-zA-Z]*r\b'; then return 0; fi
  if echo "$cmd" | grep -qE -- '--reverse\b'; then return 0; fi
  if echo "$cmd" | grep -qE '\|\s*tac\b'; then return 0; fi
  if echo "$cmd" | grep -qE '\|\s*tail\b'; then return 0; fi
  # ls -r (reverse listing — order matters here, hence we check for -r flag)
  if echo "$cmd" | grep -qE '\bls\s+-[a-zA-Z]*r\b'; then return 0; fi
  # Specific file picks: migrations/<14-digit-prefix>... with no bare glob
  # (the user is pinpointing a known migration by timestamp)
  if echo "$cmd" | grep -qE 'migrations/[0-9]{14}_'; then
    # Allow as long as the path uses the explicit timestamp prefix.
    return 0
  fi
  return 1
}

# ── migration-search detection ──
# Forward-order scans of migrations/ that learn the WRONG pattern first.
has_migration_search() {
  local cmd="$1"
  # grep/rg/ag/ack with migrations/ glob or directory target.
  if echo "$cmd" | grep -qE '\b(grep|rg|ag|ack)\b[^|;&]*\bmigrations/'; then
    return 0
  fi
  # find migrations/ ... (no reverse-sort pipe)
  if echo "$cmd" | grep -qE '\bfind\s+migrations/'; then
    return 0
  fi
  # cat/head on a glob target (multi-file alphabetical concat)
  if echo "$cmd" | grep -qE '\b(cat|head)\b[^|;&]*\bmigrations/\*'; then
    return 0
  fi
  # ls migrations/* piped to head or grep (forward-pick from sorted listing)
  if echo "$cmd" | grep -qE '\bls\b[^|;&]*\bmigrations/[^|;&]*\|\s*(head|grep)\b'; then
    return 0
  fi
  return 1
}

if has_migration_search "$normalized"; then
  if ! has_reverse_treatment "$normalized"; then
    reason_text="BLOCKED: Alphabetical migration search teaches the wrong pattern.

WHY: migrations/ filenames sort alphabetically by 14-digit timestamp, so naive grep/rg returns OLDEST hits first. You read the obsolete pattern, form a wrong mental model, and propose fixes against stale schema. This project has been bitten repeatedly when columns/tables/procs get renamed across the lifetime of the codebase.

CANONICAL: doc/db/*.md holds the CURRENT schema/proc state after all migrations applied. For 'what does the code do now', grep doc/db/, not migrations/.

If you genuinely need migration archaeology (e.g. to find when a rename happened), use reverse-iteration:
  ls -r migrations/*.sql | head -N              # newest N files
  ls migrations/*.sql | tail -N                 # also newest
  grep PATTERN \$(ls -r migrations/*.sql)       # newest matches first
  rg PATTERN \$(ls -r migrations/*.sql)         # same
  find migrations/ -name '*.sql' | sort -r      # newest first
  cat migrations/20260422000000_*.sql           # exact timestamp = fine

Command that tripped this rule:
  ${normalized:0:200}

Hook source: .claude/hooks/no-migration-archaeology.sh"

    escaped=$(jq -Rn --arg r "$reason_text" '$r')
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${escaped}
  }
}
EOF
    exit 0
  fi
fi

echo "{}"
