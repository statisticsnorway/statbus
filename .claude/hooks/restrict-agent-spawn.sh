#!/bin/bash
# restrict-agent-spawn.sh — PreToolUse hook on Agent and Bash tools.
#
# Team roles on this project: foreman (roster name "team-lead"), engineer,
# mechanic, tester, operator. See .claude/team/README.md for the full roster
# and the cost-aware delegation pattern.
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
# === Caller identification (STATBUS-168 — architect ruling + re-ruling, 2026-07-14) ===
#
# DERIVE, DON'T RECORD. No hand-maintained session id survives session
# rotation (/clear, crash, compaction) — two production incidents (STATBUS-168)
# proved a stored `leadSessionId` goes stale and either silently disarms every
# guard (if the resolved team config doesn't even exist) or hard-denies a
# legitimate rotated foreman (if it does). Identity now comes ONLY from live
# process lineage, resolved fresh on every call.
#
# THE FIRST DESIGN (env marker CLAUDE_CODE_CHILD_SESSION) WAS REFUTED BY ITS
# OWN MANDATED PROBE before ship: the ruling's premise was "root sessions run
# bare, so the marker is absent for the lead" — P1, run in the LIVE foreman
# session, found the marker SET there too (root and teammate sessions are
# indistinguishable by that env var on this harness). The probe existed
# exactly to catch this; it did. Re-ruled same day to SPAWN-ARGV ANCESTRY
# (candidate b), validated live on both endpoints — PR1 (root): hop 2 of the
# root session's own process ancestry is `claude --effort max --resume`, no
# --agent-* flags. PR2 (teammate): hop 2 is `claude ... --agent-id
# X@<team> --agent-name X --team-name <team> ...` — the harness's own spawn
# declaration, positive identity, not a heuristic. PR3 re-validated the SAME
# shape from INSIDE a real PreToolUse hook invocation on both a root and a
# teammate session (the hook's own process adds one ancestry hop vs. a plain
# Bash-tool command; the bounded walk-to-nearest-claude-ancestor tolerates
# that transparently). PR4 found the in-process-subagent residual EMPTY on
# this harness (see BOUNDED RESIDUAL below) — better than the original design
# assumed. PR5 found zero argv truncation on `ps -ww` across every live
# teammate process observed (longest 287 chars).
#
# RESOLUTION ORDER (comment #7; each step can only mis-DENY, never mis-GRANT):
#   Step 1 — ARGV IDENTITY (authoritative when a claude ancestor is found).
#            Walk this process's own ancestry (bounded ~15 hops, `ps -ww -o
#            ppid=,command=`, full untruncated argv) to the nearest `claude`
#            entrypoint.
#              - No --agent-name on that entrypoint → POSITIVE evidence of a
#                ROOT session (the lead's own shell, or the King's — a
#                spawned teammate ALWAYS carries the flag) → caller="foreman".
#              - --agent-name X present → the caller IS X: a roster hit
#                normalizes X to "foreman" when that member's agentType==
#                "team-lead", otherwise caller=X; a NON-roster X is
#                unknown-child (an argv identity that doesn't name a real
#                teammate is still authoritative — it does NOT fall through
#                to Step 2). A `--team-name` on the same entrypoint that does
#                NOT match this checkout's OWN resolved team name means that
#                ancestor belongs to a different clone/team and is treated as
#                not-found here (defends the cross-clone fixture, comment #1).
#   Step 2 — no claude ancestor found AT ALL within the bounded walk →
#            TRANSCRIPT ROSTER-GREP fallback (STATBUS-118 most-count match,
#            unchanged mechanics): covers a roster teammate whose process
#            happens to lack spawn argv. A hit normalizes team-lead→foreman
#            exactly as Step 1 does.
#   Step 3 — neither step resolved anything → unknown-child. Permissive on
#            ordinary ops (Tier 1 below); DENY on release (Tier 2).
#
# BOUNDED RESIDUAL (documented, not silently assumed — PR4, 2026-07-14): an
# IN-PROCESS background subagent (spawned via the Agent tool while the
# foreman keeps running, named "pr4-probe" for the probe) was probed live and
# found to be a SEPARATE, FULLY TEAMED process — the harness's spawn hooks
# required it to join the roster, and its own ancestry (log evidence,
# /tmp/statbus-hook-ancestry-debug.log, 2026-07-14T10:41:59Z) carries
# `--agent-id pr4-probe@session-7719192b --agent-name pr4-probe --team-name
# session-7719192b --parent-session-id <foreman's>` — full identity argv,
# exactly like any other teammate (and, before its spawn teamed it, a
# non-roster --agent-name would have landed unknown-child: Tier 1
# permissive, Tier 2 denied — the classifier's mis-deny-never-mis-grant
# property held on this data too). The residual this ruling anticipated (an
# unidentifiable in-process child inheriting the lead's identity) is EMPTY on
# this harness — every spawned agent, in-process or not, is independently
# identifiable. Kept documented rather than deleted: a future harness change
# that runs a subagent truly in-process (no separate claude entrypoint at
# all) would hit Step 1's "no claude ancestor found" path and fall to Step
# 2/3, same as any other unidentifiable child — never silently inherit
# foreman. The release gate ALSO carries an explicit no-workaround
# instruction to the calling LLM (see NO_WORKAROUND below) as DEFENSE IN
# DEPTH regardless of this residual's current emptiness: an agent that
# somehow did pass identification is still bound by that sentence at the
# gate (same doctrine as naming dangerous operations so any agent calls the
# human) — so even if a future harness change reopened the residual, the
# gate's own text still voids the workaround space.
#
# TWO-TIER POLICY (replaces the old blanket "unidentifiable → permissive"
# sentence, which directly contradicted Rule 5's existing deny-on-unknown):
#   Tier 1 — ordinary ops (Agent spawn's bg/bypass rules, Rule 4 git ops):
#            unidentifiable caller → PERMISSIVE (never hard-break legitimate
#            work; these are role guards on IDENTIFIED callers, not identity
#            checks in themselves).
#   Tier 2 — authority-gated ops (Rule 5, `./sb release prerelease`):
#            caller MUST resolve positively to "foreman"; unknown-child →
#            DENY. This no longer costs anything legitimate: a genuine
#            foreman (root OR a roster-matched team-lead transcript) can no
#            longer land in "unknown" — only a confused/unaccountable child
#            can, and that is exactly what Tier 2 exists to block.
#
# MISSING CONFIG = LOUD, NEVER SILENT. If the resolved TEAM_CONFIG file does
# not exist, every ALLOW decision on the Agent/Bash gated paths ALSO carries a
# top-level `systemMessage` (Claude Code hooks JSON schema — a warning shown to
# the user regardless of tool/decision, verified against the official hooks
# reference 2026-07-14: https://code.claude.com/docs/en/hooks) so the operator
# SEES that role guards are inactive instead of the guard silently disarming
# (STATBUS-168's root incident). NOT a deny: a missing config is legitimate in
# a solo session, and the root foreman must never be bricked by a stale
# pointer — root identification above is config-independent by design. A
# CHILD session with no config still resolves unknown-child, so the release
# gate stays fail-closed regardless.
#
# VOCABULARY — ONE NORMALIZATION BOUNDARY (fixes the previously-broken
# SendMessage hints, which hardcoded 'foreman' — not a routable roster name).
# Role tests keep "foreman" internally (matches every rule/doc/message
# above). Every EMITTED SendMessage hint instead interpolates $LEAD_NAME, the
# routable name read from config: the roster member whose agentId equals the
# config's top-level `leadAgentId` (today "team-lead"). Lead RECOGNITION
# (Step 1 above) keys on agentType=="team-lead", never on a hardcoded display
# name — the display name is free to change; the type tag is not.
#
# Parameterization (precedence: high → low):
#   CLAUDE_TEAM_NAME   — team name inside ${CLAUDE_CONFIG_DIR}/teams/. Set
#                        per-shell when you want a non-default team.
#   .claude/team.name  — project-local file, single line containing a team
#                        name. Lets per-checkout teams coexist (e.g. one user
#                        running two statbus checkouts in parallel, each with
#                        its own tester slot) without touching settings.json
#                        or shell env. Resolved relative to the invoking
#                        shell's cwd — each checkout's hook call only ever
#                        reads ITS OWN .claude/team.name, so two clones on one
#                        machine never cross-resolve each other's team config.
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
TEAM_CONFIG_MISSING=false
if [[ ! -f "$TEAM_CONFIG" ]]; then
  TEAM_CONFIG_MISSING=true
fi
MISSING_CONFIG_SYSMSG="restrict-agent-spawn: team config NOT FOUND at ${TEAM_CONFIG} (resolved via CLAUDE_TEAM_NAME | .claude/team.name | default); teammate role guards INACTIVE — fix .claude/team.name"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Agent" && "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

session_id=$(jq -r '.session_id // empty' <<<"$payload")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$payload")

# ── the King's rider (2026-07-14): every authority-gate message (deny, and
# the allow/notice paths that carry identity-uncertainty) must tell the
# calling LLM it cannot route around the gate. Doctrine: same as naming
# dangerous operations so any agent calls the human — the sentence voids the
# workaround space itself, regardless of who or what tripped the gate. ──
NO_WORKAROUND="You cannot work around this gating unless you have an explicit blessing from the King (or person in control)."

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

# emit_allow_note <reason> — allow with an explanatory reason. When the team
# config is missing, ALSO attaches the top-level systemMessage (loud, never
# silent — STATBUS-168 AC#2) so the operator sees role guards are inactive.
emit_allow_note() {
  local _note="$1"
  local _escaped _sys
  _escaped=$(jq -Rn --arg r "$_note" '$r')
  if [[ "$TEAM_CONFIG_MISSING" == "true" ]]; then
    _sys=$(jq -Rn --arg m "$MISSING_CONFIG_SYSMSG" '$m')
    cat <<EOF
{
  "systemMessage": ${_sys},
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
  else
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
  fi
}

# emit_allow — bare allow, no note. Still carries the missing-config
# systemMessage (STATBUS-168 AC#2: loud on EVERY gated-path allow, not just
# the ones that already had a reason to explain).
emit_allow() {
  if [[ "$TEAM_CONFIG_MISSING" == "true" ]]; then
    jq -n --arg m "$MISSING_CONFIG_SYSMSG" '{systemMessage: $m}'
  else
    echo "{}"
  fi
}

# ── identify caller (STATBUS-168) ──
# The harness concept is "team-lead"; in our vocabulary that's the foreman.

# LEAD_NAME — the routable roster name for SendMessage hints (today
# "team-lead"). Looked up via the config's leadAgentId, never hardcoded, so a
# future rename of the lead's display name doesn't re-break the hints the way
# a bare 'foreman' string did. Falls back to "foreman" only if config/lookup
# is unavailable — still a usable (if possibly stale) hint, never a crash.
LEAD_NAME="foreman"
if [[ -f "$TEAM_CONFIG" ]]; then
  _lead_agent_id=$(jq -r '.leadAgentId // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
  if [[ -n "$_lead_agent_id" ]]; then
    _lead_name_lookup=$(jq -r --arg id "$_lead_agent_id" '.members[] | select(.agentId == $id) | .name // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
    if [[ -n "$_lead_name_lookup" ]]; then
      LEAD_NAME="$_lead_name_lookup"
    fi
  fi
fi

# THIS_TEAM_NAME — this checkout's own resolved team, used to gate the argv
# walk's --team-name bonus check below (a cross-clone/other-team ancestor
# must never be treated as identifying THIS checkout's caller).
THIS_TEAM_NAME="$(resolve_team_name)"

# _resolve_via_argv — STATBUS-168 Step 1 (architect re-ruling, comment #7).
# Walks this process's own ancestry (bounded ~15 hops) to the nearest
# `claude` entrypoint and echoes exactly one of:
#   ROOT         — a claude ancestor was found with NO --agent-name (positive
#                  evidence of a root/user-driven session).
#   AGENT:<name> — a claude ancestor was found WITH --agent-name <name>, and
#                  (if present) its --team-name matches THIS checkout.
#   (empty)      — no claude ancestor found within the bounded walk, OR the
#                  nearest one's --team-name belongs to a DIFFERENT
#                  checkout/team (treated as not-found here, comment #1's
#                  cross-clone fixture).
# `ps -ww` (unlimited width) avoids argv truncation — PR5 verified this clean
# up to 287 chars across every live teammate process observed, 2026-07-14.
#
# TEST SEAM: STATBUS_HOOK_TEST_ARGV_RESULT, when SET (including to an empty
# string — `${VAR+x}`, not `${VAR:-}`), short-circuits the real `ps` walk and
# echoes that value instead. Lets the unit test suite stub all three
# resolution outcomes deterministically; the live `ps` walk itself is
# validated separately by the PR1-PR5 acceptance probes against real
# sessions (STATBUS-168), not by this suite. Unset in production — the real
# walk always runs.
_resolve_via_argv() {
  if [[ -n "${STATBUS_HOOK_TEST_ARGV_RESULT+x}" ]]; then
    printf '%s' "$STATBUS_HOOK_TEST_ARGV_RESULT"
    return 0
  fi
  local _pid=$$ _hop _line _ppid _cmd
  for _hop in $(seq 1 15); do
    _line=$(ps -ww -o ppid=,command= -p "$_pid" 2>/dev/null) || break
    [ -n "$_line" ] || break
    _ppid=$(printf '%s' "$_line" | awk '{print $1}')
    _cmd=$(printf '%s' "$_line" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//')
    if [[ "$_cmd" =~ ^([^[:space:]]*/)?claude(/versions/[^[:space:]/]+)?([[:space:]]|$) ]]; then
      if [[ "$_cmd" =~ --agent-name[[:space:]]+([^[:space:]]+) ]]; then
        local _an="${BASH_REMATCH[1]}"
        if [[ "$_cmd" =~ --team-name[[:space:]]+([^[:space:]]+) ]]; then
          local _tn="${BASH_REMATCH[1]}"
          if [[ "$_tn" != "$THIS_TEAM_NAME" ]]; then
            echo ""
            return 0
          fi
        fi
        echo "AGENT:${_an}"
        return 0
      fi
      echo "ROOT"
      return 0
    fi
    [ -n "$_ppid" ] || break
    if [ "$_ppid" -le 1 ] 2>/dev/null; then break; fi
    _pid=$_ppid
  done
  echo ""
}

caller=""
caller_basis="unresolved"
_argv_result=$(_resolve_via_argv)
if [[ "$_argv_result" == "ROOT" ]]; then
  caller="foreman"
  caller_basis="argv: root (claude ancestor found, no --agent-name)"
elif [[ "$_argv_result" == AGENT:* ]]; then
  _argv_name="${_argv_result#AGENT:}"
  caller_basis="argv --agent-name ${_argv_name}"
  # Authoritative once a claude ancestor names an agent — never falls
  # through to Step 2, even when the name isn't a roster member (that IS
  # unknown-child, decisively, not a cue to go guess via the transcript).
  if [[ -f "$TEAM_CONFIG" ]]; then
    _argv_type=$(jq -r --arg n "$_argv_name" '.members[] | select(.name == $n) | .agentType // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
    if [[ "$_argv_type" == "team-lead" ]]; then
      caller="foreman"
    else
      _argv_hit=$(jq -r --arg n "$_argv_name" '.members[] | select(.name == $n) | .name' "$TEAM_CONFIG" 2>/dev/null || echo "")
      if [[ -n "$_argv_hit" ]]; then
        caller="$_argv_name"
      fi
    fi
  fi
else
  # Step 2 (STATBUS-168 comment #7): the argv walk found NO claude ancestor
  # at all — fall back to transcript roster-grep (STATBUS-118 most-count
  # match, unchanged mechanics; covers a roster teammate whose process
  # happens to lack spawn argv). Robust against newer Claude Code CLIs that
  # can record a session's auto-generated ai-title in `agentName` (e.g. a
  # reused pane keeps an old throwaway title) instead of the routing name —
  # picking the roster member whose agentName appears MOST avoids the naive
  # first-match false-positive. NO first-agentName fallback: `agentName` can
  # hold a non-role ai-title, which falsely blocked the foreman's OWN spawns
  # before this rewrite — on no roster hit, caller stays "" (Step 3: unknown).
  if [[ -n "$transcript_path" && -f "$transcript_path" && -f "$TEAM_CONFIG" ]]; then
    _winning_name=$(
      while IFS= read -r _member; do
        if [[ -z "$_member" ]]; then continue; fi
        _count=$(grep -cF "\"agentName\":\"${_member}\"" "$transcript_path" 2>/dev/null || true)
        # NB: `[[ … ]] && printf` here would trip `set -e` (+ pipefail via the
        # surrounding pipeline) whenever the test is false — i.e. for every
        # roster member NOT in this transcript — crashing the hook before it
        # can decide. Use an explicit `if` so the false branch is set -e-safe.
        if [[ "${_count:-0}" -gt 0 ]]; then printf '%s %s\n' "$_count" "$_member"; fi
      done < <(jq -r '.members[].name' "$TEAM_CONFIG" 2>/dev/null || true) \
        | sort -rn | head -1 | awk '{print $2}'
    )
    if [[ -n "$_winning_name" ]]; then
      caller_basis="transcript roster-grep: ${_winning_name} (no claude ancestor found via argv)"
      _winning_type=$(jq -r --arg n "$_winning_name" '.members[] | select(.name == $n) | .agentType // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
      if [[ "$_winning_type" == "team-lead" ]]; then
        caller="foreman"
      else
        caller="$_winning_name"
      fi
    else
      caller_basis="unknown: no claude ancestor found via argv, no transcript roster hit"
    fi
  else
    caller_basis="unknown: no claude ancestor found via argv, no usable transcript"
  fi
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
      # Unknown (child, no roster hit) — Tier 1 (ordinary op): apply
      # background + bypassPermissions blanket rules, then permissive allow.
      # The no-workaround sentence still applies — an unidentified spawner
      # is exactly the confused-child case the doctrine targets.
      check_bg_and_bypass
      emit_allow_note "restrict-agent-spawn: caller identity could not be determined (${caller_basis}; session_id=${session_id}, transcript_path=${transcript_path}). Background + bypassPermissions verified. Allowing (Tier 1: ordinary op). ${NO_WORKAROUND}"
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
  - NEW ROLE (truly needed): SendMessage(to: '${LEAD_NAME}', ...) and ask.${context_suffix}

${NO_WORKAROUND}

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
  - If genuinely needed, surface to the foreman: SendMessage({to: '${LEAD_NAME}', ...}).

${NO_WORKAROUND}

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  fi

  # Rule 5: `./sb release prerelease` → only the foreman (Tier 2:
  # authority-gated — caller must resolve positively to foreman; unknown-child
  # is DENIED, never permissive. See the two-tier policy header note.)
  if echo "$normalized_for_match" | grep -qE '\./sb\s+release\s+prerelease\b'; then
    if [[ "$caller" == "foreman" ]]; then
      emit_allow
      exit 0
    fi
    if [[ -z "$caller" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): release command from an unidentified (unknown-child) caller — cannot confirm this is the foreman (${caller_basis}).

WHY: only the foreman may run release commands. They modify tags and branches — foreman's authority. This is a Tier 2, authority-gated op: unlike ordinary rules, an unidentified caller here is DENIED, not given the benefit of the doubt.

WHAT TO DO: SendMessage(to: '${LEAD_NAME}') and ask them to run it.

${NO_WORKAROUND}

Command: ${normalized:0:200}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    emit_deny "BLOCKED (restrict-agent-spawn.sh): only the foreman may run \`./sb release prerelease\`, not '${caller}'.

WHY: release commands are foreman's authority — they modify tags and branches.

WHAT TO DO: SendMessage({to: '${LEAD_NAME}', message: 'please run: ${normalized:0:120}'}).

${NO_WORKAROUND}

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
    exit 0
  fi
fi

# Passed all checks — allow.
emit_allow
