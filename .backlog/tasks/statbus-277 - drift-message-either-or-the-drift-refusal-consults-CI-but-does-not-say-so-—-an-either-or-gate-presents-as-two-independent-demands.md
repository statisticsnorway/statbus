---
id: STATBUS-277
title: >-
  drift-message-either-or: the drift refusal consults CI but does not say so —
  an either/or gate presents as two independent demands
status: To Do
assignee: []
created_date: '2026-08-27 15:02'
labels:
  - release
dependencies: []
priority: medium
type: enhancement
ordinal: 270000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's observation at the rc.10 cut, minutes after the drift-oracle escape landed: with CI still pending at the tip, the drift check printed its old refusal ("Fix: ./dev.sh migrate-and-test fast") with no mention that it had consulted the pg_regress workflow and found it pending — so the local and remote proofs read as BOTH required when the landed logic is either/or.

Fix, in the refusal branch only (the pass paths already announce themselves): when the escape was consulted and declined, the refusal says both sides and the disjunction — "local stamp is stale AND pg_regress is not green at HEAD (status: pending, run: <URL>); either a green CI run at this commit or the local run below satisfies this check." Include the run URL/status the oracle saw (checkWorkflowAtCommit already has it). Retarget any message-asserting tests; the logic does not change.

WHAT IS ACHIEVED: the operator standing at a refusal knows exactly which of the two acceptable proofs is missing and where the pending one is — no more apparent double-requirement.
<!-- SECTION:DESCRIPTION:END -->
