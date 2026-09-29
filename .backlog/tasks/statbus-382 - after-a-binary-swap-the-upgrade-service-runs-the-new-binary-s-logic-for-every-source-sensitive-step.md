---
id: STATBUS-382
title: Every source-sensitive upgrade step runs under the installed target program
status: In Progress
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-09-29 08:04'
labels:
  - owner-decision
  - upgrade
  - recovery
  - cli
dependencies:
  - STATBUS-395
priority: high
type: bug
ordinal: 24
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Before any source-sensitive upgrade step, the supervised service proves that its running program matches the installed program and worktree. A stale or deleted running program hands over or produces one bounded, recorded outcome. After the durable swap, STATBUS-395 owns prompt continuation under the target program.

## Evidence, 2026-09-24

The merged service gate and stale-program safeguard are anchored at `ops/statbus-upgrade.service:56` and `cli/internal/upgrade/service.go:294` at master `7a9cf707e`. Existing carrier-invariant coverage is at `cli/internal/upgrade/backup_path_carriers_test.go:185-207` at master `7a9cf707e`. Earlier Norway attempt counts, row identity, hashes, profile failure, and the 30.17-second figure remain unverified and are not operative facts.
<!-- SECTION:DESCRIPTION:END -->

## Status 2026-09-24

**In Progress, owner decision:** `8fcc7d8e4` adds `cli/internal/upgrade/service.go`, `statbus382_test.go`, and the actor-guarded upgrade transition migration; #4 existing backup/phase invariant remains. #1 exact installed-program identity test and #2-3 stale-program VM handoff are absent; #5 depends on unimplemented STATBUS-395. **Remaining:** decide the durable handoff mechanism, bind every source-sensitive step to the installed target program, and prove bounded stale/deleted-program outcomes and fresh continuation on VMs.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/internal/upgrade/program_identity_test.go::TestSourceSensitiveDispatchRequiresInstalledProgram` proves matching installed program and worktree execute the step while stale and deleted identities do not.
- [ ] #2 `new: test/install-recovery/scenarios/7-stale-program-register-schedule-service.sh` starts a stale supervised program, installs the fix candidate, then uses the real register, schedule, and service path and observes the source-sensitive step execute under the target version.
- [ ] #3 `new: test/install-recovery/scenarios/7-stale-program-register-schedule-service.sh` observes any failed handoff exactly once as a bounded recorded outcome with causal program/tree provenance rather than automatic reclaim.
- [x] #4 `cli/internal/upgrade/backup_path_carriers_test.go::TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` remains green across the handoff changes.
- [ ] #5 `new: test/install-recovery/scenarios/7-new-program-handoff.sh` supplies the STATBUS-395 continuation proof after the durable swap.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3 ships actor-guarded upgrade transitions (8fcc7d8e4, migration *_382_actor_guarded_upgrade_transitions). Only AC4 (existing invariant) is proven, green in Go Test 36503468493. AC1-3 and AC5 have no test or scenario yet. AC5 waits for STATBUS-395.
<!-- SECTION:NOTES:END -->
