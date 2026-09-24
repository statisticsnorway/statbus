---
id: STATBUS-393
title: The installer reports every service condition and collects every service log
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

## Implementation note, 2026-09-24

The installer now prints a five-container inventory on service-start and final-readiness failures, and the support bundle has `ps -a` and separate recent log sections for all five containers plus the automatic update unit. This is partial: the terminal inventory does not yet include the host automatic-update unit, startup errors are available in logs but not summarized per status, and neither disposable-VM scenario has been run. All three acceptance criteria remain open.

<!-- SECTION:DESCRIPTION:BEGIN -->
The installer reports the condition of the database, web entry point, API, application, worker, and automatic update service. A failure report distinguishes running, stopped, absent, and restarting services and writes logs for all six services to the support file.

## Evidence, 2026-09-24

The Finland transcript shows the API restarting while the database remained healthy (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:144-148`). The automatic update service later remained activating while its database connection retried (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:131-154`). Current support enumeration starts in `cli/cmd/support.go:52` and compose status decoding in `cli/internal/compose/compose.go:273-280` at master `7a9cf707e`, while install completion checks only database health (`cli/cmd/install.go:1058-1078` at master `7a9cf707e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/5-install-partial-services.sh` creates stopped and absent services and asserts a terminal status for all six named services plus all six log sections in the support file.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-api-restart-loop.sh` creates a restarting API and asserts the restarting condition, its startup error, the other five statuses, and all six log sections.
- [ ] #3 `new: cli/cmd/support_test.go::TestSupportBundleIncludesEveryServiceStateAndLog` covers running, stopped, absent, and restarting states and verifies the terminal prints the support-file path.
<!-- AC:END -->
