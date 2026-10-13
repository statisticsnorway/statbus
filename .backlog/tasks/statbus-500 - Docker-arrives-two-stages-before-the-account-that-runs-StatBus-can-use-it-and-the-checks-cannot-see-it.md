---
id: STATBUS-500
title: >-
  Docker arrives two stages before the account that runs StatBus can use it, and
  the checks cannot see it
status: Done
assignee: []
created_date: '2026-10-13 14:04'
updated_date: '2026-10-13 14:38'
labels:
  - install
  - hardening
  - docker
dependencies: []
priority: high
type: bug
ordinal: 426204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 reviewing the Uganda prepare run, Stage 5 (Core Tools & System Tuning). Docker is installed in stage_core_tools, but the account that will RUN StatBus is only added to the docker group two stages later: stage_user_setup adds a HARDCODED devops, and stage_service_account adds $user (the configured service account). Meanwhile Stage 5 checks Docker only as root - which docker, systemctl is-active docker, docker compose version - all of which are true while an ordinary user is refused at the socket. So a preparation can tick every box green and still hand over a box where the install dies with "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock", which is exactly what happened on the Uganda box. Two details from the same ordering: the hardcoded devops does nothing for an operator whose account is statbus, and even a correct usermod only takes effect in a NEW login session.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The stage that installs Docker also grants docker access to the account that will run StatBus, using the configured service account rather than a hardcoded name. Checked by test/install-recovery/tests/setup-docker-access-test.sh assertion 1 and by reading the stage.
- [x] #2 The stage verifies docker access AS that account (runuser -u <user> -- docker info), so a green tick cannot mean merely that the daemon is up. Checked by assertions 2 and 3.
- [x] #3 The grant happens before the stage declares itself verified. Checked by assertion 4.
- [x] #4 The operator is told that a new login session is required after the group change. Checked by the warning the stage prints in that branch.
- [ ] #5 The next real preparation reports "Docker usable by <user>" as a pass; to be recorded in STATBUS-497 (the Uganda rerun).
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13, fixed and evidenced by the coordinator directly (owner asked for it now rather than delegated). RED: STATBUS_SETUP_SCRIPT=<HEAD copy> bash test/install-recovery/tests/setup-docker-access-test.sh -> four FAIL lines, rc=1. GREEN: four PASS lines, rc=0; bash -n parses. Wired into .github/workflows/harness-selftest.yaml. The group check uses a case match rather than a grep in a pipeline because this file runs under pipefail and a grep exiting early can fail the pipeline it matched (STATBUS-227). The later-vintage usermod calls in stage_user_setup (devops) and stage_service_account ($user) are left in place: they are idempotent and the second still serves boxes where the service account is created late.

Marked Done 2026-10-13. AC 5 (the next real preparation reporting "Docker usable by <user>") rides with STATBUS-497. CI coverage: this commit own runs have aged out of the visible window, but STATBUS-489 later commit 7e38edfc4 has Harness Selftest SUCCESS and contains this code, and that workflow runs this test - so the code is covered green.
<!-- SECTION:NOTES:END -->
