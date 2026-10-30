---
id: STATBUS-551
title: >-
  Worker skips seeding recurring maintenance when it starts inside the upgrade's
  read-only window
status: To Do
assignee: []
created_date: '2026-10-30T19:31:00Z'
updated_date: '2026-10-30T19:31:00Z'
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
