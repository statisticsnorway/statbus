---
id: STATBUS-170
title: >-
  deploy-green-means-converged: the deploy workflow reports green at schedule
  time — the async upgrade can roll back afterward unseen
status: To Do
assignee: []
created_date: '2026-07-13 01:35'
labels:
  - deploy
  - ci
  - upgrade
  - fail-fast
dependencies: []
priority: medium
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a green deploy run means the box CONVERGED (row completed, services healthy on the target) — not merely that a poke was delivered. Every other meaning of green is a false signal an operator will eventually trust to their cost.
> FOUND: 2026-07-13 night, dev rc.02 attempt — apply-latest exited green at 01:22:19 (row scheduled); the daemon claimed and ran the upgrade asynchronously and ROLLED IT BACK at 01:23:16 (BINARY_REPLACE_FAILED); the workflow stayed green. Two other same-night shapes (Norway's UPDATE-0 and swallowed-constraint pokes) were fixed by STATBUS-169, but this one is structural: even a perfectly honest scheduler leaves green meaning "scheduled".
> COMPLEXITY: small workflow change + architect design ruling (what green promises, how long to poll, what terminal states map to red).

THE GAP: deploy-to-<slot>.yaml's deploy job ends when the ssh poke exits. The upgrade itself runs in the box's daemon, seconds-to-minutes later. A post-poke rollback (like tonight's) is invisible to CI — the operator sees green and believes the fleet moved.

SHAPE (architect to rule): after the poke, the workflow polls the box's upgrade row (read-only ssh, the row is commit-addressed) until a terminal state or a bounded timeout: completed → green; rolled_back/failed/parked → RED with the row's error text surfaced in the workflow log; timeout → red naming the last observed state. Design points: poll budget vs GitHub Actions billing; whether the edge slots (fast) and release slots (slower) need different budgets; the read command must be sshdo-compatible on niue slots.

RELATION: completes the STATBUS-169 arc (green implies scheduled) up the stack (green implies converged). The night's oracle discipline caught all three shapes by reading boxes directly — this ticket makes the workflow do that reading itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the polling shape (budget, per-channel differences, sshdo compatibility) — what green PROMISES is written down
- [ ] #2 The deploy workflows poll to a terminal outcome: completed → green; rolled_back/failed/parked → red with the row's error text in the workflow log; timeout → red naming the last state
- [ ] #3 Proven by a run: a deliberately failing upgrade turns the deploy run RED with the failure named (the run is the oracle)
<!-- AC:END -->
