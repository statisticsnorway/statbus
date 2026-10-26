---
id: STATBUS-530
title: >-
  Refspec normalization must not erase crashed or parked upgrade recovery
  markers
status: In Progress
assignee: []
created_date: 2026-10-26 22:28
updated_date: '2026-10-26T22:43:00Z'
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
- [x] #1 A crashed or parked service marker remains byte-identical after refspec normalization; the next ./sb install still performs recovery
- [x] #2 Regression tests prove the refspec path refuses or skips when a service/recovery marker exists, and still normalizes when no marker exists
- [ ] #3 Go tests and CI are green at the fix commit, and the 527 reviewer or a code review confirms no other refspec writer uses adopt-and-delete on a service marker
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fix commit b578b650d: cli/cmd/upgrade.go refspec normalization extracted into normalizeRefspecsUnderUpgradeMutex, now claiming the mutex with the recovery-aware fresh-only upgrade.AcquireLifecycleFlag instead of adopt-and-delete AcquireInstallFlag. Any existing marker refuses; normalization skips (never an error); the crashed/parked service marker survives byte-identical for the next ./sb install. ReleaseInstallFlag remains correct because acquisition only ever creates the marker.

Regression evidence (tmp/test-530-red.log, tmp/test-530-green.log): TestRefspecNormalize_PreservesServiceRecoveryMarker (phases new-sb-swapped crashed and new-sb-upgrading parked) FAILED before the fix — marker file deleted — and PASSES after, byte-identical and still parseable by ReadFlagFile for recovery. TestRefspecNormalize_NormalizesWhenNoMarker proves the no-marker path still normalizes to CanonicalRefspecs and leaves no stale install marker.

Verification: go test ./cmd/ ./internal/upgrade/ -count=1 ok (73.6s / 249.7s); golangci-lint run ./cmd/... ./internal/upgrade/... 0 issues (tmp/test-530-packages.log, tmp/test-530-lint.log). Code-read for the last AC clause: the only remaining AcquireInstallFlag caller is ./sb install itself (cmd/install.go:422), safe because install.Detect classifies a stale marker before acquiring.
<!-- SECTION:NOTES:END -->
