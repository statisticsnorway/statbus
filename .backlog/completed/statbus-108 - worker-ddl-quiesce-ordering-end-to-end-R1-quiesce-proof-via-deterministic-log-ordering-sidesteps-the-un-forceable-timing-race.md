---
id: STATBUS-108
title: >-
  worker-ddl-quiesce-ordering: end-to-end R1-quiesce proof via deterministic
  log-ordering (sidesteps the un-forceable timing race)
status: Done
assignee: []
created_date: '2026-06-21 21:32'
updated_date: '2026-07-06 15:58'
labels:
  - install-recovery
  - upgrade
  - recovery
  - follow-up
  - architect-plan
dependencies: []
references:
  - cli/cmd/install.go
  - cli/internal/upgrade/service.go
  - doc-017
priority: low
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
▶ LOW-PRI follow-up filed from STATBUS-071 5d-e (architect ruling 2026-06-21). NOT a 071 upgrade arc — install-recovery scope.

CONTEXT (why worker-ddl is a 5d-e DOCUMENTED RESIDUAL, not a built arc):
- R1's quiesce-before-DDL gate is install.go:633-655 (`compose.QuiesceClients` stops worker/app/rest before the Seed/Migrations DDL) — UNIT-covered (QuiesceClients).
- In 071's upgrade-arc framework the R1 quiesce is a NO-OP (service.go:4654-4665 — the preswap teardown at service.go:4207 already stopped the worker), so a worker-ddl UPGRADE arc is VACUOUS.
- The full lock-contention RED is UN-FORCEABLE: the worker holds AccessShareLock on statistical_history only during seconds-long statistical_history_reduce runs, with gaps → a timing race; doc-017 §4 forbids an inject to force it. A probabilistic test fails the no-flaky bar AND risks a FALSE-GREEN (a vacuous pass that didn't actually exercise R1 — worse than nothing). So 5d-e = honest documented residual (not faked, not flaky); the end-to-end gap is narrow (unit-covered).

THE FOLLOW-UP (a REAL deterministic proof, no inject, no race):
Assert that QuiesceClients runs BEFORE the DDL via LOG-ORDERING, on the INSTALL path:
- GREEN (current code): the install log shows the quiesce (stop worker/app/rest) ordered BEFORE the Seed/Migrations DDL.
- RED (an R1-removed build, the quiesce step deleted): no quiesce-before-DDL in the log order → deterministic RED.
- ANTI-VACUOUS: "worker active before install" — confirm via pg_locks that a worker session holds AccessShareLock on statistical_history before the install runs (so the gate has something real to quiesce).
This sidesteps the un-forceable wedge timing race entirely (it proves the ORDERING invariant, not the live lock conflict). Build IF/when end-to-end R1 coverage is wanted beyond the existing unit coverage.

REFERENCES: install.go:633-655 (R1 gate), service.go:4654-4665/:4207 (upgrade-path no-op), doc-017 §4 (worker-ddl design + the residual).
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSE (King ruling 2026-07-06). Not grounded in an observable problem the King can judge; reopen only when an ordering failure is actually observed.
<!-- SECTION:FINAL_SUMMARY:END -->
