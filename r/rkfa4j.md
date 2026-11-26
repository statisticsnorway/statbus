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
priority: medium
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

## History
- 2026-11-22T23:31 todo -> todo/design (ask)
- 2026-11-26T21:39 request 1 by jhf
- 2026-11-26T21:39 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:39 request 1 acknowledged by rabbit
- 2026-11-26T21:40 request 1 in progress by rabbit: hug task set rkfa4j
