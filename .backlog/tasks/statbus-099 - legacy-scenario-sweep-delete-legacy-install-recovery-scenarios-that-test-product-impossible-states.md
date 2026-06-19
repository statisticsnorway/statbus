---
id: STATBUS-099
title: >-
  legacy-scenario-sweep: delete legacy install-recovery scenarios that test
  product-impossible states
status: To Do
assignee: []
created_date: '2026-06-19 11:05'
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
