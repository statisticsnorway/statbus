---
id: STATBUS-578
title: Preserve requested detached dev command and arguments
status: In Progress
assignee: []
created_date: '2026-11-07T20:11:00Z'
updated_date: '2026-11-07T20:17:00Z'
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

Coordinator review: behavioral acceptance passed locally. Ticket remains In Progress until the fix is pushed and exact-SHA Harness Selftest CI is inspected. Final SQL regression and release work are tracked separately and are not established by a successful detached launcher.

Follow-up b98406ee7 uses direct tmux argv: bash -o pipefail -c "$_DETACHED_RUN", eliminating the outer default-shell quoting dependency. At 2026-11-07 20:17Z reran bash test/dev-detached-test.sh with real tmux: exact test/fast and single help child exits 0, quoted/empty/newline/metacharacter arguments with child EXIT trap 23 all passed. Evidence tmp/578-direct-argv-green.log and retained fixture tmp/dev-detached.Gu09AF. bash -n dev.sh test/dev-detached-test.sh, actionlint .github/workflows/harness-selftest.yaml and scoped git diff --check passed. Ticket deliberately remains In Progress for coordinator push and exact-SHA CI inspection. No SQL/DB runs, push or sibling checkout changes.
<!-- SECTION:NOTES:END -->
