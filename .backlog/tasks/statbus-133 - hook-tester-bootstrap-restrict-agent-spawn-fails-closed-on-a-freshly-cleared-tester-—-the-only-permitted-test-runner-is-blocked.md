---
id: STATBUS-133
title: >-
  hook-tester-bootstrap: restrict-agent-spawn fails closed on a freshly cleared
  tester — the only permitted test runner is blocked
status: To Do
assignee: []
created_date: '2026-07-04 12:15'
labels:
  - team-hooks
  - tooling
  - operator-ux
dependencies: []
references:
  - .claude/hooks/restrict-agent-spawn.sh
  - .claude/hooks/require-bash-background.sh
  - .claude/hooks/test-restrict-agent-spawn.sh
priority: medium
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-07-04 during the STATBUS-131 verification run, first ./dev.sh test invocation after the King cleared all five teammates.

THE GAP: .claude/hooks/restrict-agent-spawn.sh resolves caller identity by counting exact `"agentName":"<roster-member>"` occurrences in the session's own transcript .jsonl (roster-match, no first-agentName fallback — STATBUS-118). A freshly cleared/re-onboarded tester session has a near-empty transcript with zero (or too few) occurrences of its own roster name → caller resolves to "" → rule 4 (`./dev.sh test` = tester-only) FAILS CLOSED with "test command from unidentified caller". Net effect: right after every /clear, the ONE agent permitted to run tests is the one agent the hook cannot identify.

NOT a misdesign of rule 4 itself — fail-closed on the test serializer is correct (concurrent runs corrupt shared DB templates), and the foreman must NOT run the sweep on the tester's behalf (permission laundering; defeats the single-serializer rule). The gap is purely the post-/clear bootstrap window.

INTERIM (works today): tester retries after its transcript accrues occurrences of its own agentName (inbox messages + its own turns); foreman instruction sent 2026-07-04.

FIX CANDIDATES for the King + hook owner to weigh (hook edits need the King's nod):
(a) positive self-identification file — each teammate writes tmp/agents/<name>.session containing its session_id at onboard; hook matches session_id → name (deterministic, no transcript heuristics, cold-agent-test clean);
(b) count the FIRST occurrence as sufficient for rule 4 only when exactly one roster member matches (still can never mis-grant a wrong member);
(c) accept a bounded grace: unidentified caller + no other test run in flight (lockfile) → allow with loud note. (c) weakens the serializer guarantee — least preferred.

Related, same morning-review family: require-bash-background.sh false-positives on instant detached nohup launches (from the overnight VM campaign).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A freshly cleared tester can run ./dev.sh test on its first attempt after onboarding (no transcript-accrual wait)
- [ ] #2 Rule 4 still denies every non-tester caller, including the foreman (test-restrict-agent-spawn.sh case added)
- [ ] #3 Chosen mechanism approved by the King before the hook is edited
<!-- AC:END -->
