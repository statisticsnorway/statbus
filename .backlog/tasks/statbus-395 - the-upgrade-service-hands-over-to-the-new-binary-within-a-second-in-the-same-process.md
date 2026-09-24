---
id: STATBUS-395
title: A planned upgrade resumes promptly under the new program
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 18:42'
labels:
  - upgrade
  - recovery
  - cli
dependencies:
  - STATBUS-382
priority: high
type: task
ordinal: 85
---

## Description

After the durable program-swap phase, a planned upgrade resumes under the new program without waiting for a service-restart delay. The reliable acceptance bound is five seconds from the completed swap stamp to the first new-program continuation record.

## Evidence, 2026-09-24

The service currently has a 30-second restart delay (`ops/statbus-upgrade.service:56` at master `7a9cf707e`). The upgrade service swaps `./sb`, exits 42 for a fresh process, and distinguishes the expected post-swap continuation using `PhaseNewSbSwapped` (`cli/internal/upgrade/service.go:293-321` at master `7a9cf707e`). The excluded `tmp/handoff-and-banner.md` and its 30.17-second assertion are not evidentiary support.

## Acceptance Criteria

- [ ] #1 `new: test/install-recovery/scenarios/7-upgrade-new-program-handoff.sh` records the completed swap and first continuation under the target version no more than five seconds apart.
- [ ] #2 `new: cli/internal/upgrade/handoff_test.go::TestNewProgramHandoffPreservesUpgradeOwnership` observes one continuation and no competing service execution during a planned handoff.
- [ ] #3 `new: test/install-recovery/scenarios/7-upgrade-handoff-crash-control.sh` kills the continuation process and observes the configured restart delay and bounded recovery behavior rather than the planned fast path.
