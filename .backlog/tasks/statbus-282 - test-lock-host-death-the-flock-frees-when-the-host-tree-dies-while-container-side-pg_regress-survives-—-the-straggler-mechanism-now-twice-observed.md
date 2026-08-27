---
id: STATBUS-282
title: >-
  test-lock-host-death: the flock frees when the host tree dies while
  container-side pg_regress survives — the straggler mechanism, now
  twice-observed
status: To Do
assignee: []
created_date: '2026-08-27 16:44'
labels:
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 275000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Twice-observed mechanism (May's straggler that corrupted the King's 105 run; the engineer's harness-killed suite 2026-08-27 leaving pid 92456 walking the full list): the test-run flock releases when the HOST process tree dies, but the CONTAINER-side pg_regress does not inherit that fd and outlives it — so the lock reports free while a writer still walks the shared --outputdir. The next run would race it into NUL corruption; today only check_no_straggler_pg_regress (lock-acquisition-time) stands between.

The guard held both times it was consulted — the gap is that lock-freedom and writer-absence are different facts. Design question for the architect: should the lock's holder be (or include) the container-side process — e.g. the lock releases only when the db container confirms no pg_regress remains (fold the straggler check into release rather than only acquisition), or the runner wraps pg_regress so a host death tears down the container-side process group? Also the operational half: teammate harness timeouts have now killed a long suite mid-run — long test runs need an invocation that outlives session limits (detached tmux, as vm-bootstrap itself uses).

WHAT IS ACHIEVED: a dead host run cannot leave a live writer behind a free lock, and long suites survive their operator's session limits.
<!-- SECTION:DESCRIPTION:END -->
