---
id: STATBUS-405
title: The automatic update self-check reports a starting service as healthy progress
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:44'
labels:
  - upgrade
  - service
  - install
dependencies: []
priority: medium
type: bug
ordinal: 358000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The automatic update self-check reports activation as startup progress, reports success only after readiness, and reports a truthful alarm for an actually inactive service. Messages appear in that observable order.

## Evidence, 2026-09-24

Finland printed `The upgrade service is NOT RUNNING` while the unit was activating (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:131-169`). Current unit-floor classification is at `cli/internal/unitfloor/unitfloor.go:110-139`, and installer readiness is at `cli/cmd/install.go:2804-2823`, both at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/internal/unitfloor/unitfloor_test.go::TestActivatingIsStartupProgressUntilReady` observes progress and no alarm while activating, then success only after readiness.
- [ ] #2 `new: cli/internal/unitfloor/unitfloor_test.go::TestInactiveProducesAlarmBeforeRecoveryGuidance` observes an inactive-state alarm followed by the complete installer recovery command.
- [ ] #3 `test/install-recovery/scenarios/1-boot-startup-timeout.sh` records no alarm from activation through readiness, then success in journal order.
<!-- AC:END -->
