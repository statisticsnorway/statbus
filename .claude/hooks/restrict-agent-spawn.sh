#!/bin/bash
# restrict-agent-spawn.sh — PreToolUse hook on Agent and Bash tools.
#
# Team roles on this project: foreman (team-lead), engineer, mechanic,
# tester, operator. See .claude/team/README.md for the full roster and
# the cost-aware delegation pattern.
#
# === AGENT tool rules ===
#
# 1. Only the foreman may spawn agents. All other roles → DENY. Use
#    SendMessage to reach an existing teammate, or ask the foreman to
#    spawn a new one.
#
# 2. Foreman-spawned agents must set run_in_background: true AND
#    mode: "bypassPermissions". Without bypassPermissions, a background
#    subagent silently hangs on the first permission-prompted tool call
#    (no interactive user to approve).
#
# 3. Name-collision guard (all callers): if the `name` parameter matches
#    an existing team roster member, DENY — almost certainly a mistake.
#
# === BASH tool rules ===
#
# Test-run serialization is NO LONGER enforced here. It moved to a direct
# exclusive lock taken by the test runner itself (acquire_test_run_lock in
# dev.sh): concurrent runs that touch the shared pg_regress templates fail
# loudly on lock contention, and the lock self-releases on process death.
# The lock supersedes the old "only the tester may run ./dev.sh test"
# identity gate — which was a proxy for serialization and broke on every
# clear/crash/compaction (a fresh tester was refused, a post-compaction
# foreman was unidentifiable). "The tester runs the tests" remains a TEAM
# CONVENTION for coordination and reporting, not a machine-enforced check.
#
# 4. `git commit / revert / cherry-pick / rebase / am / push` → blocked for
#    operator and tester. These Haiku-tier roles are scoped to read-only
#    legwork (operator) and test execution (tester); committing or pushing
#    bypasses pre-commit review and produces work nobody asked for. The
#    smaller-model context window makes role-file paperwork unreliable
#    here — structural enforcement is the principled fix.
#
# 5. `./sb release prerelease` → only the foreman may run it. Release
#    commands modify tags and branches — foreman's authority.
#
# Caller identification:
#   - session_id == leadSessionId (from team config) → "foreman"
#   - else grep agentName from the session's transcript .jsonl
#   - if unidentifiable → permissive fallback (never hard-break legitimate work)
#
# Parameterization (precedence: high → low):
#   CLAUDE_TEAM_NAME   — team name inside ${CLAUDE_CONFIG_DIR}/teams/. Set
#                        per-shell when you want a non-default team.
#   .claude/team.name  — project-local file, single line containing a team
#                        name. Lets per-checkout teams coexist (e.g. one user
#                        running two statbus checkouts in parallel, each with
#                        its own tester slot) without touching settings.json
#                        or shell env.
#   default            — "team"

set -euo pipefail

resolve_team_name() {
  if [[ -n "${CLAUDE_TEAM_NAME:-}" ]]; then
    echo "$CLAUDE_TEAM_NAME"
    return
  fi
  if [[ -f ".claude/team.name" ]]; then
    local _name
    _name=$(head -1 ".claude/team.name" | tr -d '[:space:]' || true)
    if [[ -n "$_name" ]]; then
      echo "$_name"
      return
    fi
  fi
  echo "team"
}

TEAM_CONFIG="${CLAUDE_CONFIG_DIR}/teams/$(resolve_team_name)/config.json"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Agent" && "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

session_id=$(jq -r '.session_id // empty' <<<"$payload")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$payload")

# ── helpers ──

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

emit_allow_note() {
  local _note="$1"
  local _escaped
  _escaped=$(jq -Rn --arg r "$_note" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
}

# ── identify caller ──
# The harness concept is "team-lead"; in our vocabulary that's the foreman.

lead_session_id=""
if [[ -f "$TEAM_CONFIG" ]]; then
  lead_session_id=$(jq -r '.leadSessionId // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
fi

caller=""
if [[ -n "$session_id" && -n "$lead_session_id" && "$session_id" == "$lead_session_id" ]]; then
  caller="foreman"
elif [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  # Resolve identity by the team ROSTER name, robust against newer Claude Code
  # CLIs that can record a session's auto-generated ai-title in `agentName`
  # (e.g. a reused pane keeps an old throwaway title) instead of the routing
  # name — which broke the naive first-`agentName` match. Pick the roster
  # member whose agentName appears MOST in this transcript: the session's own
  # identity dominates; any relayed/quoted name is rare. Can never mis-GRANT
  # identity — it only matches exact current roster names.
  if [[ -f "$TEAM_CONFIG" ]]; then
    caller=$(
      while IFS= read -r _member; do
        if [[ -z "$_member" ]]; then continue; fi
        _count=$(grep -cF "\"agentName\":\"${_member}\"" "$transcript_path" 2>/dev/null || true)
        # NB: `[[ … ]] && printf` here would trip `set -e` (+ pipefail via the
        # surrounding pipeline) whenever the test is false — i.e. for every
        # roster member NOT in this transcript — crashing the hook before it can
        # decide. Use an explicit `if` so the false branch is set -e-safe.
        if [[ "${_count:-0}" -gt 0 ]]; then printf '%s %s\n' "$_count" "$_member"; fi
      done < <(jq -r '.members[].name' "$TEAM_CONFIG" 2>/dev/null || true) \
        | sort -rn | head -1 | awk '{print $2}'
    )
  fi
  # NO first-agentName fallback. `agentName` can hold the session's auto-derived
  # ai-title (after /rename it became "statbus-speed") — that is NOT a role, and
  # it falsely blocked the foreman's OWN spawns. The roster-match above only ever
  # returns a REAL member name; on no match the caller stays "" and is treated
  # permissively below (bootstrap, post-/clear, and unknown sessions). Never
  # derive a role from the session name/ai-title. (STATBUS-118)
  :
fi

# ── Agent tool ────────────────────────────────────────────────────────

if [[ "$tool" == "Agent" ]]; then
  run_in_bg=$(jq -r '.tool_input.run_in_background // false' <<<"$payload")
  new_agent_name=$(jq -r '.tool_input.name // ""' <<<"$payload")
  new_model=$(jq -r '.tool_input.model // "(default)"' <<<"$payload")
  spawn_mode=$(jq -r '.tool_input.mode // "default"' <<<"$payload")
  context_suffix=" (caller='${caller}', new agent name='${new_agent_name}', model='${new_model}', run_in_background=${run_in_bg}, mode=${spawn_mode})"

  # Rule 3: Name-collision guard — check before role-based rules.
  if [[ -n "$new_agent_name" && -f "$TEAM_CONFIG" ]]; then
    roster_names=$(jq -r --arg cwd "${CLAUDE_PROJECT_DIR:-}" '.members[] | select($cwd == "" or (.cwd // "") == $cwd) | .name' "$TEAM_CONFIG" 2>/dev/null || true)
    if echo "$roster_names" | grep -qxF "$new_agent_name"; then
      roster_list=$(echo "$roster_names" | sed 's/^/  - /')
      emit_deny "BLOCKED (restrict-agent-spawn.sh): Agent name '${new_agent_name}' already exists in the team roster.

WHY: spawning a new agent with an existing teammate's name throws away warm context, burns cold-start tokens, and creates confusion about which instance will receive SendMessage calls.

WHAT TO DO:
  Use SendMessage to reach the existing agent instead:
    SendMessage({to: '${new_agent_name}', message: '...'})

Current team roster:
${roster_list}

If you genuinely need a brand-new ephemeral agent (not a teammate), give it a unique task-scoped name — e.g. 'researcher', 'scout-install', 'auditor'.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  fi

  # Shared check: background + bypassPermissions requirement.
  check_bg_and_bypass() {
    if [[ "$run_in_bg" != "true" ]]; then
      emit_deny "BLOCKED: Agent spawn must use run_in_background: true.

WHY: requiring background (long-running, reused-via-SendMessage) agents is a cost-AND-control rule, three ways — all lose-lose if ignored:
  1. COST (amortization): a freshly spawned agent burns many tokens reorienting and rebuilding its initial context before it can even answer. A long-running agent — spawned ONCE, then reused via SendMessage — pays that initialization cost a single time and amortizes it across many turns. Re-spawning pays the cold start every time.
  2. CONTROL: a foreground spawn stalls the conversation — you can't continue working, respond to the user, or be redirected, until the subagent finishes (which can take minutes).
  3. VISIBILITY: only a backgrounded agent gets its own console the user can see and talk to directly. A foreground subagent is private to its spawner — the user goes blind, can't course-correct, and tokens get spent on a wrong turn nobody can stop.
Background spawns let you dispatch work, keep talking to the user, and run the team concurrently; you get a notification when the subagent messages you.

WHAT TO DO: retry the Agent call with 'run_in_background: true' (combine with 'mode: \"bypassPermissions\"' per the rule below) so the agent runs as a persistent, visible, reusable teammate.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    if [[ "$spawn_mode" != "bypassPermissions" ]]; then
      emit_deny "BLOCKED: background Agent spawn must set mode: \"bypassPermissions\".

WHY: a subagent running in the background has no interactive user to approve tool-permission prompts. Without bypassPermissions, the first time the subagent calls a tool that requires approval (Edit, Write, many Bash commands), the harness queues a prompt that nobody will ever answer. The agent appears to be working but silently does nothing — classic confusing failure.

WHAT TO DO: retry the Agent call with 'mode: \"bypassPermissions\"'. Combine with 'run_in_background: true' and the agent can actually execute its work.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  }

  case "$caller" in
    "foreman")
      check_bg_and_bypass
      ;;

    "")
      # Unknown caller — apply background + bypassPermissions blanket rules.
      check_bg_and_bypass
      emit_allow_note "restrict-agent-spawn: caller identity could not be determined (session_id=${session_id}, leadSessionId=${lead_session_id}, transcript_path=${transcript_path}). Background + bypassPermissions verified. Allowing."
      exit 0
      ;;

    *)
      # Rule 1: any identified non-foreman caller — DENY entirely.
      emit_deny "BLOCKED: '${caller}' cannot spawn agents. Only the foreman may spawn.

WHY: the cost-aware team pattern has one spawner (the foreman) and a fixed roster. Spawning from inside a specialist or worker role burns tokens on cold starts and hides work from the foreman.

WHAT TO DO:
  - LEGWORK (reads, greps, SSH, log tails, summaries): SendMessage(to: 'operator', ...).
  - TESTS: SendMessage(to: 'tester', ...) or assign a Backlog.md task to 'tester'.
  - DIAGNOSIS and targeted fixes: SendMessage(to: 'mechanic', ...).
  - DESIGN or architectural work: SendMessage(to: 'engineer', ...).
  - NEW ROLE (truly needed): SendMessage(to: 'foreman', ...) and ask.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
      ;;
  esac

# ── Bash tool ─────────────────────────────────────────────────────────

elif [[ "$tool" == "Bash" ]]; then
  command=$(jq -r '.tool_input.command // empty' <<<"$payload")

  # Strip HEREDOC bodies (file/script CONTENT being written) BEFORE flattening
  # newlines, so a rule never matches a command that merely APPEARS inside
  # content the caller is AUTHORING rather than EXECUTING — e.g.
  #     cat > launcher.sh <<'EOF'
  #     ./dev.sh test fast      # documented in the script, not run here
  #     git push origin main    # ditto
  #     EOF
  # Only commands OUTSIDE heredoc bodies are real invocations to gate. Handles
  # <<EOF, <<'EOF', <<"EOF", and <<-EOF (tab-stripped terminator). The opener
  # line is kept (its pre-<< text may itself be a real command); the body and
  # the terminator line are dropped. After the terminator, matching RESUMES —
  # a gated command on a later line is still caught.
  #
  # KNOWN RESIDUALS (both deliberate, both out of this guardrail's scope):
  #   1. Here-STRINGS (`cmd <<<foo`) are NOT heredocs; the `(^|[^<])` prefix
  #      below stops the `<<` inside `<<<` from being read as an opener.
  #   2. Interpreter-fed heredocs (`bash <<'EOF' … EOF`, `ssh host <<EOF`) run
  #      their body as EXECUTED content, yet we still strip it. Catching that
  #      would require a shell-semantics parser; anyone laundering a gated
  #      command through an interpreter heredoc is deliberately evading, which
  #      a content-pattern hook never claims to stop. The body is dropped.
  # A stray `<< word` inside a quoted string on a multi-line command can still
  # be misread as an opener — but that only ever DROPS following lines from
  # matching (weakens a block), never fabricates one, so it can't wrongly deny.
  _optquote=$'[\047\042]?'   # optional ' or " around the delimiter word
  # (^|[^<]) — the `<<` must start the line or follow a non-`<`, so `<<<` (a
  # here-string) does not match as a heredoc opener. BASH_REMATCH: [1]=prefix
  # char, [2]=dash (<<-), [3]=delimiter word.
  _hd_re="(^|[^<])<<(-?)[[:space:]]*${_optquote}([A-Za-z_][A-Za-z0-9_]*)"
  command_no_heredoc=""
  _hd_in=0; _hd_delim=""; _hd_dash=0
  while IFS= read -r _hd_line || [ -n "$_hd_line" ]; do
    if [ "$_hd_in" -eq 1 ]; then
      _hd_t="$_hd_line"
      if [ "$_hd_dash" -eq 1 ]; then
        while [[ "$_hd_t" == $'\t'* ]]; do _hd_t="${_hd_t#$'\t'}"; done
      fi
      if [ "$_hd_t" = "$_hd_delim" ]; then _hd_in=0; fi
      continue   # drop body AND terminator line
    fi
    if [[ "$_hd_line" =~ $_hd_re ]]; then
      # NB: `[ -n .. ] && _hd_dash=1` as a bare statement would trip set -e when
      # the test is false; use an explicit if (same guard the caller-ID block uses).
      _hd_dash=0
      if [ -n "${BASH_REMATCH[2]}" ]; then _hd_dash=1; fi
      _hd_delim="${BASH_REMATCH[3]}"; _hd_in=1
      command_no_heredoc+="$_hd_line"$'\n'
      continue
    fi
    command_no_heredoc+="$_hd_line"$'\n'
  done <<<"$command"

  normalized=$(printf '%s' "$command_no_heredoc" | tr '\n' ' ' | tr -s ' ')

  # Strip commit message bodies before pattern-matching, so command strings
  # documented inside commit messages don't false-match hook patterns.
  # Handles: -m 'single'  -m "double"  -m $'ansi-c'  -F <path>
  # After tr-normalization the input is already single-line, so multi-line
  # HEREDOC bodies ($(cat <<'EOF'..EOF)) are covered by the double-quote case.
  # Caveat: if the message body itself contains double-quote characters the
  # [^"]* pattern stops at the first embedded ", leaving the tail unstripped.
  # Workaround: write the message to a file and use `git commit -F <file>`.
  # The -F path strip above handles that form cleanly. A shell-aware parser
  # is heavier than this problem is worth; -F is the documented escape hatch.
  if printf '%s' "$normalized" | grep -qE '^[[:space:]]*git[[:space:]]+commit\b'; then
    normalized_for_match=$(printf '%s' "$normalized" | sed -E \
      -e "s/-m[[:space:]]+'[^']*'//g" \
      -e 's/-m[[:space:]]+"[^"]*"//g' \
      -e "s/-m[[:space:]]+\\\$'[^']*'//g" \
      -e 's/-F[[:space:]]+[^[:space:]]+//g')
  else
    normalized_for_match="$normalized"
  fi

  # NOTE: the old Rule 4 ("only the tester may run ./dev.sh test") is RETIRED.
  # Test-run serialization is now enforced directly by an exclusive lock the
  # test runner takes itself (acquire_test_run_lock in dev.sh) — see the BASH
  # tool rules header above. No identity check on the test path remains.

  # Rule 4: commit-creating / push git ops → block operator + tester.
  # These Haiku-tier roles must not modify history; smaller-model context
  # windows make role-file rules unreliable, so enforce structurally.
  if echo "$normalized_for_match" | grep -qE '\bgit\s+(commit|revert|cherry-pick|rebase|am|push)\b'; then
    if [[ "$caller" == "operator" || "$caller" == "tester" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): '${caller}' cannot create or push commits.

WHY: operator and tester are read-only on git history. Operator does legwork (greps, log reads, summaries). Tester runs \`./dev.sh test\`. Neither commits, reverts, cherry-picks, rebases, applies mailboxes, or pushes — those bypass pre-commit review and produce work nobody asked for.

WHAT TO DO:
  - For a targeted fix: SendMessage({to: 'mechanic', message: '...'}).
  - For a substantive change: SendMessage({to: 'engineer', message: '...'}).
  - For a plan: SendMessage({to: 'architect', message: '...'}).
  - If genuinely needed, surface to foreman: SendMessage({to: 'foreman', ...}).

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  fi

  # Rule 5: `./sb release prerelease` → only the foreman.
  if echo "$normalized_for_match" | grep -qE '\./sb\s+release\s+prerelease\b'; then
    if [[ "$caller" == "foreman" ]]; then
      echo "{}"
      exit 0
    fi
    if [[ -z "$caller" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): release command from unidentified caller — cannot confirm this is the foreman.

WHY: only the foreman may run release commands. They modify tags and branches — foreman's authority.

WHAT TO DO: SendMessage(to: 'foreman') and ask them to run it.

Command: ${normalized:0:200}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    emit_deny "BLOCKED (restrict-agent-spawn.sh): only the foreman may run \`./sb release prerelease\`, not '${caller}'.

WHY: release commands are foreman's authority — they modify tags and branches.

WHAT TO DO: SendMessage({to: 'foreman', message: 'please run: ${normalized:0:120}'}).

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
    exit 0
  fi
fi

# Passed all checks — allow.
echo "{}"
