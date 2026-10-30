---
id: STATBUS-551
title: >-
  Worker skips seeding recurring maintenance when it starts inside the upgrade's
  read-only window
status: In Progress
assignee: []
created_date: '2026-10-30T19:31:00Z'
updated_date: '2026-10-30T23:41:00Z'
labels:
  - worker
  - upgrade
dependencies: []
priority: medium
type: bug
ordinal: 474204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: a worker start always leaves every recurring maintenance command with a pending row, whatever the database's read-only state at that moment.

### Zoom out
An upgrade sets the database read-only (default_transaction_read_only = on) so a rollback can never lose a write, and starts the new worker before it lifts that window. Every startup step that writes meets the window. Crash recovery is the one step exempt from it (STATBUS-265). The recurring-task seed (STATBUS-263) is ordinary work, so it waits for the window to end instead of being exempt (owner's decision, 2026-10-30). Impact before the fix: a box whose recurring rows were already missing stayed unrepaired until the next worker restart, and healthy boxes logged a false ERROR on every upgrade.

### Zoom in
rc.02 LXD fleet 41108121046, 0-https-only-egress capture: the new worker started at 18:43:52, the upgrade unblocked SQL writes at 18:43:56, and the worker logged 'Failed to seed recurring maintenance tasks: cannot execute INSERT in a read-only transaction. Maintenance may not recur until the next worker start.' Fix (ae0fdbde9): cli/src/worker.cr seed_recurring_tasks_when_writable runs the seed in its own fiber on a fresh connection. On SQLSTATE 25006 it logs one INFO line and retries every 5 s until the seed succeeds or the worker shuts down; any other error is logged as ERROR. Test: test/worker-seed-read-only-test.sh, run by Fast Tests against the commit's worker image (WORKER_IN_CONTAINER=1).

### Closing review
The seed's comment in cli/src/worker.cr states why it waits rather than being exempt. No memory or doc change needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A test reproduces the skip: worker started with default_transaction_read_only=on, then writes unblocked; recurring tasks missing before start are still absent afterwards (red)
- [x] #2 After the fix the same test ends with every recurring command pending, and a scan of the worker log finds no 'Failed to seed recurring maintenance tasks' line
- [ ] #3 Fast Tests green on ae0fdbde9 or later, with the step 'Worker started read-only restores recurring tasks once writable (STATBUS-551)' passing (run ID recorded)
- [ ] #4 The rc.03 LXD fleet passes, and an upgrade scenario's captured worker log shows the read-only INFO line and no 'Failed to seed recurring maintenance tasks' line (run ID and capture recorded)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Prototype (rolled back, statbus_seed on the test container, tmp/551-proto.log): with default_transaction_read_only=on, seed_recurring_tasks() fails with the field error; with the scoped exemption crash recovery uses (SET ... = off, then RESET), after removing task_cleanup's pending row the seed recreates exactly that row. Proposed fix: run the seed inside that existing exemption in cli/src/worker.cr, before the RESET. Awaiting owner go-ahead.

2026-10-30 23:20 owner discussion: preferred design is the owner's: the worker detects that the database is read-only and waits, instead of widening the read-only exemption. At startup, if the seed hits the read-only window, log one plain INFO line (database read-only for an upgrade; recurring jobs restored once writable) and retry every few seconds in a separate fiber, so normal startup and queue processing are not blocked; stop retrying only on shutdown. The guard keeps one exemption (crash recovery). Awaiting owner go-ahead to build.

Implemented (owner's design): worker.cr seed_recurring_tasks_when_writable runs the seed in its own fiber on a fresh connection; on SQLSTATE 25006 it logs one INFO line and retries every 5 s until writable or shutdown; other errors stay ERROR. No new read-only exemption. Test test/worker-seed-read-only-test.sh runs the real worker against an isolated copy of statbus_test_template with task_cleanup's pending row removed and the DB read-only, lifts read-only after 6 s: red on the current worker (tmp/test-551-red.log: 'Failed to seed ... read-only', row absent; also red on the compose image b6d81049 via WORKER_IN_CONTAINER=1, tmp/test-551-container-old-image.log), green after (tmp/test-551-green.log: INFO read-only line, then 'Seeded missing recurring maintenance task(s): task_cleanup', no 'Failed to seed' line). Healthy box (nothing missing, writable): no seed lines at all (tmp/test-551-healthy.log). Fast Tests runs the test against the commit's worker image.
<!-- SECTION:NOTES:END -->
