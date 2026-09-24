---
id: STATBUS-393
title: The installer reports every service condition and collects every service log
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:35'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The installer finishes by confirming every service is running and prints the address to open. When a service needs attention, the installer names it in plain words, states its current condition, and writes logs from every service into the support file.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

Finland had a restarting API service while the installer progressed. The support bundle gathered the database log only, leaving the API authentication failure outside the bundle.

## Proving scenario

The partial-service and API-restart-loop scenarios assert a final status for the database, web entry point, API, application, worker, and automatic update service. The support file contains logs for every service and the terminal prints its path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful installation confirms every service is running and prints the web address.
- [ ] #2 A service needing attention is named in plain words with its current condition.
- [ ] #3 The support file contains logs from the database, web entry point, API, application, worker, and automatic update service.
<!-- AC:END -->

## Review correction 2026-09-24

Current support output and enumeration are anchored at `cli/cmd/support.go:52`, `cli/internal/compose/compose.go:273`, and database-only install checking at `cli/cmd/install.go:1058-1078`; attach each Finland transcript observation to its exact line. Add **new** `test/install-recovery/scenarios/5-install-partial-services.sh` and `test/install-recovery/scenarios/5-install-api-restart-loop.sh`. They explicitly cover stopped, absent, and restarting states and inspect status plus logs for all six: database, web entry point, API, application, worker, and automatic update service.
