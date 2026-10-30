---
id: STATBUS-100
title: >-
  worker-ddl-wedge: worker AccessShareLock blocks upgrade DDL — needs R1
  quiesce-before-DDL (KING decision)
status: Done
assignee: []
created_date: '2026-06-19 11:43'
updated_date: '2026-06-19 14:14'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RESOLVED - ALREADY IMPLEMENTED (foreman-verified by direct code read, 2026-06-19). The worker-lock wedge fix EXISTS on both paths; STATBUS-100's not-implemented claim was a FALSE ALARM read off a stale legacy test-header (LIKELY RED @ commit 1f077e545) that predates the fix - the stale-legacy-vs-code trap this rework exists to flush. THE FIX = compose.QuiesceClients (cli/internal/compose/compose.go:126) stops clientServices={worker,app,rest} (compose.go:101 - the worker IS the AccessShareLock holder) before the DDL window, fail-loud. Both paths: INSTALL cli/cmd/install.go:676 ('[DDL] quiescing worker/app/rest before Seed/Migrations'); UPGRADE (autonomous service) cli/internal/upgrade/service.go:4663 in applyPostSwap, BEFORE the migrate DDL (:4751); comment :4654 explicitly covers the resumePostSwap re-entry; step 11 (:4784) restarts the clients after. Order: reconnect(:4633) -> quiesce(:4663) -> migrate-DDL(:4751) -> restart(:4784). Documented doc/upgrade-timeline.md:266 + :702. Nothing to build. The reshaped 5d worker-ddl arc becomes a positive regression-proof of this R1 fix (a normal GREEN-asserting CAT-C reshape), NOT a King-flag - doc-017 section 4 corrected accordingly.
<!-- SECTION:NOTES:END -->
