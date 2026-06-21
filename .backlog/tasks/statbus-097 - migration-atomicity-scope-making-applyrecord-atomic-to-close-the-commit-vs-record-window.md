---
id: STATBUS-097
title: >-
  torn-window-recovery: atomicity RETIRED — rolled_back per 013 is the recovery,
  no build
status: Done
assignee: []
created_date: '2026-06-18 21:36'
updated_date: '2026-06-21 17:28'
labels:
  - upgrade
  - migration
  - design-scoping
dependencies: []
priority: high
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RETIRED (King, 2026-06-21). Atomicity (making apply+record atomic) is NOT the fix and is NOT built.

The correct recovery is STATBUS-013's verbatim spec: a crash in the commit↔record gap → recovery re-runs → "relation already exists" → the product has NO safe way to reconcile a half-applied-but-unrecorded migration → it RESTORES the pre-upgrade backup and marks the upgrade ROLLED_BACK → cleanly on the OLD version → operator retries. The rollback IS the recovery.

Atomicity would only AVOID that one rollback (efficiency) on a sub-millisecond, near-never crash. Its cost — every migration → pure DDL with the runner owning the transaction; a convention enforced forever; a new failure mode if a future migration forgets it; a one-time transition of ~359 migrations — dwarfs the benefit. RETIRED: runner-owns-tx, the self-record convention, the inject-before-END, the SQL-lint. None built.

The remaining real question is NOT atomicity — it is recovery-CORRECTNESS: does the box ACTUALLY reach rolled_back per 013, or did it deviate to 'completed' (overnight observation)? That lives in STATBUS-105. This task is closed: atomicity is not the path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Atomicity confirmed NOT the fix and not built (runner-owns-tx / self-record / inject / lint all retired)
- [ ] #2 Recovery is STATBUS-013's restore → rolled_back; the recovery-correctness verification moved to STATBUS-105
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed without a product change. The committed-but-unrecorded ("torn") window does not need atomicity: STATBUS-013's spec already defines the correct recovery — restore the pre-upgrade backup and end rolled_back (operator retries). Atomicity is only an efficiency optimization on a near-never crash and is not worth its permanent cost. Retired the whole atomicity line (runner-owns-tx, self-record convention, inject-before-END, SQL-lint). The open recovery-correctness question — does the box honor 013's rolled_back, or deviate to completed — is tracked in STATBUS-105, not here.
<!-- SECTION:FINAL_SUMMARY:END -->
