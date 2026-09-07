---
id: STATBUS-362
title: >-
  live tests drive the mutable on-disk ./sb: pin the binary they start with
status: To Do
assignee: []
created_date: '2026-09-07 17:26'
updated_date: '2026-09-07 17:26'
labels:
  - testing
  - upgrade
dependencies: []
priority: medium
type: task
---

## Ground truth (2026-09-07)

`live_statbus354_crash_twins_test.go` (and other `STATBUS_LIVE_DB=1` tests) invoke
`filepath.Join(projDir, "sb")` directly. That file is mutable: any concurrent
rebuild, or a raw `go build` without dev.sh's `cmd.commit` ldflag, changes what
the test is driving mid-run. Observed 2026-09-07 during the 354 review: an
identity-less `./sb` (`vcs.modified=true`, no `cmd.commit`) made every mutating
subcommand exit 69 after twin 1 had applied a real down migration, leaving
`statbus_local` below the daemon floor. Investigation:
`tmp/STATBUS-354-stale-sb-investigation.md`.

## What to do

Live tests build (via the same ldflags dev.sh uses) or copy the binary once at
test start into a temp path and drive THAT for the whole run. Add one test that
proves a mid-run replacement of `./sb` does not change the binary under test.

## Done when

- No live test references `filepath.Join(projDir, "sb")` for execution.
- The pinning test passes; full live suite green.

## Not this ticket

The freshness guard itself is correct (`cli/`-scoped). Do not widen or weaken it.

## Scope addition (2026-09-07 21:03): tests must never write the project's .env

`TestLiveReattemptRestore_DelayedSecondInstallCannotRestoreAgain`
(`cli/internal/upgrade/live_reattempt_race_test.go`) puts a fake `git` on
PATH that answers `rev-parse` with `1111…1111`, then lets the code under test
run `sb config generate` against the REAL project dir. Result on 2026-09-07:
the developer's `.env` carried `COMMIT_SHORT=1111…` and `VERSION=shim git:
describe …` from 16:38 until the RC cut at 20:47, and `build-sb` tried to
pull seed image `statbus-seed:1111…`. Owner ruling: unprincipled. Rule: a
live test gets a scratch project dir (copy of the tree, own `.env`) or it
does not exercise config generation. Same family as the stale-`./sb`
problem this ticket already covers; fix together.
