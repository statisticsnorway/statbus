---
id: STATBUS-384
title: Running the installer again brings up every service the chosen mode needs
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
The Services step brings up every service required by the selected installation and confirms each service is running on every run. A rerun repairs a partial first run by starting the missing web entry point, API, application, and worker before later steps continue. A first installation interrupted after service startup is still recognized as an incomplete first installation and resumes from the next incomplete step.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

Finland session 1 left only the database running after port 80 was occupied. Session 2 then reported Services OK because the check observed only the healthy database, and later work failed through the missing database route. Code review also found that a fresh database created before seed and migrations has no upgrade table, so the current state detector can classify an interrupted first install as a legacy installation and refuse the rerun.

The local Multipass replay reproduced the service gap exactly. A port-80 bind failure left the web entry point in `Created`, which is not a running state. On rerun, step 8 reported Services OK because it checked only database health, so the web entry point was never started and its database route remained unavailable. Source: `/Users/jhf/ssb/statbus/tmp/local-ville-replay.md`, lines 240-284, 697-718, and 720-783.

## Proving scenarios

New harness scenario `5-install-proxy-never-started`: install to green, remove the web entry point, application, and worker, then run the one install command. The Services step reports RUNNING, restores all five services, and steps 13 and 17 succeed.

New interruption scenario: stop installation between steps 8 and 12, then run the one install command. The rerun recognizes the incomplete first installation, resumes at the first incomplete step, and reaches green. Unit coverage includes database only, database plus web entry point, all services, an API restart loop, and the pre-migration fresh-database state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Services step reports OK only when the database, web entry point, API, application, and worker are running and the database is healthy.
- [ ] #2 A rerun starts every missing or stopped service required by the selected installation.
- [ ] #3 The `5-install-proxy-never-started` scenario finishes with all five services running and the automatic update service active.
- [ ] #4 A rerun after interruption between service startup and database setup continues from the first incomplete step.
<!-- AC:END -->

## Review correction 2026-09-24

Current `checkServicesDone` checks only the database (`cli/cmd/install.go:1058-1078`); the step runner is at `cli/cmd/install.go:711,741`. The local replay shows the web entry point left `Created`, a database-only Services OK rerun, and an unavailable database route (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:240-284,697-718,720-783`). Add the **new** `test/install-recovery/scenarios/5-install-proxy-never-started.sh`. Its implementable recovery rule, shared with STATBUS-408/411, resumes from the first incomplete persisted step only after classifying an interrupted first install by exact markers. Operator text says web entry point/API, not proxy/container.
