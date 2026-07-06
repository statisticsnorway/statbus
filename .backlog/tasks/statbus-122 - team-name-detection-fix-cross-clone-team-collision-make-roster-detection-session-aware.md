---
id: STATBUS-122
title: >-
  team-name-detection: fix cross-clone team collision + make roster detection
  session-aware
status: To Do
assignee: []
created_date: '2026-07-01 13:42'
updated_date: '2026-07-06 16:05'
labels:
  - tooling
  - not-install-upgrade
dependencies:
  - STATBUS-133
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: two checkouts can run their teams concurrently — ownership detected from the session/checkout, not a shared global name.
> BENEFIT: the cross-clone deadlock that already bit a real session (couldn't spawn canonical names OR message replacements → forced specialist proliferation) becomes impossible, and the broken-symlink failure mode gets a named error instead of "unidentified caller" misdirection (three repair attempts lost to that).
> STAGE: Team tooling.
> COMPLEXITY: engineer-substantial (cwd/session-filtered roster in two hooks + the dangling-alias fallback + fixture tests).
> DEPENDS ON: STATBUS-133 (hard in practice: same hook files; land after 133's commit to avoid conflicting edits).

---

ROOT CAUSE (proven 2026-07-01): `.claude/team.name = "statbus"` is git-tracked, so BOTH statbus checkouts (`/Users/jhf/ssb/statbus` and `/Users/jhf/ssb/statbus_speed`) resolve the SAME team name. A team name is a GLOBAL namespace (`${CLAUDE_CONFIG_DIR}/teams/<name>/config.json`) — ONE file shared by both clones. The live config's roster is ENTIRELY the OTHER clone's: `leadSessionId 2c632915`, all 6 members (team-lead/engineer/architect/mechanic/tester/operator) carry `agentId=…@session-2c632915` and `cwd=/Users/jhf/ssb/statbus`.

CONSEQUENCE (the deadlock): from a statbus_speed session, `restrict-agent-spawn.sh` (name-collision guard, reads `.members[].name`) blocks spawning engineer/tester/etc. (they are "in the roster"), and `route-alias.sh` (`get_roster` = `.members[].name`) only accepts those 6 names for SendMessage — but they are not live in this session, so the harness silently drops the message. Net: cannot spawn canonical names, cannot message freshly-spawned `pg-*` names → every delegation forces a brand-new spawn (the specialist-proliferation anti-pattern).

The hooks' own comment (`restrict-agent-spawn.sh:44-49`) states `.claude/team.name` is meant to let per-checkout teams coexist — committing it as "statbus" defeats that. There is NO liveness signal; mere presence in the shared file counts as "exists" (the "active flag is useless" observation).

FIX — two levels:
1. PER-CHECKOUT NAME (immediate unblock): each checkout gets a distinct team name → its own namespace. Options: `CLAUDE_TEAM_NAME` env per-clone (hooks check env FIRST) via `.claude/settings.local.json` (local/gitignored), OR gitignore `.claude/team.name` with per-clone content. E.g. statbus_speed → `statbus-speed`.
2. SESSION-AWARE ROSTER DETECTION (the real fix): `get_roster` (route-alias.sh) and the rule-3 name-collision guard (restrict-agent-spawn.sh) must filter `.members[]` to the CURRENT session/checkout — members whose `agentId` session == payload `session_id`, or whose `cwd` == `$CLAUDE_PROJECT_DIR` — not the raw global list. Then a shared namespace never cross-pollutes and detection stops relying on any active flag (cwd/session match IS the ownership/liveness signal). Investigate the 'dynamic team directory' (King recalls: discoverable via TeamCreate + SendMessage-to-self) as the authoritative live-member source; key detection off it if it exists.

Files: `.claude/hooks/route-alias.sh` (`get_roster`, `is_in_roster`), `.claude/hooks/restrict-agent-spawn.sh` (rule-3 name guard + caller ID), `.claude/hooks/enforce-team-name.sh`. Config: `${CLAUDE_CONFIG_DIR}/teams/statbus/config.json`. Context: this bit the power-group design session (agents pg-engineer/pg-tester/pg-frontend/pg-konsern couldn't be reused).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Two statbus checkouts can each run their own team concurrently with no roster collision (verify: statbus_speed can spawn engineer/tester AND message them while ../statbus's team is also registered)
- [ ] #2 route-alias.sh get_roster + restrict-agent-spawn.sh name-guard detect the roster from the CURRENT session/checkout only (filter .members[] by session_id or cwd == $CLAUDE_PROJECT_DIR), not the raw shared config
- [ ] #3 Detection does not rely on any 'active' flag; cwd/session match is the ownership/liveness signal
- [ ] #4 Locate + document whether a per-session dynamic team directory exists (King: TeamCreate + SendMessage-to-self); if so, use it as the authoritative live-member source
- [ ] #5 No regression: the generic-'team' collision guard (enforce-team-name.sh) and the cost/role rules still hold; add a hook test fixture for the cross-clone case
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
# WIRING MAPPED (2026-07-02, from existing on-disk state — nothing created)

`${CLAUDE_CONFIG_DIR}/teams/` holds TWO kinds of dir:
- `teams/session-<sessionId>/` = AUTHORITATIVE per-session team ("the dynamic team directory"): `config.json` (`.name`='session-<id>', `.leadSessionId`, `.members[]` each with `.cwd`) + `inboxes/<member>.json` (message routing).
- `teams/<name>/config.json` = NAMED registry — a COPY of the owning session's config. VERIFIED: `teams/statbus/config.json` is byte-identical to `teams/session-2c632915/config.json`. Last-writer-wins on TeamCreate → cross-session/clone clobber.

Observed:
- `teams/statbus` → bound to session-2c632915 = ../statbus (`cwd=/Users/jhf/ssb/statbus`), 6 members + inboxes (live).
- Other checkouts each have their OWN session dir: frogs (session-b13f72d0 = full team, session-75d4a6b9), lodgebook (session-a00d0c8d), and a PRIOR statbus_speed session (session-e0719eba, `cwd=/Users/jhf/ssb/statbus_speed`, team-lead only).
- THIS session (95a9145e) has NO `teams/session-95a9145e/` → no team → hooks reading `teams/statbus/` falsely adopt ../statbus's roster.

# FIX (confirmed, minimal)
In `route-alias.sh` `get_roster()` and `restrict-agent-spawn.sh` rule-3 name-guard, filter `.members[]` by `cwd == $CLAUDE_PROJECT_DIR` (hooks receive CLAUDE_PROJECT_DIR). ../statbus members drop out when run from statbus_speed → empty roster → no false block; typo-validation naturally re-engages once THIS checkout has its own members. `cwd` IS the ownership signal (the absent/"useless" active flag is not needed). Stronger variant: resolve `teams/session-<payload.session_id>/` directly as the live roster+inboxes source.

Backup of ../statbus's named config saved to the session scratchpad before any experiment.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 19:02
---
FIELD EVIDENCE from the statbus team session (2026-07-02 ~19:01): restrict-agent-spawn.sh's caller-ID option (b) DOES NOT AUTHENTICATE in practice. Sequence: tester ran `./dev.sh test 117_power_group_fundamentals` → blocked ('test command from unidentified caller'); foreman sent the tester a SendMessage containing the exact `run: ./dev.sh test 117_power_group_fundamentals 2>&1 | head -50` line per the hook's own suggestion → tester retried → STILL blocked. Tester's read of the mechanism: the hook counts "agentName":"tester" occurrences in the transcript, and SendMessage-delivered authorizations don't materialize there in a form the hook recognizes. WORKAROUND USED (the hook's option a, board-truthful): added 'tester' as co-assignee on the In Progress task whose tests he runs (STATBUS-124) → unblocked expected. FIX CANDIDATE for this task's owner: make option (b) actually check the tester's INBOX/delivered messages (or drop option b from the deny text so it stops advertising a path that fails); the option-a path works but requires a board write for every ad-hoc test delegation.
---

author: foreman
created: 2026-07-02 19:05
---
CORRECTION + TRUE ROOT CAUSE (supersedes comment #1's mechanism blame; foreman first-hand, 2026-07-02 ~19:05): the caller-ID failures were NOT the transcript-grep mechanism — `~/.claude-veridit/teams/statbus` was a BROKEN SYMLINK → session-2c632915 (created Jun 18; that session's team dir was deleted when the previous team was shut down). The hook's TEAM_CONFIG therefore read as EMPTY → leadSessionId empty + roster loop iterates zero members → EVERY caller 'unidentified' for gated commands (tester AND foreman alike); both advertised remedies were unreachable because identification never ran, not because they're mis-coded (untested either way — note: I found no code implementing the 'assign a Backlog task' remedy, only deny-text advertising it; verify when fixing). REPAIR APPLIED (state, not settings): repointed the symlink to the live team dir (session-12238063); hook now resolves leadSessionId + the 6-member roster; tester unblocked. DESIGN IMPLICATIONS for this task: (1) the named-team alias must not dangle when a session's team dir is deleted — either TeamDelete should clean/repoint the alias, or the hook should fall back to a cwd-filtered scan of session-*/config.json (this task's planned fix) instead of hard-trusting one symlink; (2) the hook should distinguish 'config missing/unreadable' (fail with a CONFIG error naming the path) from 'caller not in roster' — today both print 'unidentified caller', which cost three misdirected repair attempts; (3) the deny-text remedies should be code-backed or removed.
---
<!-- COMMENTS:END -->
