---
id: STATBUS-603
title: >-
  Setup's summary shows a rerun as a rerun: each stage says whether it changed
  something or found it already in place
status: To Do
assignee: []
created_date: '2026-11-10T10:05:00Z'
updated_date: '2026-11-10T10:05:00Z'
labels:
  - setup
dependencies: []
priority: medium
type: bug
ordinal: 519204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

On a box that is already set up, the end of a setup rerun tells the operator what is already in place, and gives no next step they have already taken.

### Zoom out

The owner reran the full released setup (v2026.11.3) on Uganda on 2026-11-10 as an idempotency check. Every stage verified and changed nothing, but the summary still reads as a first install: "statbus service account created (for StatBus install)" although the stage logged "User 'statbus' already exists, reusing" and "1 key already present, 0 added"; and "Next step: install StatBus as 'statbus'" although StatBus has run on that box for months. The firewall line was fixed separately (STATBUS-602).

### Zoom in

`ops/setup-ubuntu-lts.sh`: the service-account summary line distinguishes created from found (the stage already knows which), and `print_run_summary` offers the install next step only when no StatBus checkout exists for the service user (for example `~statbus/statbus/.env` absent). Prove it in `test/install-recovery/tests/setup-summary-truth-test.sh`, RED first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 setup-summary-truth-test.sh fails against the current setup and passes after: a rerun that reused the service account says it was found, not created
- [ ] #2 The same test: with a StatBus installation present for the service user, the summary gives no 'install StatBus' next step; without one it does
- [ ] #3 Every stage's summary line on a rerun of a configured box says it found its work already in place, and names what it changed when it did change something (e.g. a Docker upgrade), proven in setup-summary-truth-test.sh
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-10 10:05 UTC owner: idempotency should be visible. The summary line of every stage says whether this run changed something or found it already in place (e.g. 'statbus service account already present, 1 key, none added'; 'Docker updated 29.9.2 -> 29.9.3'; 'firewall rules already in place: OpenSSH (22), 713/tcp, 80, 443, 5432'), so a rerun on a configured box reads as a rerun. The install next step appears only when no StatBus installation exists for the service user.
<!-- SECTION:NOTES:END -->
