---
id: STATBUS-425
title: >-
  All release gating on the LXD box: smoke builds the checkpoints; faults and
  upgrade arcs fork from them
status: To Do
assignee: []
created_date: '2026-09-28 13:07'
updated_date: '2026-09-28 19:04'
labels:
  - ci
  - lxd
  - release
dependencies: []
priority: high
ordinal: 374200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 4/4 upgrade-arc stage boots one Hetzner CX23 per arc, max-parallel 2 (project core quota): 35 arcs x ~11 min = ~3.5 h (green run 35975471099: 08:28-12:07; rc.14 run 36414310454: 11:13-12:50). STATBUS-417 moved only the fault fleet to LXD. Move the arcs onto the LXD box the same way: ordinary arcs fork the candidate's installed checkpoint (A = candidate), 6+ at once; special bases (schema-floor d53731ec5, pre-rename 730b5001c) get their own install. Parity per owner ruling for 417: LXD arc verdicts match the Hetzner arc verdicts at the same commit. Gate: ./sb release stable requires the LXD arc run green at the RC commit; the Hetzner run-arc matrix is retired.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every arcs/*-arc.sh runs on the LXD box from one CI job with bounded parallelism
- [ ] #2 Verdicts match the Hetzner arc run at the same candidate commit
- [ ] #3 Orchestrator 4/4 and the stable gate use the LXD arc run; the Hetzner run-arc matrix is deleted
- [ ] #4 Full arc suite wall time under 60 min
- [ ] #5 Smoke 0-happy-install and 0-happy-upgrade run on the LXD box and leave the checkpoints the fault checks and arcs fork from
- [ ] #6 LXD guests are ubuntu:26.04
- [ ] #7 No release gate boots a Hetzner VM
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner direction 2026-09-28 18:56: move smoke AND the upgrade arcs to LXD; smoke creates the checkpoint images the fault checks and the arcs fork from. Design and measurements: tmp/lxd-all-gates.md. Guests move to ubuntu:26.04 (VM harness default). The 40 GB real-disk install leaves with smoke (owner's 07:21 ruling named this revisit condition); remaining coverage is Go tests. Parity: LXD verdicts match Hetzner at the same candidate (rc.16 arcs run 36468921894).
<!-- SECTION:NOTES:END -->
