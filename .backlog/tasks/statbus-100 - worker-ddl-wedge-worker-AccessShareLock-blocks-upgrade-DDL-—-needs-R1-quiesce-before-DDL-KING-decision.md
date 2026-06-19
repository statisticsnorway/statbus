---
id: STATBUS-100
title: >-
  worker-ddl-wedge: worker AccessShareLock blocks upgrade DDL — needs R1
  quiesce-before-DDL (KING decision)
status: To Do
assignee: []
created_date: '2026-06-19 11:43'
labels: []
dependencies: []
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING-FLAG from STATBUS-071 step-5d (architect-judged, foreman-surfaced, 2026-06-19). The worker-ddl-deadlock CAT-C scenario reproduces a REAL product gap, but its PASS needs a PRODUCT fix that is beyond the §9(5) charter — so the King decides implement-vs-document.

THE GAP (real, reproducible): during an upgrade, a worker process holding an AccessShareLock on statistical_history (or another base table) blocks the upgrade's schema-change DDL indefinitely (the DDL needs an AccessExclusiveLock) → the upgrade WEDGES (hangs until the worker releases, which under load may be never). This is the 40h-wedge-class shape on the worker↔migrate axis. The arc fixture (worker holds a table lock + a deadlocking migration) is IN-CHARTER + reproduces it.

WHY IT NEEDS A PRODUCT FIX (R1): the scenario's GREEN requires the product to QUIESCE the services (stop the worker) BEFORE running the upgrade DDL (R1: quiesce-services-before-DDL). R1 is NOT implemented → the scenario is "LIKELY RED" as-is. So unlike the rest of the §9(5) reshape (test-only), worker-ddl's PASS depends on a real PRODUCT change.

KING DECISION:
- (A) IMPLEMENT R1 (quiesce-services-before-DDL) now → the product handles the worker-DDL wedge + the scenario passes. Closes a real wedge hole (Albania-relevant: an unattended box could wedge on this). Product work, scoped separately.
- (B) DOCUMENT-THE-GAP → defer R1; the worker-ddl scenario stays HELD/skipped with a known-gap note in doc-017; revisit when R1 is prioritized.

OWNER: King decides (A vs B). If A → architect designs R1 + the scenario; engineer implements; foreman commits + VM-proves. If B → document + hold. NOT blocking the §9(5) arc reshape (worker-ddl is one held scenario; the other CAT-C mechanisms + 5e proceed). This is the charter value again — the framework surfaced a real product gap before it could wedge a customer.
<!-- SECTION:DESCRIPTION:END -->
