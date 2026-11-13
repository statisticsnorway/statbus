---
id: STATBUS-612
title: Recalculation progress moves in the navbar while refresh batches finish
status: Done
assignee:
  - hibiscus
created_date: '2026-11-10T22:31:00Z'
updated_date: '2026-11-13T12:06:00Z'
labels:
  - bug
  - app
dependencies: []
type: bug
ordinal: 526204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
While the worker recalculates, the navbar shows how far it has come, so a user can see the work moving and roughly when it ends.

## Zoom out
A relay that waits for quiet before speaking never speaks during a steady stream. Progress must reach the browser at a steady rate while the stream lasts, carrying the newest state, and the final state must arrive last.

## Zoom in
- The worker sends a pipeline_progress notification after each refresh batch, a median 130 ms apart on the full register (3,162 completions, 102 gaps over 500 ms).
- app/src/lib/db-listener.ts relayed worker_status through a 500 ms trailing debounce that restarted on every arrival, so no progress reached any browser until the stream paused. Seen by the owner on rune rc.01 as a Statistical Units bar without a percentage.
- The relay now delivers the newest payload per key once per window, in last-arrival order, for worker_status, import_job_progress and worker_task_changed.

## Closing review
No memory or documentation change needed; the relay's purpose is stated at relayLatest's definition.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A steady stream of pipeline_progress notifications 100 ms apart for 5 s reaches subscribers 10 times, each with the newest completed count (app/src/lib/db-listener.test.ts)
- [x] #2 A local recalculation on the dev server shows a moving Statistical Units percentage
- [x] #3 A phase's idle status sent right after its last progress reaches subscribers after that progress, in the same window (db-listener.test.ts, 'delivers a phase's idle status after its last progress' passes)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Diagnosis 2026-11-10: DB side publishes total/completed/step correctly. Measured on import_benchmark_64469's last recalculation: refresh-batch completions median 130 ms apart (3,162 completions, 102 gaps >= 500 ms over 566 s); history partitions 24 ms; facet partitions 27 ms. The 500 ms trailing debounce in db-listener.ts restarted on each arrival. RED: new test delivered 0 of 10 expected updates (tmp/605/progress-red.log). GREEN with relayLatest throttle: 3/3 (tmp/605/progress-green.log).

Live check on this checkout's dev server (port 3000, statbus_local), 46 pipeline_progress notifications 130 ms apart via pg_notify, SSE /api/sse/worker_status read with curl, server restarted per variant (tmp/605/progress-live.sh, dev-restart.sh): master listener delivered 1 event (completed 46, after the stream stopped); fixed listener delivered 12 (4, 8, ... 44, 46). Logs tmp/605/progress-live-{master,fixed}.log. tsc and eslint clean.

On master 8c4f3c704 (Rabbit fast-forward). CI at 8c4f3c704 all completed/success: Fast Tests 42917418020, Go Test 42916708675, app build & lint 42916708666, Images 42916708804, Harness Selftest 42916708812, Push on master 42916708349.

Browser acceptance 2026-11-13 11:42-12:06 UTC (owner request, his Firefox): import_benchmark_64469 (full register, 3,118,352 statistical units) migrated to master a2a176e3d and served by the local https dev stack (https://local.statbus.org:3011, logged in as test.admin). Full recalculation through the real worker, 451 refresh batches, 973 tasks, 0 failed, 11:43:03-12:05:16 (22 min). Navbar Statistical Units fill read from the DOM: 2% at 6/451 batches, 4% at 43/451, 30% at 217/451; SSE pipeline_progress events carried completed/total live (e.g. 8/451); back to idle (no fill) after completion. Local stack restored to statbus_local afterwards. Logs tmp/605/navbar-*.
<!-- SECTION:NOTES:END -->
