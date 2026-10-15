---
id: STATBUS-408
title: An interrupted first install finishes when the install command is run again
status: In Progress
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-10-15 19:16'
labels:
  - release-bug
  - install
  - recovery
  - database
dependencies: []
priority: high
type: bug
ordinal: 361000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A first install that stops part-way can be finished by running the same install command again: it picks up at the first unfinished step and keeps the database it already created.

### Zoom out
A first install creates things before it can finish: settings, credentials, the database volume. If it stops in between (a busy port, a lost connection, Ctrl-C), the box is neither empty nor installed. The worst response is a refusal that leaves the operator no path except deleting things by hand, because deleting the installation directory while the volume survives creates the password split of STATBUS-407.

So a rerun recognises its own unfinished work and continues it. Each step checks whether its result is already there, so "continue" simply means the finished steps report OK and the first unfinished one runs. Recognising the unfinished database is the classification STATBUS-411 owns; this ticket owns the operator's path from interrupted to serving.

### Zoom in
- **Incident, Hetzner reproduction and Finland, 2026-09-24:** a port-80 failure at step 8 left the database reachable without `public.upgrade`. Every rerun was refused as pre-1.0 (then `install/state.go:141-147`), so the only way forward looked like removing the installation directory, which with a surviving volume causes the 407 credential split.
- **Shipped (v2026.09.3):** `0a3f2ff80` continues a fresh install stopped after the database was created; `3c76d6323` classifies from migration provenance (STATBUS-411). The rerun prints `The database exists but setup stopped before it was finished. Continuing where it stopped.`
- **Proof, real box:** `5-install-interrupted-first-run.sh` runs a genuine first install, interrupts it at the `Services DONE` boundary, checks the database has no `public.upgrade` and no application tables, reruns, and requires that message, `Services OK`, Seed or Migrations `DONE`, `public.upgrade` present, the signer consent kept, and every service running. PASS in rc.17 LXD; scenario last touched `a425435a7` (2026-10-15, STATBUS-468 follow-on).
- **Not asserted:** that the rerun used the same database volume rather than a new one, and that data written before the interruption survived. On an init-db-only database there is no data yet to lose.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A rerun after a first install stopped at the Services boundary classifies the database as unfinished, reports OK for finished steps and runs Seed and Migrations (`5-install-interrupted-first-run.sh`, rc.17 LXD PASS)
- [x] #2 The resumed install ends with `public.upgrade` present, the release-signer consent kept and every service running (same scenario)
- [ ] #3 Owner decision: should the scenario also prove the same volume was kept, for example by volume identity or a sentinel written before the interruption? No closes this ticket. Yes adds that assertion as the open criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** rc.17 LXD PASS (2026-09-29 audit, `ea170989e`).
- **Superseded criteria:** the restyle named `state_markers_test.go` cases and `5-install-interrupted-after-database-created.sh` with a sentinel row, none written. The marker cases moved to STATBUS-411 (`TestDetectWith`); the scenario that exists is `5-install-interrupted-first-run.sh`. The 408 -> 411 dependency was removed: 411 is the classification both tickets rely on, already shipped.
<!-- SECTION:NOTES:END -->
