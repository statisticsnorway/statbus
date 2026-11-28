---
id: vcbb8d
title: "The upgrade progress page names each migration and long step as it runs"
state: "doing"
type: feature
priority: ""
assignee: ["worker-vcbb8d"]
labels: []
group: ""
rank: "zzzzzzzzzzzs"
created: 2026-11-28
updated: 2026-11-28
doing_since: "2026-11-28T15:39"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
---

## Goal
The upgrade progress page shows each step before it runs and keeps reporting while a long step runs.

## Purpose
The Norway upgrade to rc.02 looked hung: the page went silent for 2m47s and 11m34s, then printed 'Applying database migrations: 21 pending ... ok' with no start line.

## Principle
Every main-narration step writes its start line before it runs and its result after; a step longer than 30 s writes a still-running line, as the backup does. The page keeps showing only M lines; what it needs is narrated as M lines.

## Details
rune 2026-11-28 (tmp/norway-rc02-progress.log, tmp/norway-rc02-handover-journal.log). Gap 1 10:21:47-10:24:34: systemd restarts the new binary after 30 s; its recovery boot's floor migrate ran EnsureTrackedExtensions, ALTER EXTENSION sql_saga UPDATE TO '1.15' for 130 s (db log duration 130371 ms), printed with fmt.Printf to the journal only (cli/internal/migrate/extensions.go:178). Gap 2 10:24:37-10:36:11: the delta migrate (service.go:11295 runMigrateUpToLog); per-migration output goes to the log as 'O migrate' lines, which ops/maintenance/maintenance.html filters out (line 287 keeps only 'M '); the M line is written only after migrate returns (service.go:11344). 20261127162620 alone ran 672 s (statistical_unit rewrite).

## Depends on

## Acceptance
- [ ] A test upgrade's progress log has, in order: an M line 'Applying database migrations: N pending ...' before the first migration, an M line per migration with its name and then its time, and an M still-running line at least every 30 s during a migration that runs longer
- [ ] The boot extension update writes M lines (extension, versions, start and time) to the progress log
- [ ] Observed on a real upgrade (dev canary or Norway): the progress page shows the running migration's name during its run

## Notes

file:norway-rc02-progress.log (15281 bytes, sha256:c5c36195)

file:norway-rc02-handover-journal.log (6075 bytes, sha256:fe72e133)


## History
- 2026-11-28T15:39 todo -> doing/active (take)
