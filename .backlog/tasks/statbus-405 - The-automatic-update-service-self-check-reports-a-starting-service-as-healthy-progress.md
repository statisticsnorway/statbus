---
id: STATBUS-405
title: The automatic update self-check reports a starting service as healthy progress
status: Done
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-15 19:39'
labels:
  - release-bug
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
### North Star
The automatic update service's startup message tells the truth: while it is starting it reports progress, it reports success only once it is ready, and it raises an alarm only when it is really not running.

### Zoom out
A systemd service passes through `activating` on its way to `active`. A self-check that treats every state other than `active` as failure prints a frightening "NOT RUNNING" box during a perfectly normal start, and the operator learns to ignore alarms. The check must therefore classify what systemd reports: activating is progress, active and ready is success, inactive or failed is the alarm. Messages appear in that order, and the alarm is followed by the one install command that repairs it.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** the journal showed `The upgrade service is NOT RUNNING: statbus-upgrade@statbus.service` while the unit was activating and later reached READY (`tmp/finland-transcript-2-actual.txt:162`).
- **Shipped (merge `70741d8a4`, 2026-10-01, in v2026.10.1):** `classifySystemdActivity` (`cli/internal/unitfloor`) is the production classifier used by `systemdActivityIsRunning`; activating is progress, and success is recorded only after readiness.
- **Proof, unit:** `TestActivatingIsStartupProgressUntilReady` (the real `activating` then `ready` sequence, alarm-free, success only on the second) and `TestInactiveProducesAlarmBeforeRecoveryGuidance` (alarm first, then the complete install command). Green 2026-10-15.
- **Proof, real box:** `1-boot-startup-timeout.sh` reads the recovered service's journal, rejects `The upgrade service is NOT RUNNING`, the inactive alarm and the repair box, and requires `Starting`, `Upgrade service started (channel=` and `Started` in that order. PASS in the v2026.10.1 LXD fleet, run `38740447079` (2026-10-15, 379 s).

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 While the service is activating the self-check reports progress and no alarm, and reports success only after readiness (`TestActivatingIsStartupProgressUntilReady`)
- [x] #2 An inactive service produces the alarm followed by the complete install recovery command (`TestInactiveProducesAlarmBeforeRecoveryGuidance`)
- [x] #3 On a real box, the journal from activation through readiness has no alarm and shows `Starting statbus-upgrade@statbus.service`, `Upgrade service started (channel=` and `Started statbus-upgrade@statbus.service` in that order (`1-boot-startup-timeout.sh`, PASS in LXD fleet `38740447079` at v2026.10.1)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green locally on master, 2026-10-15.
- **AC3:** LXD fleet `38740447079` (v2026.10.1, `3b17af171`), `comparison.tsv`: `1-boot-startup-timeout PASS 379 s`.
<!-- SECTION:NOTES:END -->
