---
id: STATBUS-516
title: >-
  The release gate tests the candidate against the previous stable, not against
  pinned old releases
status: In Progress
assignee: []
created_date: '2026-10-17 15:39'
updated_date: '2026-10-20 11:41'
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
- [x] #1 Remove the four tests and their wiring: scenario files, arc files, `lxd/run-arcs.sh`, the checkpoint mapping in `lib/lxd-backend.sh`, `lib/vm-bootstrap.sh`; `rg` for the four test names outside `tmp/`, `.backlog/` and `lxd/evidence/` finds nothing
- [x] #2 Update the harness self-tests that name them (`tests/lxd-checkpoint-identity-test.sh`, `tests/rc10-schema-floor-family-test.sh`, `tests/lxd-default-domain-test.sh`, `tests/process-log-host-guest-test.sh`, `tests/scenario-selection-test.sh`) and run them green
- [x] #3 Update `test/install-recovery/README.md`, `doc/upgrade-rollback-floor.md` and `doc/diagrams/upgrade-timeline.*` so no doc names the removed tests as coverage
- [x] #4 Run the Go tests listed in the Description on the change and record them green in Implementation Notes
- [ ] #5 On the first release candidate cut after `41689e94a` (check with `git merge-base --is-ancestor 41689e94a <tag>`), every `historical base`, `historical baseline` and `historical target` line in its fault fleet artifact and arc logs names that candidate's previous stable release and nothing older; record both run IDs in Implementation Notes, then set Done
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20: `rg` for the four test names (excluding tmp/, .backlog/, test/install-recovery/lxd/evidence/) returns nothing.

2026-10-20: commit 41689e94a removes the four pinned tests and wiring (scenarios, arcs, run-arcs.sh + workflow lineage cases incl. SCHEMA_FLOOR_BASE_SHA/PRE_RENAME_BASE_SHA, lxd-backend checkpoint case, lxd-fleet summary, dead adoption helpers in schema-floor-assertions.sh). Self-tests updated: rc10-schema-floor-family, lxd-checkpoint-identity, lxd-default-domain (now self-contained fixture cells), process-log-host-guest (source-proof block removed), scenario-selection (on-demand example now 5-install-cert-repair-via-cert-install). ./dev.sh test-harness green (tmp/test-516-harness.log). Go tests green (tmp/test-516-go.log): TestPhaseBytes_{DecodeNormalizesLegacyThroughChokepoint,IsServiceNewSbRecovery_AcrossSpellings,ReadModifyWriteRewritesLegacyToCanonical,TablesAreDisjoint}, TestCaptureSourceServingImageIdentitiesRejectsMixedContainerTags, ...SurvivesLostComposeDisplay, TestReapplyRollbackDaemonSchemaFloorUsesTargetBinaryAndOrdinaryLedger, TestRollbackSchemaFloorFailureDurablyRoutesDaemonAliveIdle. AC#5 awaits the next candidate gate run.

CI on 41689e94a: Go Test, app build & lint, Harness Selftest, Push on master, Images, Notify all completed/success (checked 2026-10-20 11:41 UTC).

2026-10-20, waiting: no existing tag contains 41689e94a (newest is v2026.10.3, 2026-10-17), and the fault fleet only runs on a release-candidate tag (`run-forks.sh` refuses other refs). The owner chose to wait for the next ordinary candidate rather than cut one for this check. Baseline for AC5 from v2026.10.2-rc.01 (runs 38819807364, 38819893048): the old logs named `historical baseline v2026.10.1` (8, the previous stable, expected), `historical target v2026.10.1` (1, expected), and `historical base` v2026.09.2 (2), v2026.07.0-rc.05 (1), v2026.09.0 (1), which are the four removed tests.
<!-- SECTION:NOTES:END -->
