---
id: STATBUS-101
title: >-
  expect-red-guard: self-validating RED-build CI guard for the rollback-restore
  watchdog-cover (e)-gate
status: Done
assignee: []
created_date: '2026-06-19 13:02'
updated_date: '2026-07-06 15:59'
labels: []
dependencies: []
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOLLOW-UP (foreman, 2026-06-19, from STATBUS-071 step-5d rollback-restore). Hardening — NOT blocking CAT-B (the one-time RED-build run already proves the gate bites).

CONTEXT: the rollback-restore-watchdog arc's (e) gate proves the STATBUS-031 always-ping ticker covers rollback()'s restoreDatabase stall (delta-0 NRestarts bound). To prove the gate actually BITES a real regression, we run it once against the ticker-deleted RED build (base_sha=red/031-rollback-watchdog) → it must FAIL (the gate REDs). That's a one-time, foreman-interpreted proof (RED=success).

THE FOLLOW-UP (engineer's option b, ~10 lines): add an EXPECT_RED env to the arc that INVERTS the gate — RED-detected → exit 0 (GREEN); no-RED → exit 1. Then a run with base_sha=red/031-rollback-watchdog EXPECT_RED=1 shows GREEN, self-documenting + re-runnable (no foreman interpretation). Optionally wire it into the harness as a periodic/on-demand self-validating scenario so the watchdog-cover meta-test can't silently rot.

VALUE: a permanent, self-documenting proof that the watchdog-cover gate catches a watchdog-cover regression (guards against gate-rot). The no-vacuous-tests / gate-the-output-with-intent doctrine applied to the gate itself.

COST/TRADEOFF: ~10 lines for the EXPECT_RED env. A per-harness-run auto-matrix entry would add ~€0.01 + ~20min VM per run — so prefer on-demand/periodic over every-run unless the King wants the strongest guard. King decides scope (env-only + on-demand, vs auto-matrix).

OWNER: King prioritizes; if taken → engineer adds the EXPECT_RED env, foreman commits + fires the self-validating run. Pattern generalizes to the other watchdog/anti-vacuous gates (C15 reconnect, archivebackup, the CAT-C mechanisms).
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MERGED into STATBUS-071: a ~10-line self-validating RED-gate option for one of 071's arcs; belongs on the same hardening list.
<!-- SECTION:FINAL_SUMMARY:END -->
