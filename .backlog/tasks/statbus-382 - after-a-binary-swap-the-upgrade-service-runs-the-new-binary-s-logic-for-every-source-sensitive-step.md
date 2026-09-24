---
id: STATBUS-382
title: Every source-sensitive upgrade step runs under the installed target program
status: To Do
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-09-24 18:45'
labels:
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

Before any source-sensitive upgrade step, the supervised service proves that its running program matches the installed program and worktree. A stale or deleted running program hands over or produces one bounded, recorded outcome. After the durable swap, STATBUS-395 owns prompt continuation under the target program.

## Evidence, 2026-09-24

The merged service gate and stale-program safeguard are anchored at `ops/statbus-upgrade.service:56` and `cli/internal/upgrade/service.go:294` at master `7a9cf707e`. Existing carrier-invariant coverage is at `cli/internal/upgrade/backup_path_carriers_test.go:185-207` at master `7a9cf707e`. Earlier Norway attempt counts, row identity, hashes, profile failure, and the 30.17-second figure remain unverified and are not operative facts.

## Acceptance Criteria

- [ ] #1 `new: cli/internal/upgrade/program_identity_test.go::TestSourceSensitiveDispatchRequiresInstalledProgram` proves matching installed program and worktree execute the step while stale and deleted identities do not.
- [ ] #2 `new: test/install-recovery/scenarios/7-stale-program-register-schedule-service.sh` starts a stale supervised program, installs the fix candidate, then uses the real register, schedule, and service path and observes the source-sensitive step execute under the target version.
- [ ] #3 `new: test/install-recovery/scenarios/7-stale-program-register-schedule-service.sh` observes any failed handoff exactly once as a bounded recorded outcome with causal program/tree provenance rather than automatic reclaim.
- [ ] #4 `cli/internal/upgrade/backup_path_carriers_test.go::TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` remains green across the handoff changes.
- [ ] #5 `new: test/install-recovery/scenarios/7-new-program-handoff.sh` supplies the STATBUS-395 continuation proof after the durable swap.
