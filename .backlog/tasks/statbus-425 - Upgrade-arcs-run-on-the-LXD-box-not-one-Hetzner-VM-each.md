---
id: STATBUS-425
title: >-
  All release gating runs on the LXD box: smoke builds the checkpoints, faults
  and upgrade arcs fork from them
status: In Progress
assignee: []
created_date: '2026-09-28 13:07'
updated_date: '2026-10-15 19:49'
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
### North Star
Every release gate runs its scenarios on the shared LXD box, so a full release check takes about an hour instead of most of a day, without losing what the per-VM runs used to catch.

### Zoom out
Release gating used to rent one Hetzner VM per scenario. Upgrade arcs alone took about 3.5 hours (35 arcs, about 11 minutes each, two at a time under the project's core quota). The fix is the pattern STATBUS-417 used for fault scenarios:
- **Install once:** smoke installs the candidate on the LXD box and leaves a checkpoint.
- **Fork many:** ordinary arcs fork that checkpoint, six or more at a time; the two historical-base arcs get their own pinned install.
- **Bound on the host:** capacity is admitted by slots on the box (`ops/lxd-fleet/admission.sh`), not by a workflow lock.

Moving the arcs is only safe if LXD sees what Hetzner saw. So the move was gated on a parity run, with every disagreement explained rather than averaged away. The LXD box itself is a Hetzner machine; "no Hetzner VM" means no per-scenario test VM.

### Zoom in
- **Before, 2026-09:** Hetzner arc runs took 3.5 hours (green run `35975471099`, 08:28-12:07) and 1.5 hours (rc.14 run `36414310454`).
- **Parity (M3b, 2026-09-29):** a full LXD run at v2026.09.3-rc.17 compared with Hetzner run `36509925405`. Result: 33 of 35 verdicts match. Durable evidence on master: `test/install-recovery/lxd/evidence/v2026.09.3-rc.17/final-comparison.tsv` with its README (integrated in `c339f406e`). The two mismatches, `rollback-pair-terminal` and `restore-broke-reattempt`, were a product behaviour that LXD exposed: tag discovery worked on LXD, so an installed release superseded a newer failed row (proven by a ledger dump; the Hetzner side is inferred). That behaviour is STATBUS-435. Three other early reds were harness timing or infrastructure, fixed on the branch as `7edb2f275` and `83b3b3b84` (reaching master in the integration commit `c339f406e`) and by retest.
- **Shipped (M1 to M4):** `a83039410` (M1, M2', M3a) and the integration merge `508dbc163` (2026-09-30). `upgrade-arc-harness.yaml` runs arcs on LXD forks via `install_statbus_at_sha` and creates no VM (`hcloud server create` appears nowhere under `.github/workflows`). `release-fleet-orchestrator.yaml` dispatches the arcs as stage 3/4 beside the LXD fault fleet, and the stable gate needs both green. LXD guests are `ubuntu:26.04` (`ops/lxd-fleet/base.sh`).
- **Observed (v2026.10.0, `bce5bf39b`):** Upgrade Arc Harness `37578475601` SUCCESS, 42 jobs, 59 min 41 s, including the two arcs that disagreed in M3b. Test Smoke `37577261099` SUCCESS with both LXD legs.
- **Leftover:** the workflow concurrency group is still named `hetzner-vm-fleet`, documented in the workflow as historical.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the evidence README records the parity method.
- **Cleanup:** branches `ci/lxd-m4` and `ci/lxd-arcs` were reviewed and deleted 2026-10-13 (`c81f82fad`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every arcs/*-arc.sh runs on the LXD box from one CI job with bounded parallelism (Upgrade Arc Harness `37578475601`)
- [x] #2 LXD verdicts match the Hetzner arc run at the same candidate, with each disagreement explained (33/35 at v2026.09.3-rc.17 vs `36509925405`; both mismatches traced to the STATBUS-435 product behaviour; `test/install-recovery/lxd/evidence/v2026.09.3-rc.17/`)
- [x] #3 The orchestrator's stage 3/4 and the stable gate use the LXD arc run; no per-arc Hetzner VM is created (`release-fleet-orchestrator.yaml`, `upgrade-arc-harness.yaml`)
- [x] #4 The full arc suite finishes in under 60 minutes (59 min 41 s, `37578475601`)
- [x] #5 Smoke 0-happy-install and 0-happy-upgrade run on the LXD box and leave the checkpoints faults and arcs fork from (Test Smoke `37577261099`)
- [x] #6 LXD guests are ubuntu:26.04 (`ops/lxd-fleet/base.sh`)
- [x] #7 No release gate boots a per-scenario test VM; the shared LXD box is itself a Hetzner machine by design
- [ ] #8 Owner decision: accept 33/35 parity with both mismatches attributed to STATBUS-435 as the parity proof (AC2), and "no per-scenario test VM" as the meaning of AC7? Yes closes this ticket.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1, AC3-6:** checked 2026-10-13 against runs `37578475601` and `37577261099` at `bce5bf39b` (v2026.10.0).
- **AC2:** the comparison is durable on master since `c339f406e`; the 2026-10-13 note that it was "not recorded anywhere durable" missed it. Rechecked 2026-10-15: both mismatching arcs succeed in `37578475601`.
- **AC7:** `rg 'hcloud server create' .github/workflows` finds nothing; the only Hetzner API use is `ops/lxd-fleet/up.sh` ramping the fleet host.
- **History:** milestone notes from 2026-09-29 to 2026-10-13 (M1 to M4 reviews, the integration merge, the 10-13 status correction) are in Git history of this file, last full version at `c81f82fad`.
<!-- SECTION:NOTES:END -->
