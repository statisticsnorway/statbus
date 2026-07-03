#!/bin/bash
# migration-cluster-statement-gate.sh — PreToolUse hook on Bash.
#
# STATBUS-116 (doc-025 E): block committing a NEW or CHANGED migrations/*.up.sql
# that introduces a CLUSTER-SCOPED statement. Cluster-scoped catalog writes
# (pg_db_role_setting, pg_authid, pg_tablespace, ALTER SYSTEM's postgresql.auto.conf)
# are NOT carried by pg_dump — so on every seed-restored box the migration's ledger
# row says "applied" while the effect is structurally absent. The STATBUS-110
# read-only exemption lost exactly this way (its first window-crossing upgrade
# deadlocked), and 20240102000000's timeouts + safeupdate preload were silently
# missing on every seed-restored box.
#
# The DESIGNED home for cluster-level re-arms is migrations/post_restore.sql
# (idempotent, admin-run on every `migrate up`, even zero-pending — so it re-arms
# on a seed-restored box), or init-db.sh (true cluster birth).
#
# DIFFS, does not SWEEP: only the ADDED lines of STAGED up-migrations are checked,
# so existing released migrations are grandfathered.
set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
[[ "$tool" != "Bash" ]] && { echo "{}"; exit 0; }
command=$(jq -r '.tool_input.command // empty' <<<"$payload")

# Only gate `git commit` (allow `git -C <dir> commit` too). Anything else no-ops.
if ! grep -qE '(^|[;&|][[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit(\b|$)' <<<"$command"; then
  echo "{}"; exit 0
fi

# Resolve a -C <dir> if present so `git diff --cached` targets the right repo.
gitdir=""
if [[ "$command" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  gitdir="${BASH_REMATCH[1]}"
fi
git_cmd=(git)
[[ -n "$gitdir" ]] && git_cmd=(git -C "$gitdir")

staged=$("${git_cmd[@]}" diff --cached --name-only --diff-filter=AM -- 'migrations/*.up.sql' 2>/dev/null || true)
[[ -z "$staged" ]] && { echo "{}"; exit 0; }

# Cluster-scoped statement patterns (added lines only). Role-membership GRANT is
# `GRANT <role> TO <role>` (no ON/privilege clause → no " ON " before TO).
pattern='(ALTER[[:space:]]+ROLE|CREATE[[:space:]]+ROLE|DROP[[:space:]]+ROLE|ALTER[[:space:]]+SYSTEM|TABLESPACE|GRANT[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+TO[[:space:]]+[a-zA-Z_])'
hits=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  added=$("${git_cmd[@]}" diff --cached -- "$f" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)
  # Strip the leading '+' and drop SQL line-comments so a comment mentioning a
  # cluster statement doesn't false-trip.
  body=$(sed -E 's/^\+//; s/--.*$//' <<<"$added")
  m=$(grep -inE "$pattern" <<<"$body" || true)
  [[ -n "$m" ]] && hits+="  ${f}:"$'\n'"$(sed 's/^/      /' <<<"$m")"$'\n'
done <<<"$staged"

if [[ -n "$hits" ]]; then
  reason="BLOCKED: a staged migration introduces a CLUSTER-SCOPED statement.

WHY: pg_dump is DATABASE-scoped — it cannot carry cluster catalogs (role GUCs via ALTER ROLE ... SET → pg_db_role_setting, roles via CREATE/DROP/ALTER ROLE → pg_authid, ALTER SYSTEM → postgresql.auto.conf, tablespaces, role-membership GRANTs). A migration that writes them records \"applied\" in the ledger, but the EFFECT is silently absent on every SEED-RESTORED box (fresh installs, post-upgrade). STATBUS-116/doc-025: the STATBUS-110 read-only exemption was lost exactly this way; 20240102000000's timeouts + safeupdate preload are missing on all seed-restored boxes.

OFFENDING statement(s) in staged up-migrations:
${hits}
WHAT TO DO INSTEAD:
  - Idempotent re-arm needed on every box (role GUCs, role-membership GRANTs, extension search_path):
      put it in migrations/post_restore.sql — it runs on every 'sb migrate up' (even zero-pending), as admin,
      so it re-arms on a seed-restored box. Mirror the released migration's statement there (duplicate, don't edit the released file).
  - True cluster birth (roles, cluster-wide settings on a fresh cluster):
      put it in init-db.sh.
If this is intentional and genuinely belongs in a migration, discuss it — do not force it through.

Hook source: .claude/hooks/migration-cluster-statement-gate.sh"

  jq -n --arg r "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $r
    }
  }'
  exit 0
fi

echo "{}"
