---
id: STATBUS-232
title: >-
  phase-writer-pin: the flag invariant is guarded against one of its two
  violation routes
status: To Do
assignee: []
created_date: '2026-08-18 12:09'
labels:
  - upgrade-recovery
  - quality-gate
dependencies: []
references:
  - cli/internal/upgrade/backup_path_carriers_test.go
  - cli/internal/upgrade/service.go
priority: low
type: enhancement
ordinal: 232000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Crash recovery decides whether to roll a box back by reading a small marker file the upgrade leaves behind. One combination in that file is forbidden: a marker saying "nothing has changed yet" while also naming a database snapshot. Recovery reads that as permission to restore a database that was never touched — it has happened twice, and both times it took a real test failure on a real machine to notice.

WHAT GOES WRONG: the guard added to catch it watches only one of the two ways in. It enumerates every place the code writes the snapshot name, and fails if an unknown one appears. But the forbidden combination can also be reached from the other side — by changing the phase on a marker that already names a snapshot, leaving the same illegal pair. That is exactly what STATBUS-210 did, and this guard would not have caught it.

THE DETAIL: `TestEveryBackupPathWriterIsAccountedFor_STATBUS229` enumerates writers of `BackupPath`. STATBUS-197 violated the invariant that way, so the pin covers it. STATBUS-210 violated it the other way — it wrote `f.Phase = PhaseOldSbUpgrading` and touched `BackupPath` not at all, making an existing, legitimate snapshot identity dangerous by re-labelling the phase around it. The architect's STATBUS-228 ask named both routes ("every flag-writing call site that touches Phase OR BackupPath"); only the BackupPath half landed, which is honest scope, not a defect in what was built.

Nothing is currently wrong: STATBUS-229 removed the only phase-blanking writer, and `PhaseOldSbUpgrading` being the zero value means reaching it takes either an explicit assignment or a zero-valued struct. The exposure is the next writer, in a codebase where this exact invariant has now been broken twice from two different functions.

THE FIX: extend the guard to the second route — enumerate the writers of `Phase`, each with the reason it is allowed, in the same accounted-for shape. Better still, state the invariant once at the level it actually lives: no PERSISTED flag may pair a pre-swap phase with a snapshot identity, asserted over every construction and mutation site rather than over one field's writers.

WHY THAT HELPS: the guard then matches the claim it is making. A pin that watches one door of two reports safety it cannot see, which is worse than a pin that names its own scope — and this particular invariant has already proven it will be broken again by someone who never read the comment explaining it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The guard covers writers of Phase as well as BackupPath, each accounted for with its reason
- [ ] #2 Verified RED against the STATBUS-210 change: re-introducing the phase-blanking write fails the guard
- [ ] #3 The invariant is stated once, at flag level, rather than once per field
- [ ] #4 In-memory-only flag literals stay legal and are asserted as such, as the current pin already does for the flagless rollback site
<!-- AC:END -->
