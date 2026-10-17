---
id: STATBUS-516
title: >-
  The release gate tests the candidate against the previous stable, not against
  pinned old releases
status: To Do
assignee: []
created_date: '2026-10-17 15:39'
labels:
  - ci
  - lxd
dependencies: []
priority: high
ordinal: 442204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every release-gate test starts from the candidate or the previous stable release, so the gate tests what real boxes will run and costs only what it must.

### Zoom out
A past incident, once understood and fixed, keeps its lesson in a unit test or a principle. A gate test pinned to an old release keeps paying for an incident real boxes no longer reach, and grows slower as releases accumulate.

### Zoom in
- Four gate tests install hard-coded old releases: `5-install-source-identity-operator` and `-scheduled` (v2026.09.2 targeting v2026.09.3, STATBUS-436), arc `cross-version-rename-handoff` (v2026.07.0-rc.05, STATBUS-164), arc `rollback-schema-floor-adoption` (v2026.09.0, STATBUS-354).
- Together 64 of 356 guest-minutes in v2026.10.2-rc.01; the two source-identity tests are the longest (19 min each), 5 min of which is the old daemon verifying 24 newer releases.
- Their logic is covered by Go tests that pass on master (2026-10-17): `TestPhaseBytes_*`, `TestCaptureSourceServingImageIdentitiesRejectsMixedContainerTags`, `...SurvivesLostComposeDisplay`, `TestReapplyRollbackDaemonSchemaFloorUsesTargetBinaryAndOrdinaryLedger`, `TestRollbackSchemaFloorFailureDurablyRoutesDaemonAliveIdle`.
- Owner decision 2026-10-17: drop all four. Design record: `tmp/lxd-gate-design.md` (T1).

### Closing review
- **Memory:** none needed.
- **Documentation:** `test/install-recovery/README.md` and `doc/upgrade-rollback-floor.md` no longer list these tests as gate coverage.
- **Cleanup:** evidence folders under `test/install-recovery/lxd/evidence/` stay as history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Remove the four tests and their wiring: scenario files, arc files, `lxd/run-arcs.sh`, the checkpoint mapping in `lib/lxd-backend.sh`, `lib/vm-bootstrap.sh`
- [ ] #2 Update the harness self-tests that name them (`tests/lxd-checkpoint-identity-test.sh`, `tests/rc10-schema-floor-family-test.sh`, `tests/lxd-default-domain-test.sh`) and run them green
- [ ] #3 Update `test/install-recovery/README.md`, `doc/upgrade-rollback-floor.md` and `doc/diagrams/upgrade-timeline.*` so no doc names the removed tests as coverage
- [ ] #4 Run the Go tests listed in the Description on the change and record them green in Implementation Notes
- [ ] #5 A candidate gate run after the change installs no release older than the previous stable, shown by its fault artifact and arc logs; run IDs recorded in Implementation Notes
<!-- AC:END -->
