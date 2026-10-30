---
id: STATBUS-551
title: >-
  Worker skips seeding recurring maintenance when it starts inside the upgrade's
  read-only window
status: To Do
assignee: []
created_date: '2026-10-30T19:31:00Z'
updated_date: '2026-10-30T23:22:00Z'
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
Every startup step that writes (seed, crash recovery, anything added later) shares the upgrade's read-only window; the window ends seconds later, so an exemption or a retry closes it. Impact today: a box whose recurring rows were already missing stays unrepaired until the next worker restart; healthy boxes get a false ERROR line on every upgrade.

### Zoom in
rc.02 LXD fleet 41108121046, 0-https-only-egress capture (tmp/rc02-lxd-art/lxd-fleet-comparison/lxd-s2-*-0-https-only-egress-failure-*.log): the new worker started at 18:43:52, the upgrade unblocked SQL writes at 18:43:56. Worker log: 'Failed to seed recurring maintenance tasks: cannot execute INSERT in a read-only transaction. Maintenance may not recur until the next worker start.' Crash recovery (reset abandoned processing tasks) is exempt from the read-only guard (STATBUS-265, SET default_transaction_read_only = off then RESET); the seed in cli/src/worker.cr (STATBUS-263, worker.seed_recurring_tasks()) runs after the RESET and is not exempt.

### Closing review
The worker startup comment in cli/src/worker.cr states which startup writes are exempt and why; no memory or doc change expected beyond that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test reproduces the skip: worker started with default_transaction_read_only=on, then writes unblocked; recurring tasks missing before start are still absent afterwards (red)
- [ ] #2 After the fix the same test ends with every recurring command pending, and a scan of the worker log finds no 'Failed to seed recurring maintenance tasks' line
- [ ] #3 Fast Tests green, and an LXD upgrade scenario capture shows the worker log without the seed failure
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Prototype (rolled back, statbus_seed on the test container, tmp/551-proto.log): with default_transaction_read_only=on, seed_recurring_tasks() fails with the field error; with the scoped exemption crash recovery uses (SET ... = off, then RESET), after removing task_cleanup's pending row the seed recreates exactly that row. Proposed fix: run the seed inside that existing exemption in cli/src/worker.cr, before the RESET. Awaiting owner go-ahead.

2026-10-30 23:20 owner discussion: preferred design is the owner's: the worker detects that the database is read-only and waits, instead of widening the read-only exemption. At startup, if the seed hits the read-only window, log one plain INFO line (database read-only for an upgrade; recurring jobs restored once writable) and retry every few seconds in a separate fiber, so normal startup and queue processing are not blocked; stop retrying only on shutdown. The guard keeps one exemption (crash recovery). Awaiting owner go-ahead to build.
<!-- SECTION:NOTES:END -->
