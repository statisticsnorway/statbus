---
id: skvfnn
title: "Migrations and the worker take turns, so a migration triggers one recalculation"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-28
updated: 2026-11-28
---

## Goal
While ./sb migrate up runs, the worker starts no task, and the recalculations migrations request run once, after the last migration.

## Purpose
On the test slot (2026-11-27) the worker started a full recalculation between two migrations, computed it against a half-migrated schema, and a second full pass followed: about 75 min of derive instead of 40. The upgrade stops the worker container and so avoids it, but any migrate up on a slot or by hand does not.

## Principle
Reuse what exists: migrate up already holds an exclusive advisory lock on hashtext('migrate_up') for its whole run; the worker takes the same lock shared, so workers never block each other and Postgres queues an exclusive request ahead of new shared ones. The pause point is the task, the unit that commits: a migration waits only for the tasks already running, and a pipeline paused between tasks is durable rows (pending, waiting), as after an upgrade's stop. No timer: a paused worker waits on the lock itself and resumes the moment it is free, also after a migrate crash.

## Details
Worker: worker.process_tasks claims and runs one task at a time, each with its own COMMIT (p_batch_size 10 is only a loop bound). Before claiming a task it takes pg_try_advisory_lock_shared(hashtext('migrate_up')) and releases it after the task's commit; on false it stops claiming and returns. Not when called inside a transaction (v_inside_transaction: a migration's inline CALL worker.process_tasks(), as in 20260427124351, runs under migrate's own exclusive lock). The Crystal worker (cli/src/worker.cr process_tasks, DB.connect per call, so a session lock never outlives its call) then blocks on pg_advisory_lock_shared on a dedicated connection, releases it at once and wakes its queues. Migrations keep calling worker.enqueue_derive_statistical_unit_all(): with no worker running, every request merges into the one pending collect_changes (idx_tasks_collect_changes_dedup). A pipeline paused mid-way finishes after the migrations; a migration that changes what the derive computes requests a full pass, which runs after it, so the last pass is on the new schema. migrate up's wait message names the worker's running task. Measured: a waiting exclusive advisory lock makes a new pg_try_advisory_lock_shared return false (local db, 2026-11-28). Longest single task on Norway: flush staging up to 316 s.

## Depends on

## Acceptance
- [ ] A test: while a task holds the shared lock, an exclusive request waits, no other task is claimed, and the exclusive lock is granted when that task commits
- [ ] A test: two migrations that each request a full recalculation leave exactly one pending collect_changes, and the worker runs one full pass after migrate up ends
- [ ] A migration's inline CALL worker.process_tasks() still processes its tasks
- [ ] A paused worker resumes within a second of migrate up releasing its lock, and after migrate up is killed, with no timer
- [ ] On a slot with the worker running, migrating across a migration that requests a recalculation runs one full pass, not two (observed)

## Notes

Owner 2026-11-28: think through the bad cases. (1) Upgrade: unchanged, never waits: it stops the worker container and then the database, which ends any running task; its transaction rolls back and the worker's startup reset (reset_abandoned_processing_tasks, STATBUS-264) marks it interrupted and reruns it. (2) Gap found: migrate.Up takes the exclusive lock before counting pending (migrate.go:995), so the upgrader's boot migrate on a running box (0 pending) would wait for a running task; migrate up must take the exclusive lock only when migrations are pending (count without the lock, recount under it). (3) Manual migrate up waits by default and says every 30 s which task it waits for and for how long; Ctrl-C applies nothing and leaves the worker untouched; --now does what the upgrade does: stop the worker, terminate its remaining database sessions (a stopped client's backend keeps running its SQL, so pg_terminate_backend is needed), migrate, start the worker; the interrupted task reruns. (4) A stuck task is the --now case. (5) A crashed or killed migrate releases its lock with its connection; a hung migrate keeps the worker paused, which is right while the schema is half-changed.
