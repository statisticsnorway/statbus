---
id: STATBUS-118
title: >-
  team-name-detection: fix cross-clone team collision + make roster detection
  session-aware
status: To Do
assignee: []
created_date: '2026-07-01 13:42'
labels:
  - team
  - hooks
  - infra
dependencies: []
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
