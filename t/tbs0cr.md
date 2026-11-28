---
id: tbs0cr
title: "Upgrade Now says what the worker is doing and asks to interrupt it"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-28
updated: 2026-11-28
---

## Goal
When the worker is busy, Upgrade Now's confirm dialog names the running work and needs an explicit tick to interrupt it.

## Purpose
An upgrade stops the worker, so a running recalculation or import is interrupted and starts over afterwards. Today the dialog says only that the system goes briefly into maintenance, so an admin can unknowingly throw away 40 minutes of recalculation on Norway's data.

## Principle
Inform, then let the person decide: the upgrade never waits on its own and never refuses. One choice only: go ahead anyway, or cancel and press Upgrade Now later. Nothing to undo afterwards: an interrupted task rolls back and reruns. The upgrade log names what it interrupted.

## Details
Dialog: app/src/app/admin/upgrades/page.tsx, the AlertDialog 'Confirm Upgrade' (around line 1570), Proceed calls scheduleNow (upgrade_schedule RPC). Worker state is in the app already (app/src/atoms/worker_status.ts: is_importing, is_deriving_statistical_units, is_deriving_reports, with phase progress); the running task's start time and name come from worker.tasks state processing. The upgrader's step 3 stops app, worker, rest (cli/internal/upgrade/service.go ~8847); its log line names the interrupted task. Scheduling for later does not exist yet; out of scope. Owner 2026-11-28.

## Depends on

## Acceptance
- [ ] With the worker recalculating, the dialog says what runs and since when (e.g. 'The worker is recalculating statistical units, started 13:51'), and Proceed stays disabled until 'Upgrade anyway, the work restarts afterwards' is ticked; jest
- [ ] With the worker idle, the dialog is as today, with no tick
- [ ] The upgrade log has a main line naming the task it interrupts and how long it had run, or that the worker was idle
- [ ] Observed on a slot: start a recalculation, Upgrade Now shows the notice, ticking and proceeding upgrades, and the recalculation reruns and completes after

## Notes
