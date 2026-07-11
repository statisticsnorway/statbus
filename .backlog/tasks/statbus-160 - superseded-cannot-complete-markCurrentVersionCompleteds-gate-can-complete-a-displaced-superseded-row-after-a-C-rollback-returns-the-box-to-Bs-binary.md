---
id: STATBUS-160
title: >-
  superseded-cannot-complete: markCurrentVersionCompleted's gate can complete a
  displaced-superseded row after a C rollback returns the box to B's binary
status: To Do
assignee: []
created_date: '2026-07-11 22:46'
labels:
  - upgrade
  - recovery
  - architecture
dependencies: []
references:
  - STATBUS-159
  - STATBUS-154
priority: medium
ordinal: 161000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a row that ended as 'superseded' (displaced by a fix-release claim) stays superseded forever; no later boot may quietly promote it to completed.
> STAGE: upgrade recovery / state-model integrity. FOUND: 2026-07-12 — residual identified by the architect while ruling STATBUS-159 (displacement-at-claim); explicitly OUT of 159's scope, pre-existing class, unchanged by 159's fix ("gate ignores app health, same before/after").
> COMPLEXITY: needs an architect ruling on the gate shape before build.

THE RESIDUAL (from 159's ruling comment): markCurrentVersionCompleted (service.go — 154 added the state/parked guard) completes "the row whose commit_sha matches the running binary and completed_at IS NULL". Sequence: B parks → C claims (displacing B to superseded) → C FAILS and rolls back → the box is back on B's binary. On the next boot, the gate can match the displaced-superseded B row and mark it completed — a superseded row silently becoming the completed current version, contradicting the displacement's meaning and the state log's narration.

SHAPE QUESTION for the architect: does the completer's WHERE exclude terminal states (code gate), or does 'superseded' get the same DB-enforced cannot-be-completed treatment 154 gave parked rows? Per the always-add-constraints principle the DB-level guard is the likely floor; ruling needed on exact geometry AND on the honest disposition for a box rolled back onto a displaced version's binary (fresh row? re-open B? refuse?).

Origin: STATBUS-159 ruling comment #1 (architect, 2026-07-12); wave-9 evidence tmp/wave9-healthpark-job.log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling recorded: the guard geometry preventing completion of a superseded row (code gate vs DB constraint) and the honest disposition for a box rolled back onto a displaced version's binary
- [ ] #2 A displaced-superseded row provably cannot reach completed_at/state=completed under the post-rollback boot sequence (test proves it)
<!-- AC:END -->
