---
id: STATBUS-612
title: Recalculation progress moves in the navbar while refresh batches finish
status: Done
assignee:
  - hibiscus
created_date: '2026-11-10T22:31:00Z'
updated_date: '2026-11-10T23:09:00Z'
labels:
  - bug
  - app
dependencies: []
type: bug
ordinal: 526204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The navbar's Statistical Units bar has no percentage during a full recalculation on rune rc.01. The worker sends a pipeline_progress notification after each refresh batch, a median 130 ms apart on the full register (3,162 batches, 102 gaps over 500 ms). The app's database listener relays worker_status notifications through a 500 ms trailing debounce that restarts on every arrival, so a steady stream reaches no browser until it pauses. The relay delivers the newest payload once per window instead, so progress moves while batches finish.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A steady stream of pipeline_progress notifications 100 ms apart for 5 s reaches subscribers 10 times, each with the newest completed count (app/src/lib/db-listener.test.ts)
- [x] #2 A phase's idle status is delivered after its last progress in the same window
- [x] #3 A local recalculation on the dev server shows a moving Statistical Units percentage
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Diagnosis 2026-11-10: DB side publishes total/completed/step correctly. Measured on import_benchmark_64469's last recalculation: refresh-batch completions median 130 ms apart (3,162 completions, 102 gaps >= 500 ms over 566 s); history partitions 24 ms; facet partitions 27 ms. The 500 ms trailing debounce in db-listener.ts restarted on each arrival. RED: new test delivered 0 of 10 expected updates (tmp/605/progress-red.log). GREEN with relayLatest throttle: 3/3 (tmp/605/progress-green.log).

Live check on this checkout's dev server (port 3000, statbus_local), 46 pipeline_progress notifications 130 ms apart via pg_notify, SSE /api/sse/worker_status read with curl, server restarted per variant (tmp/605/progress-live.sh, dev-restart.sh): master listener delivered 1 event (completed 46, after the stream stopped); fixed listener delivered 12 (4, 8, ... 44, 46). Logs tmp/605/progress-live-{master,fixed}.log. tsc and eslint clean.

On master 8c4f3c704 (Rabbit fast-forward). CI at 8c4f3c704 all completed/success: Fast Tests 42917418020, Go Test 42916708675, app build & lint 42916708666, Images 42916708804, Harness Selftest 42916708812, Push on master 42916708349.
<!-- SECTION:NOTES:END -->
