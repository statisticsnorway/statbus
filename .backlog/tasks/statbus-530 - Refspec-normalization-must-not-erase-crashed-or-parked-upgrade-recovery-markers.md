---
id: STATBUS-530
title: >-
  Refspec normalization must not erase crashed or parked upgrade recovery
  markers
status: To Do
assignee: []
created_date: '2026-10-26 22:28'
labels:
  - upgrade
  - cli
  - recovery
dependencies: []
priority: high
type: bug
ordinal: 456204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Refspec normalization never destroys an upgrade's recovery marker. A crashed or parked upgrade keeps the state `./sb install` needs to recover it.

### Zoom out
The STATBUS-527 review proved that the new lifecycle commands initially used an adopt-and-delete install lock and erased crashed or parked recovery markers. Those call sites were fixed. One older caller has the same defect and was explicitly outside 527's scope: `cli/cmd/upgrade.go` normalizes refspecs with `upgrade.AcquireInstallFlag` and later releases it. If the canonical marker already exists with its flock free, the acquire overwrites it and release deletes it.

An existing service marker means an upgrade is in progress, parked, or needs recovery. Refspec normalization is housekeeping and must never take ownership of that state.

### Zoom in
- Location found by the final 527 reviewer: `cli/cmd/upgrade.go:419` (refspec normalization).
- Failure: an upgrade crashes or parks, leaving `Holder=service` and recovery state with a free flock. The refspec path acquires the install flag, replaces the marker, then deletes it on release. The next `./sb install` no longer sees the crashed-upgrade marker and can skip recovery.
- Fix direction: use the recovery-aware, fresh-only lifecycle acquisition introduced for 527, or skip normalization whenever an existing service/recovery marker is present. The marker must remain byte-identical. Preserve the intentional install-holder handoff.

### Closing review
- **Memory:** none needed; the recovery-marker ownership rule is in the code comments and ticket 527.
- **Documentation:** no new guide; the definition comment states why housekeeping refuses an existing recovery marker.
- **Cleanup:** no compatibility path that recreates the deleted state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A crashed or parked service marker remains byte-identical after refspec normalization; the next ./sb install still performs recovery
- [ ] #2 Regression tests prove the refspec path refuses or skips when a service/recovery marker exists, and still normalizes when no marker exists
- [ ] #3 Go tests and CI are green at the fix commit, and the 527 reviewer or a code review confirms no other refspec writer uses adopt-and-delete on a service marker
<!-- AC:END -->
