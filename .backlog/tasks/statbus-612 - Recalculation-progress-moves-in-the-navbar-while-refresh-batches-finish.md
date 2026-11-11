---
id: STATBUS-612
title: Recalculation progress moves in the navbar while refresh batches finish
status: Done
assignee:
  - hibiscus
created_date: '2026-11-10T22:31:00Z'
updated_date: '2026-11-10T23:11:00Z'
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
<!-- SECTION:NOTES:END -->
