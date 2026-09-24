---
id: STATBUS-384
title: Running the installer again brings up every service the chosen mode needs
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies:
  - STATBUS-408
  - STATBUS-411
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `474cf6119`, `145c17292`: `cli/cmd/install_services.go` and `cli/cmd/install_services_test.go` check the selected service set (#1 behavior); the exact named `TestCheckServicesDoneRequiresAllSelectedServices` is not present. #2 is authored in `5-install-proxy-never-started.sh` but real-VM proof is pending; #3 remains not met. **Remaining:** run the proxy-loss VM recovery proof and add/run the interrupted-first-install resume scenario to ready API and web.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Services step brings up and verifies the database, web entry point, API, application, and worker required by the selected mode. A rerun repairs a partial first run and resumes only after the installer identifies an interrupted first installation by the exact markers owned by STATBUS-408 and STATBUS-411.

## Evidence, 2026-09-24

The current completion check inspects only database health (`cli/cmd/install.go:1058-1078` at master `7a9cf707e`), although the step runner can continue to later work (`cli/cmd/install.go:711-741` at master `7a9cf707e`). On the local replay, the web entry point remained `Created`, the rerun reported Services OK from database health alone, and the database route was still unavailable (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:240-284,697-718,720-783`). The Finland transcript records the original port-80 start failure, the database-only Services OK rerun, and the later route refusal (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-76,121-137`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_services_test.go::TestCheckServicesDoneRequiresAllSelectedServices` proves Services is complete only when the database, web entry point, API, application, and worker are running and the database is healthy.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-proxy-never-started.sh` removes the web entry point, application, and worker from a green install, reruns the one install command, and observes all required services restored before migrations and final readiness.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-interrupted-first-run.sh` stops between service startup and database setup, then observes the exact STATBUS-408/411 classification and a resume from the first incomplete persisted step to a ready web entry point and API.
<!-- AC:END -->
