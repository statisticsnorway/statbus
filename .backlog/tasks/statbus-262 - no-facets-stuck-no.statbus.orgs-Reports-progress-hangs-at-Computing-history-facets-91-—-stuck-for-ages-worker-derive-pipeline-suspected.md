---
id: STATBUS-262
title: >-
  no-facets-stuck: no.statbus.org's Reports progress hangs at "Computing history
  facets 91%" — stuck for ages, worker derive pipeline suspected
status: To Do
assignee: []
created_date: '2026-08-27 12:35'
updated_date: '2026-08-27 12:36'
labels:
  - worker
  - production
  - norway
dependencies: []
priority: high
type: bug
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by the King 2026-08-27 with a screenshot of no.statbus.org: the Reports dropdown shows "Reports Progress — Handle ~1 legal units, ~1 enterprises — Computing history facets 91%" and has been sitting there "for ages".

no.statbus.org is the Norway box — the HUMAN CANARY (prerelease channel, deliberately installed candidates against an observation card), slot `no` on niue (offset 3). A hang on the human canary is exactly the kind of observation that box exists to produce: whatever candidate it runs may carry a worker defect that the chain-driven dev box did not surface.

"Computing history facets" is worker derive-pipeline territory (doc/derive-pipeline.md; structured concurrency per doc/worker-structured-concurrency.md — ONE top-level task per queue, top fiber blocks until all children complete). A progress stuck at 91% for a long period means a derive child task is hung, crash-looping, or dead with the parent still waiting — or the progress reporting itself is stale while work completed/failed underneath.

INVESTIGATION (read-only, via operator): worker.tasks state distribution, the non-completed tasks and their ages/errors, worker container status and log tail, and which version the box is running (it is the human canary — the candidate identity is part of the diagnosis).

Note the oddity in the banner itself: "~1 legal units, ~1 enterprises" — a tiny unit count with a facets computation that cannot finish suggests either a pathological task on trivial data (loop/deadlock rather than volume) or a progress denominator bug.

WHAT IS ACHIEVED: the hang is diagnosed to a named cause on a named version, the fix ships as code through the normal path, and the human canary's observation card gains whatever check would have caught this earlier.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 12:36
---
KING'S ADMIN-UI EVIDENCE (screenshots, no.statbus.org/admin/worker-tasks, 2026-08-27): task chain Recording changes #646207 → Deriving reports #646212 (waiting, serial) → children 646213 statistical history COMPLETED, 646214 history_reduce COMPLETED, 646215 search facets COMPLETED, 646216 merge search facets COMPLETED, 646217 Computing history facets WAITING (concurrent, 8.2s, "1280 children"), 646218 Merging history facets PENDING. Inside #646217: ALL 1280 `derive_statistical_history_facet_period` children COMPLETED (pages 1 and 26-of-26 both verified green, durations 400ms–1m30s, ~12k rows each), created 7 days ago.

READING: nothing is running and nothing is slow — every child is done and the parent never transitioned. A LOST WAKEUP: under structured concurrency a waiting parent with all children complete must complete and release the next serial task (the merge, still pending). The stuck "91%" is the pipeline fully done except the parent's own bookkeeping and the un-started merge.

HYPOTHESIS (labelled as such): 7 days ago ≈ 2026-08-20; if a candidate was deliberately installed on the human canary that day, the worker restarted mid-derive — children completed around the restart window, the parent's wake signal died with the old process, and resume-on-startup does not re-examine waiting parents whose children are ALL already complete. To confirm: operator's DB reads (exact states/timestamps of 646212/646217/646218 and last-child completion vs worker restart time in logs), then root-cause in the worker's resume path.
---
<!-- COMMENTS:END -->
