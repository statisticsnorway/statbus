---
id: STATBUS-578
title: Preserve requested detached dev command and arguments
status: Done
assignee: []
created_date: '2026-11-07T20:11:00Z'
updated_date: '2026-11-07T20:13:00Z'
labels: []
dependencies: []
type: bug
ordinal: 505204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Detached dispatch shifts the already parsed action again, so detached test fast launches fast instead of test fast. Keep scope to exact child command and arguments and safe acceptance coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The public detached test fast invocation starts the child with test and fast intact.
- [x] #2 Detached execution preserves argument boundaries and records explicit child exit evidence in a bounded actual tmux regression.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RED dfd968c18: bash test/dev-detached-test.sh failed with actual tmux, launcher advertised ./dev.sh fast and exact child argv comparison failed. GREEN 9267baa55: same public detached test fast invocation in private fixture passed exact test/fast argv and observed child EXIT trap status 0. Quoted, empty, newline and metacharacter arguments preserved with child status 23, single help preserved with status 0. Fixture uses full public launcher, safe child entrypoint and isolated real tmux socket. Final log tmp/578-green-final.log, retained fixture tmp/dev-detached.lPidpK, journal tmp/578-worker-journal.md. bash -n, actionlint Harness Selftest, git diff --check passed. Harness Selftest path and step wired. Launcher exit 0 is not SQL suite success. No SQL/DB runs or mutation, no push, no Norway or sibling checkout writes. Coordinator owns final SQL regression and push/CI.
<!-- SECTION:NOTES:END -->
