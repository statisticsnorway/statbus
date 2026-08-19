---
id: STATBUS-242
title: >-
  terminal-rewind-column-audit: every column the rollback restore rewinds that
  the terminal write must preserve — enumerated once, as a mechanism
status: To Do
assignee: []
created_date: '2026-08-19 00:17'
labels:
  - upgrade-recovery
  - quality-gate
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: medium
type: enhancement
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rollback's database restore rewinds public.upgrade to a pre-upgrade snapshot, and every terminal write that runs after it silently loses any column not explicitly re-imposed. That mechanism has now bitten twice — recovery_attempts (observed live at rc.03, fixed by STATBUS-181's explicit re-imposition) and backup_path (predicted during the rc.05 arc corrections, fixed by STATBUS-241). A third instance should be impossible, not merely unlikely.

THE ASK (architect's morning ticket from the 241 ruling): a GENERAL answer instead of a third one-column patch when the next instance surfaces. Enumerate once, as a mechanism rather than prose: every column of public.upgrade that (a) is written between the pre-upgrade snapshot and a possible rollback restore, and (b) carries meaning the terminal row must preserve. For each: either the terminal write re-imposes it (from the authoritative carrier — the flag — per the 241 ruling, never a remembered variable), or a recorded reason why the rewound value is correct.

THE MECHANISM SHAPE (builder designs, architect verifies): the strongest form is a pin that fails when a new post-snapshot column write appears without a corresponding terminal re-imposition or exemption — the same every-writer-accounted-for pattern as TestEveryBackupPathWriterIsAccountedFor_STATBUS229. Prose lists rot; the 197 comment-premise lesson applies.

WHAT IS ACHIEVED: the terminal-write path stops being a place where the restore quietly eats one column per incident; the next person who adds a column write learns at test time that the rewind exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every post-snapshot column write in the upgrade path is enumerated with its terminal-write disposition: re-imposed (flag-sourced) or exempt-with-reason
- [ ] #2 The enumeration is a failing-test mechanism, not prose — a new unaccounted column write goes red until dispositioned
- [ ] #3 recovery_attempts and backup_path appear as the two founding entries, citing STATBUS-181 and STATBUS-241
<!-- AC:END -->
