---
id: STATBUS-168
title: >-
  hook-identity-rotation: the team identity hook dies silently across session
  rotation — stale team.name + stale leadSessionId disabled every role guard
status: To Do
assignee: []
created_date: '2026-07-12 22:14'
updated_date: '2026-07-13 09:09'
labels:
  - tooling
  - team
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 169000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the role guards (operator/tester cannot commit or push; only the foreman cuts releases) hold on EVERY session, including post-restart/compaction continuations — and when identity is unknowable, the hook behaves per its own documented intent instead of silently disarming.
> FOUND: 2026-07-13 ~00:10, night shift — the foreman's authorized RC cut was denied as "unidentified caller"; investigation showed the guards had been silently OFF for everyone all along.
> COMPLEXITY: architect ruling + small hook change; the King should bless the final shape (it is permission machinery).

WHAT BROKE, three stacked stale facts (.claude/hooks/restrict-agent-spawn.sh):
1. `.claude/team.name` (the hook's per-checkout team pointer) was git-tracked with value "statbus" — but the harness moved to SESSION-SCOPED teams (`teams/session-<id>/`); `teams/statbus/` no longer exists. The hook resolved a nonexistent config → `lead_session_id=""` → every caller unidentified → ALL identity rules silently disabled (operator/tester commit blocks included). A guard that dies silently is worse than no guard — nothing failed loudly.
2. Even pointed at the live config, `leadSessionId` records the foreman session that CREATED the team; session ids rotate on restart/clear/continuation, so a legitimate continuation-foreman never matches. This is the same class STATBUS-118 fixed for spawns and the retired test-identity rule ("broke on every clear/crash/compaction").
3. The transcript-grep fallback identifies teammates by `agentName` — which never appears in the LEAD's own transcript (verified: zero roster-name matches in the live foreman transcript). So the lead has NO working fallback identification.

NIGHT-SHIFT REPAIRS (data fixes only, rule untouched; commit 701477b3a):
- `.claude/team.name` untracked + gitignored (per-checkout state by its own design), local copy now names the live session-team.
- The live team config's `leadSessionId` corrected to the current foreman session.
Both re-armed the hook; the authorized RC cut then passed identification legitimately.

DURABLE FIX for the architect to rule (the repairs are one-time; recurrence must fail loudly, never be quietly repaired — no-standing-self-heal):
- How the hook should identify the lead across rotation (e.g. the harness updates leadSessionId on continuation; or identify the lead as "the session that is not any roster member's" — careful, that grants by exclusion; or read the team dir freshest-inbox ownership).
- Whether `release prerelease`'s deny-on-unknown should stand given the file header's own documented principle is "unidentifiable → permissive fallback (never hard-break legitimate work)" — the two contradict; pick one and write it down.
- A loud self-check: if the resolved team config does not exist, the hook must SAY so on every gated call, not silently disable all rules.
- Map the vocabulary drift: the roster name is "team-lead" but the rules test for "foreman" — the header notes the equivalence, the code does not implement it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the lead-identification mechanism across session rotation and the deny-vs-permissive contradiction for release commands; King blesses the shape (permission machinery)
- [ ] #2 The hook fails LOUDLY when its resolved team config does not exist — silent disarm is impossible
- [ ] #3 The ruled fix is implemented with the hook's test file extended to cover: continuation-foreman identification, missing-config loudness, and team-lead↔foreman vocabulary
- [ ] #4 The night-shift data repairs (701477b3a + config leadSessionId) are superseded by the mechanism — nothing depends on hand-maintained session ids
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 09:09
---
CARRY-OVER from STATBUS-122 (merged here on the 2026-07-13 triage): the cross-clone concurrent-team scenario — two checkouts on one machine, each with its own live team — becomes an explicit TEST FIXTURE for the ruled identity mechanism (AC#3's test file gains it). 122's original collision mechanism (shared global team name) died with the harness's move to session-scoped teams; what survived is exactly this ticket's scope.
---
<!-- COMMENTS:END -->
