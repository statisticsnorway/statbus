---
id: STATBUS-242
title: >-
  terminal-rewind-column-audit: every column the rollback restore rewinds that
  the terminal write must preserve — enumerated once, as a mechanism
status: To Do
assignee: []
created_date: '2026-08-19 00:17'
updated_date: '2026-08-19 10:14'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 10:14
---
AUTHORITATIVE ENUMERATION (AC#1), part 1 of 2 — the window and two findings that widen the problem beyond how the founding incidents framed it. Part 2 carries the dispositions.

## The window, precisely

- **OPENS** at `d.backupDatabase(...)` — service.go:5713. The snapshot's contents are the table as it stands at that instant.
- **CLOSES** at `d.restoreDatabase(...)` — service.go:8274 (rollback) and :8705 (abort). The volume rewinds to the snapshot.
- **TERMINAL WRITES** run after the rewind — :2971, :8398, :8428, :8665, :8800 — and are the only chance to re-impose anything.

A write executed between those points is lost unless a terminal write puts it back. The carrier for re-imposed values is the FLAG, never a remembered variable (the 241 ruling); `writeRollbackTerminal`'s contract at :8154-8164 already states this for recovery_attempts.

## FINDING 1 — the restore rewinds the WHOLE TABLE, not the upgrading row

Both founding incidents concerned the row being upgraded, and that framing is too narrow. `restoreDatabase` rewinds the database volume, so EVERY row returns to its snapshot state — including rows the upgrade never touched. Concurrent writers in the window are therefore in scope:

- **`superseded_at` / `state='superseded'`** (:1706, supersedeOlderReleases) — a newer candidate arriving mid-upgrade supersedes older rows; a restore silently un-supersedes them.
- **`dismissed_at`, `skipped_at`** — deliberate human acts. A restore reverts an operator's dismissal with no record it ever happened.

These differ from the derived columns in the decisive respect: **nothing re-derives them.** Discovery recomputes image and build status on its next tick, so losing those is self-correcting. Nobody re-dismisses a candidate on the operator's behalf. Same defect class as STATBUS-181 and 241, one scope wider — and precisely the third instance this ticket exists to make impossible.

## FINDING 2 — a service.go-only scan would be a zero-scope check

public.upgrade is not written solely by the Go service. It is exposed through PostgREST under RLS, and the operator-facing dismiss/skip actions are app writes. **A mechanism that greps only cli/internal/upgrade/service.go would pass while blind to exactly the writers Finding 1 identifies as unrecoverable.** It must either cover the app's write paths as well, or state in its own failure message that it does not — a check must report what it examined (doc-033).
---

author: architect
created: 2026-08-19 10:14
---
AUTHORITATIVE ENUMERATION (AC#1), part 2 of 2 — dispositions and the mechanism shape.

**A — RE-IMPOSED FROM THE FLAG** (in-window write whose meaning must survive):
1. `recovery_attempts` — written :6989 (`+ 1`). Re-imposed as `recovery_attempts = $2` at all five terminals. FOUNDING (STATBUS-181, observed live at rc.03).
2. `backup_path` — written :6526, the single row recorder. Re-imposed via `terminalBackupPathSQL` (:8152) as `$4`. FOUNDING (STATBUS-241).

**B — SUPERSEDED BY THE TERMINAL WRITE ITSELF.** No re-imposition needed; the terminal sets them after the rewind: `state`; `error` (the mid-flight annotations at :6295 and :6249 are overwritten by `error = $1`); `rolled_back_at` (:8428).

**C — OUTSIDE THE WINDOW** (written before the snapshot, therefore contained in it). Verified for the first two: `log_relative_file_path` (:5351) and the claim's `state` / `started_at` / `from_commit_version` (:5198) all execute inside `executeUpgrade` (opens :5323) BEFORE the backup at :5713. Also `scheduled_at`, `recreate`, `discovered_at`. Exempt — the snapshot already holds them.

**D — SUCCESS PATH ONLY, no restore occurs.** `completed_at` and the completion write's `docker_images_status='ready'` (:3306, :6814, :7411). Exempt by construction.

**E — SELF-HEALING DERIVED.** `docker_images_status` (:1682), `release_builds_status` (:4065, :4094), `docker_images_downloaded` (:4437), `commit_tags` / `release_status` (:4225), and the static discovery columns (`commit_sha`, `committed_at`, `summary`, `changes`, `release_url`, `has_migrations`, `commit_version`). Exempt WITH REASON: discovery re-derives each from an external source of truth on its next tick. The reason is "re-derived", NOT "unimportant" — if any of these ever stops being re-derived, its exemption expires with it.

**F — OPEN, to be resolved as the mechanism is built.** `recovery_parked_at`, `recovery_parked_reason` (:7210, :6249), plus the Finding 1 columns `superseded_at`, `dismissed_at`, `skipped_at`. I did not trace every park and abort interleaving to a confident verdict, and I am leaving them explicitly open rather than guessing — an enumeration handed on as fact is the failure mode this campaign has hit repeatedly, mine included. **The mechanism resolves them by construction: unaccounted goes red until dispositioned**, which is stronger than any answer I could assert here and is the whole point of AC#2.

## Mechanism shape

**Scan for write SITES, not columns.** A column can have several sites with different dispositions — `error` at :6295 is in-window and superseded, `error` at the terminals is the superseding write. Key each site by file:line plus the column set it writes, and require every site to carry exactly one of:

- **RE-IMPOSED** — naming the terminal that re-imposes it AND the flag field the value comes from (never a remembered variable);
- **EXEMPT** — naming which of B–E applies, and why.

A new or moved site with no entry goes red, in the same shape as `TestEveryBackupPathWriterIsAccountedFor_STATBUS229`. Per Finding 2, the scan's scope must include the app's write paths or say plainly that it does not.
---
<!-- COMMENTS:END -->
