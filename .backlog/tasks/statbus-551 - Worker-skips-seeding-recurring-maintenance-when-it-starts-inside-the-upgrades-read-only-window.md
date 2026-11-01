---
id: STATBUS-551
title: >-
  Worker skips seeding recurring maintenance when it starts inside the upgrade's
  read-only window
status: In Progress
assignee: []
created_date: '2026-10-30T19:31:00Z'
updated_date: '2026-11-01T16:04:00Z'
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
- [x] #3 Fast Tests green on ae0fdbde9 or later, with the step 'Worker started read-only restores recurring tasks once writable (STATBUS-551)' passing (run ID recorded)
- [x] #4 The rc.03 LXD fleet passes, and an upgrade scenario's captured worker log shows the read-only INFO line and no 'Failed to seed recurring maintenance tasks' line (run ID and capture recorded)
- [ ] #5 Every upgrade scenario ends by asserting that every recurring maintenance command the worker seeds is present in worker.tasks, and that the worker log has no 'Failed to seed recurring maintenance tasks' line (shared post-upgrade assertion; offline harness test red without the seed, green with it; passes in the next RC's gate)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Prototype (rolled back, statbus_seed on the test container, tmp/551-proto.log): with default_transaction_read_only=on, seed_recurring_tasks() fails with the field error; with the scoped exemption crash recovery uses (SET ... = off, then RESET), after removing task_cleanup's pending row the seed recreates exactly that row. Proposed fix: run the seed inside that existing exemption in cli/src/worker.cr, before the RESET. Awaiting owner go-ahead.

2026-10-30 23:20 owner discussion: preferred design is the owner's: the worker detects that the database is read-only and waits, instead of widening the read-only exemption. At startup, if the seed hits the read-only window, log one plain INFO line (database read-only for an upgrade; recurring jobs restored once writable) and retry every few seconds in a separate fiber, so normal startup and queue processing are not blocked; stop retrying only on shutdown. The guard keeps one exemption (crash recovery). Awaiting owner go-ahead to build.

Implemented (owner's design): worker.cr seed_recurring_tasks_when_writable runs the seed in its own fiber on a fresh connection; on SQLSTATE 25006 it logs one INFO line and retries every 5 s until writable or shutdown; other errors stay ERROR. No new read-only exemption. Test test/worker-seed-read-only-test.sh runs the real worker against an isolated copy of statbus_test_template with task_cleanup's pending row removed and the DB read-only, lifts read-only after 6 s: red on the current worker (tmp/test-551-red.log: 'Failed to seed ... read-only', row absent; also red on the compose image b6d81049 via WORKER_IN_CONTAINER=1, tmp/test-551-container-old-image.log), green after (tmp/test-551-green.log: INFO read-only line, then 'Seeded missing recurring maintenance task(s): task_cleanup', no 'Failed to seed' line). Healthy box (nothing missing, writable): no seed lines at all (tmp/test-551-healthy.log). Fast Tests runs the test against the commit's worker image.

AC3: Fast Tests 41146791423 at 600a2257b (contains ae0fdbde9) success; step 'Worker started read-only restores recurring tasks once writable (STATBUS-551)' success, against the commit's worker image. Earlier runs on ae0fdbde9 (41145863986) and 74f5e6f8b (41146225140) were cancelled by newer pushes, not failed. In v2026.10.6-rc.03 (600a2257b); AC4 waits for its LXD fleet.

rc.03 gate green (2026-10-31 01:01 UTC): orchestrator 41148532815, LXD fleet 41149641777 (28/28 PASS), upgrade arcs 41149719409, Release 41148532827, Fast Tests 41148532812, Hardening 41148532823. AC4 evidence so far: passing LXD scenarios do not capture container logs (only failures do), so the fleet artifact holds no worker log. Dev canary upgraded to rc.03 (worker started 00:19:51): its worker log has 0 'Failed to seed' lines and all three recurring commands are pending (detect_stuck_tasks, import_job_cleanup, task_cleanup); the worker started after the window had lifted, so no read-only INFO line either. AC4 as written (INFO line in an upgrade capture) depends on the worker starting inside the window; owner to decide whether the dev evidence plus the Fast Tests step closes it.

2026-11-01 owner decision: close on the evidence. The fix runs in production code (dev since rc.03: no 'Failed to seed recurring maintenance tasks' line, the three recurring jobs pending), the red/green test runs in Fast Tests on every commit, and every gate since rc.03 passed the upgrade scenarios. AC4's LXD worker-log capture is not required; the read-only window is short and was not hit in passing scenarios. Whether upgrade scenarios should assert the end state permanently (all recurring maintenance tasks present after the upgrade) is tracked as a separate proposal, not as part of this ticket.

2026-11-01 owner: instead of a new ticket, add the cheap end-state check here and finish it now: assert the recurring tasks exist after every upgrade scenario and scan the worker log for the failure line. Delegated.

AC5 implementation (ec0d1f01e, fail-closed follow-up 742e2c60c, pushed by coordinator with the rc.08 prep): test/install-recovery/lib/assertions.sh adds assert_recurring_maintenance_tasks. It reads the expected set from worker.command_registry WHERE schedule_interval IS NOT NULL - the same source worker.seed_recurring_tasks() seeds from, so no second list can drift - and asserts every such command has a pending worker.tasks row, then scans 'docker compose logs worker' for 'Failed to seed recurring maintenance tasks'. Unreadable probes fail (return 1, naming worker.command_registry / worker.tasks / the worker log / a non-numeric scan), never skip. The check runs from the shared assert_health_passes, which every upgrade scenario and 39 arcs end through, plus an explicit call in c-rollback-resurrection-arc (the only arc that does not call health).

Offline test test/install-recovery/tests/recurring-maintenance-tasks-test.sh, run by Harness Selftest: green tmp/551-recurring-green.log (8 PASS: complete schedule passes; missing row fails naming import_job_cleanup; seed-failure line fails; empty registry fails; registry/tasks/log unreadable fail; non-numeric scan fails; rc=0). Red against parent d7c0067c3's assertions.sh: tmp/551-recurring-red.log 'assert_recurring_maintenance_tasks: command not found', rc=1. Red for the fail-closed fix against ec0d1f01e: tmp/551-recurring-infra-red.log 'INFRA error; skipping' then 'FAIL: worker.command_registry unreadable was accepted', rc=1. All 8 assertion-touching install-recovery selftests pass.

CI on pushed HEAD 742e2c60c: Harness Selftest run 41323938618 completed success; step 'Prove the upgrade end state asserts every recurring maintenance task (STATBUS-551)' success. AC5 left unchecked for the coordinator after the next RC gate.
<!-- SECTION:NOTES:END -->
