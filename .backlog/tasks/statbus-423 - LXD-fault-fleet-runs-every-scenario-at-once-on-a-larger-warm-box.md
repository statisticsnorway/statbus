---
id: STATBUS-423
title: LXD fault fleet runs every scenario at once on a larger warm box
status: To Do
assignee: []
created_date: '2026-09-28 08:18'
labels:
  - ci
  - lxd
dependencies: []
priority: medium
ordinal: 372200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Purpose: cut the LXD release fault gate from ~34 min to ~12 min so candidates move faster.

Measured (rc.12, run 36388841250): 25 scenarios = 6,957 s of work, longest single scenario 419 s (5-install-orphaned-db-volume-credentials); forks ran 6 at a time (run-forks.sh LXD_PARALLEL default 6, max 8) for 29 min; base checkpoints built serially in 4.3 min. Each fork is capped at 2 vCPU / 6 GiB (lxd-backend.sh); the ccx33 box has 8 vCPU / 32 GB / 60 GiB Btrfs pool, so 6 forks already oversubscribe CPU ~1.5x.

Proposal: (1) a larger server type for statbus-lxd-fleet (e.g. CCX53, 32 vCPU / 128 GB) with a larger Btrfs pool and LXD_PARALLEL = number of scenarios, so the fork phase approaches the longest scenario; (2) build independent checkpoint bases in parallel with per-base locks; (3) schedule longest-first from the previous run's comparison.tsv. The box is reaped after 3 h idle, so the larger type costs little.

Risk: timing-sensitive scenarios (startup timeout, concurrent install) can false-fail under CPU starvation, so do not raise concurrency on the current box type.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A full LXD fleet run on the new box type completes with verdicts identical to the preceding candidate's run, scenario by scenario, recorded with run ids
- [ ] #2 Dispatch-to-verdict wall time measured and recorded, target under 15 minutes including cold ramp
- [ ] #3 up.sh image/type drift handling recreates the box on the new type by mechanism, not by hand
<!-- AC:END -->
