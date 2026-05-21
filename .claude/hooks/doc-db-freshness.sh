#!/bin/bash
# doc-db-freshness.sh — PreToolUse hook on the Bash tool.
#
# Gates searches of doc/db/ on freshness vs migrations/. doc/db/ is the
# canonical "current schema state" reference; if migrations were committed
# (or are uncommitted in the working tree) without a corresponding
# regeneration of doc/db/, the documentation may be out of date.
#
# Three outcomes:
#   1. FRESH — committed doc/db is newer than or equal to committed
#      migrations AND no uncommitted activity → silent allow.
#   2. WORK IN FLIGHT — uncommitted activity in migrations/ or doc/db/
#      → allow + WARNING listing the in-flight files. The agent must
#      decide: "is this my own work and I'm aware, or someone else's
#      work I need to check?"
#   3. DEFINITELY STALE — committed migrations are newer than committed
#      doc/db AND no uncommitted doc/db updates to explain the gap →
#      hard deny. Run `./dev.sh generate-db-documentation` first.
#
# Detected access patterns: grep/rg/ag/ack/find/cat/head/ls against
# doc/db/ paths.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

command=$(jq -r '.tool_input.command // empty' <<<"$payload")
normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

# ── doc/db search detection ──
has_docdb_search() {
  local cmd="$1"
  if echo "$cmd" | grep -qE '\b(grep|rg|ag|ack|find|cat|head|ls)\b[^|;&]*\bdoc/db/'; then
    return 0
  fi
  return 1
}

if ! has_docdb_search "$normalized"; then
  echo "{}"
  exit 0
fi

# Require git; allow silently if not available or not in a repo.
if ! command -v git >/dev/null 2>&1; then
  echo "{}"; exit 0
fi
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "{}"; exit 0
fi

# Last commit timestamps (committer date, epoch seconds).
# Disable signature-verification output (some local git configs prepend a
# "Good git signature for..." line) so the format string yields a clean value.
mig_ts=$(git -c log.showSignature=false log -1 --format=%ct -- migrations/ 2>/dev/null || echo 0)
doc_ts=$(git -c log.showSignature=false log -1 --format=%ct -- doc/db/ 2>/dev/null || echo 0)
mig_ts=${mig_ts:-0}
doc_ts=${doc_ts:-0}

# Working-tree dirty lists.
mig_dirty=$(git status --porcelain migrations/ 2>/dev/null | awk '$2 ~ /\.sql$/ {print $2}')
doc_dirty=$(git status --porcelain doc/db/ 2>/dev/null | awk '{print $2}')
mig_dirty_count=$(printf '%s' "$mig_dirty" | grep -c . || true)
doc_dirty_count=$(printf '%s' "$doc_dirty" | grep -c . || true)
mig_dirty_count=${mig_dirty_count:-0}
doc_dirty_count=${doc_dirty_count:-0}

mig_dirty_excerpt=$(printf '%s' "$mig_dirty" | head -5)
doc_dirty_excerpt=$(printf '%s' "$doc_dirty" | head -5)

# ── DEFINITELY STALE ──
# Committed migrations newer than committed doc/db, AND no uncommitted
# doc/db updates that might be a regeneration in progress.
if (( mig_ts > doc_ts )) && (( doc_dirty_count == 0 )); then
  mig_commit=$(git -c log.showSignature=false log -1 --format='%h %ci %s' -- migrations/ 2>/dev/null || echo "unknown")
  doc_commit=$(git -c log.showSignature=false log -1 --format='%h %ci %s' -- doc/db/ 2>/dev/null || echo "(none)")

  reason_text="BLOCKED: doc/db/ is stale; searching it would teach the WRONG current state.

WHY: committed migrations are newer than committed doc/db, and there are no uncommitted doc/db updates to explain the gap.
  - last migrations/ commit: ${mig_commit}
  - last doc/db/ commit:     ${doc_commit}

FIX (in this order):
  ./dev.sh generate-db-documentation        # regenerates doc/db/ from current DB
  git add doc/db/                           # stage the refresh
  git commit -m 'doc: refresh db docs'      # land it

THEN retry your doc/db/ search.

Need the schema RIGHT NOW without refreshing? Query the live DB:
  echo \"\\\\d public.SOME_TABLE\" | ./sb psql
  echo \"\\\\sf SCHEMA.FUNCTION_NAME\" | ./sb psql

Command that tripped this rule:
  ${normalized:0:200}

Hook source: .claude/hooks/doc-db-freshness.sh"

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

# ── WORK IN FLIGHT ──
# Uncommitted activity in either migrations/ or doc/db/. Allow but warn:
# the searcher must judge whether this is their own in-flight work
# (already aware) or another teammate's work (must check).
if (( mig_dirty_count > 0 )) || (( doc_dirty_count > 0 )); then
  scenario=""
  if (( mig_dirty_count > 0 && doc_dirty_count > 0 )); then
    scenario="BOTH migrations/ AND doc/db/ have uncommitted changes — schema and docs are likely being updated together. Verify they're consistent before relying on doc/db, especially if some changes aren't yours."
  elif (( mig_dirty_count > 0 )); then
    scenario="migrations/ has uncommitted .sql change(s) but doc/db/ has none — if those migrations are yours and not yet schema-applied + documented, doc/db reflects the PRE-migration state. If those migrations aren't yours, check git status / git diff to see what's in flight."
  else
    scenario="doc/db/ has uncommitted changes but no in-flight migrations — either a manual edit, a partial regeneration, or a refresh-only commit being prepared. Verify the refresh covers the latest committed migrations."
  fi

  details=""
  if (( mig_dirty_count > 0 )); then
    details="${details}\nUncommitted in migrations/ (${mig_dirty_count} file(s); first 5):\n${mig_dirty_excerpt}"
  fi
  if (( doc_dirty_count > 0 )); then
    details="${details}\nUncommitted in doc/db/ (${doc_dirty_count} file(s); first 5):\n${doc_dirty_excerpt}"
  fi

  warn_text="WARNING (doc-db-freshness.sh): work in flight near doc/db/ ↔ migrations/.

${scenario}
${details}

If this is your own work, you're aware and can proceed. If not, run \`git status migrations/ doc/db/\` and read the in-flight files before trusting doc/db search results."

  escaped=$(jq -Rn --arg r "$warn_text" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": ${escaped}
  }
}
EOF
  exit 0
fi

# ── FRESH ──
echo "{}"
