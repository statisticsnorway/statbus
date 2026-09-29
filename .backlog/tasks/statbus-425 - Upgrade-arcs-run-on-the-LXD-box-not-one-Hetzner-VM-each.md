---
id: STATBUS-425
title: >-
  All release gating on the LXD box: smoke builds the checkpoints; faults and
  upgrade arcs fork from them
status: In Progress
assignee: []
created_date: '2026-09-28 13:07'
updated_date: '2026-09-29 08:04'
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

Plan review 2026-09-28 (Fable 5.1, one pass; Astra stopped on the OpenAI limit): SOUND WITH CHANGES, tmp/review-lxd-all-gates-plan.md. Revised milestones adopted: M2' smoke on LXD with provenance keys (user.statbus.candidate/producer/run_id), checkpoint-pending→checkpoint rename as smoke's last act, rerun-safe replace, per-job active marker vs reaper, single ramp job; M3a arc-aware LXD backend (tag-less install_statbus_at_sha, statbus-arc-* mapping, executable ssh/scp shim for 'timeout ssh', ProxyJump for deploy-status-proof, bounded volume for un-park-to-completion, GITHUB_TOKEN, ControlMaster), verified by hand on 4 hardest arcs incl. c-rollback reproducing rc.16's red; M3b arc workflow shadow run beside Hetzner; M4 orchestrator (construct at start, smoke always dispatched, box slot semaphore) + gates + delete Hetzner steps; M5 parity (every Hetzner red is an LXD red for the same reason). Estimate ~77 min on ccx33 sequential faults→arcs; ~40 min on a bigger box (423).

2026-09-29 05:42: M1 + M2' + M3a merged to master (a83039410) after 4 Opus 5.5 review rounds (tmp/review-lxd-m2*.md; round 4 APPROVE + R4-1/R4-2 landed 0aaafeb52). Live evidence: both smoke legs green on the box against rc.16; fault fleet on the branch backend 24/24 against rc.17 (matching master's rc.17 LXD run 36506437069); harden-host completed live. From the next RC, smoke (rungs 4/5) and the fault fleet (rung 7) run on LXD; upgrade arcs (rung 8) stay on Hetzner until M3b (shadow run beside Hetzner) and M4 (orchestrator + gates + delete Hetzner steps). Low follow-ups: harden-host refusal wording conflates SSH-probe failure with activity; PATH ssh shim intercepts local git-over-SSH when an operator runs run-forks.sh; H2 residue (upgrade-leg rerun after a failed -pre build refuses); M6 checkpoint name length at vX.Y.10.

Audit after v2026.09.3 (2026-09-29): Not in v2026.09.3. M1/M2'/M3a merged to master afterwards (a83039410). Harness Selftest red on master since (lxd-smoke-checkpoint-test, run 36534648749). Fix before the next candidate.
<!-- SECTION:NOTES:END -->
