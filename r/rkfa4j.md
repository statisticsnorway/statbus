---
id: "rkfa4j"
title: "Upgrade lets the worker finish its current task before stopping it"
state: "todo"
assignee: []
labels:
  - upgrade
  - worker
group: ""
rank: ""
dependencies: []
priority: "low"
type: "feature"
origin: "backlog:DRAFT-002"
aliases: ["DRAFT-002"]
backlog_type: "enhancement"
created: "2026-08-27 16:14"
design_asked_by: "hibiscus"
design_question: "drain-before-upgrade awaits your ruling on the architect's design (2026-08-27): finish pending work with a bounded drain before upgrading, falling back to interruption. Accept it (then it gets acceptance checks), reject it, or drop the task?"
design_for: "jhf"
design_since: "2026-11-22T23:31"
stage: "design"
---

## Goal
An upgrade stops the worker after its current task ends, within a bounded wait, then proceeds as today if the wait runs out.


## Purpose
What we have today (checked in code 2026-11-26): the upgrade runs 'docker compose stop app worker rest' (cli/internal/upgrade/service.go, step 3). The worker container has no stop_grace_period, so Docker sends SIGTERM and kills it after 10 s. The worker's SIGTERM handler (cli/src/worker.cr handle_shutdown_signal) stops claiming new tasks and waits only 5 s for running fibers, then exits. A task running longer (an import batch, a derive) is cut off mid-transaction: PostgreSQL rolls it back, and on the next start worker.reset_abandoned_processing_tasks() puts it back to pending (STATBUS-264, which since retries and is exempt from the upgrade's read-only guard, STATBUS-265). So interruption is safe: no data is lost or half-written, the task is redone after the upgrade. What this would add: the interrupted task's work is not thrown away and redone, the upgrade observes a quiet box, and the operator sees 'Finishing current work…' instead of a task that silently restarts.

## Principle
Finish, never refuse: an upgrade is never blocked by pending work. The wait is bounded; when it runs out, today's safe interruption happens. No new protocol if a timeout is enough: first measure whether raising the worker's own 5 s fiber wait and Docker's stop timeout already gives a clean finish.

## Details
Pieces it would touch: (1) cli/src/worker.cr: the shutdown wait (5 s) becomes the drain bound, and a running task is allowed to commit before exit; (2) docker-compose.worker.yml: stop_grace_period for worker, above the drain bound (db already has 120 s); (3) cli/internal/upgrade/service.go step 3: a progress line 'Finishing current work (up to N s)…' and the stop of worker before app and rest; (4) a test that SIGTERM during a long task lets it commit and the task ends 'completed', not 'pending'. Complexity added: one timeout value per side and an ordering of stops; no new state, no refusal path. Cost: an upgrade can take up to the drain bound longer. Priority: low; safety is already there (264, 265), this buys less redone work and a cleaner operator message. Origin: architect's design 2026-08-27 for the owner's question 'we can't run the upgrade while work is pending, what is the principled way?'.

## Acceptance
- [ ] [Owner] decides: build it, or drop it as not worth the added wait; recorded in Notes
- [ ] A test sends SIGTERM to the worker during a task that takes longer than 5 s but less than the drain bound: the task ends completed and is not reset to pending on restart
- [ ] An upgrade in a real guest with a running import shows 'Finishing current work' and the import's batch completes before the worker stops

## Questions
- 2026-11-22T23:31 question 1 by hibiscus to jhf:
  drain-before-upgrade awaits your ruling on the architect's design (2026-08-27): finish pending work with a bounded drain before upgrading, falling back to interruption. Accept it (then it gets acceptance checks), reject it, or drop the task?


## Requests
- 2026-11-26T21:39 request 1 by jhf:
  I find this ticket is lacking clarity in what do we have today? It is referencing something else. Interruption is now safe by construction, but I would like to can you organize this so it is clearer to understand what we have, what this will solve, what it brings to the table, what complexity it adds, and what pieces or machinery it modifies
  resolved 2026-11-26T21:40 by rabbit:
    Rewritten around what we have today, checked in code: the upgrade stops the worker with Docker's 10 s timeout; the worker waits 5 s for running fibers, so a longer task is cut off, rolled back by PostgreSQL and reset to pending on restart (STATBUS-264/265), which is why interruption is safe. Purpose now says what draining would add (no redone work, a quiet box, a clear 'Finishing current work' message); Principle: finish never refuse, bounded, try a timeout first; Details: the four pieces it touches (worker.cr shutdown wait, worker stop_grace_period, upgrade step 3 order and message, a SIGTERM test), the complexity (two timeouts and an order, no new state) and its cost (up to the bound longer). Title and goal shortened; three checks, the first your build-or-drop decision.
- 2026-11-27T11:04 request 2 by jhf:
  Thinking about this ticket, I'm tempted to reject it. Why? Because then our current upgrade actually tests what we're doing. So I think that we either have to wait until the work finishes completely before we upgrade, meaning you have no in-progress things. But what if the upgrade fixes something that hangs? Or this behavior we have today is safe and exercises precisely rescuing something that will stall forever and making and it relies on and tests or semantics that are crash safe
- 2026-11-27T11:05 request 3 by jhf:
  But we have many tests, so if this is fully tested, because this brings some complexity, and how long would you wait then?
- 2026-11-27T15:39 request 4 by jhf:
  It seems hard to answer this without, for instance, measuring how long any task is on, say, the Norwegian installation, and because that's the bound on how long we have to wait, right

## Notes
2026-11-27 rabbit, measured on the Norway copy (local slot), 6 858 worker tasks 2026-11-15..27 (tmp/rkfa4j-task-durations.txt): share of tasks running longer than a bound: 5 s 30 %, 10 s 12.5 %, 30 s 2.6 %, 60 s 0.6 %, 120 s 0.09 % (6 tasks), 300 s 0.03 % (2), 600 s 0.01 % (1). Longest per command: derive_quality 690 s (before 0pn35h's partitioning; now 15 s with h9mhxe), statistical_unit_flush_staging 309 s (p95 185 s), derive_quality_partition 111 s, statistical_unit_refresh_batch 87 s (p50 8 s, 1 816 runs), history facet delta reduce 75 s. Imports: task rows are cleaned up, but import_job 9-11 (1.05 M rows each) processed in 610-1 349 s at 8 000 rows per batch, about 5-10 s per batch task. So today's 5 s fiber wait cuts off a third of all tasks; a bound that lets every task finish is about 5 min (the full-refresh flush), and even 2 min still interrupts the long derive steps. What this means for the decision: draining would make an upgrade wait up to ~5 min on a busy Norway box for the rare long task, against redoing at most that one task after the upgrade (interruption is crash-safe, STATBUS-264/265).

## History
- 2026-11-22T23:31 todo -> todo/design (ask)
- 2026-11-26T21:39 request 1 by jhf
- 2026-11-26T21:39 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:39 request 1 acknowledged by rabbit
- 2026-11-26T21:40 request 1 in progress by rabbit: hug task set rkfa4j
- 2026-11-26T21:40 resolved request 1 by rabbit
- 2026-11-27T11:04 request 2 by jhf
- 2026-11-27T11:04 request 2 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T11:05 request 3 by jhf
- 2026-11-27T11:05 request 3 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T15:39 request 4 by jhf
- 2026-11-27T15:39 request 4 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T15:39 request 4 acknowledged by rabbit
- 2026-11-27T15:40 request 4 in progress by rabbit: hug task note rkfa4j "2026-11-27 rabbit, measured on the Norway copy (local slot), 6 858 worker tasks 2026-11-15..27 (tmp/rkfa4j-task-duratio…"
