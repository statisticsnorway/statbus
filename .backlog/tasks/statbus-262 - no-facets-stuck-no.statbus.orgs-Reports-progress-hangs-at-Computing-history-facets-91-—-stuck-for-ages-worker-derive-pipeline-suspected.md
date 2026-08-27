---
id: STATBUS-262
title: >-
  no-facets-stuck: no.statbus.org's Reports progress hangs at "Computing history
  facets 91%" — stuck for ages, worker derive pipeline suspected
status: To Do
assignee: []
created_date: '2026-08-27 12:35'
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
