---
id: STATBUS-099
title: >-
  legacy-scenario-sweep: delete legacy install-recovery scenarios that test
  product-impossible states
status: Done
assignee: []
created_date: '2026-06-19 11:05'
updated_date: '2026-06-21 20:15'
labels: []
dependencies: []
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOLLOW-UP from STATBUS-071 step-5 (foreman, 2026-06-19). The arc framework empirically proved the legacy scenario test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh tests a PRODUCT-IMPOSSIBLE state: a "process killed twice during the post-swap resume -> must not loop" case. The real product's STATBUS-067 self-heal canary (resumePostSwap, service.go:5053) + the one-shot Resuming latch doubly prevent the two-run resume-re-kill, so the failure it asserts cannot occur. The legacy header (line 59) admits it was "never run on real systemd" -- which is why the impossible assumption was never caught. The arc reshape was the first real execution -> RED (resume completed, NRestarts=0, no kill) -> diagnosed -> the arc scenario deleted/subsumed (C8 container-restart-kill covers the real resume-death + latch-no-loop contract).

KING DOCTRINE: a fabricated test describing a state that CANNOT occur -> DELETE it.

SCOPE: (1) Delete the legacy 3-postswap-resume-died-rollback.sh + its run.sh entry + README reference. (2) Audit the other legacy install-recovery scenarios for similar untested/fabricated assumptions ("never run on real systemd" headers; fabricated crash states the real product prevents) as part of retiring the legacy harness in favour of the arc harness.

OWNER: architect (audit) -> engineer (delete) -> foreman (commit). NOT blocking the step-5 arc reshape (separate harness); the legacy-harness retirement tail, distinct from the arc fabricate-retirement (AC3/AC4). Run by King's prioritization.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
resume-died + archivebackup-resume deleted (doc-016); deterministic-error + checkout-kill-legacy remain
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed 2026-06-21 (King-directed backlog-currency pass; folded into STATBUS-071). The legacy-scenario sweep happens inside 071's kill-family reshape — each product-impossible scenario is deleted as a real arc subsumes it, per the King's doctrine "a fabricated test describing a state that can't occur → DELETE."

DONE: 3-postswap-resume-died-rollback + 3-postswap-archivebackup-resume deleted (doc-016 — self-heal-blocked, subsumed by the C8 container-restart-kill arc); the standalone 4-rollback-restore-watchdog retired (5c-hard — its harness can't drive a real failure, subsumed by the rollback-restore arc).

REMAINING (= 071's 5d): the deterministic-error delete (subsumed by the failing arc) + the checkout-kill-legacy delete (superseded by the reshaped preswap-checkout-kill arc) + the worker-ddl-deadlock assess. All tracked in 071's coverage map + the 5d dispatch note. No separate sweep ticket needed.
<!-- SECTION:FINAL_SUMMARY:END -->
