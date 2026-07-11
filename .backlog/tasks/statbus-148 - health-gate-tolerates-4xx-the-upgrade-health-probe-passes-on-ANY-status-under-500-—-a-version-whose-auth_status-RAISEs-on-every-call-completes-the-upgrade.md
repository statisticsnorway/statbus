---
id: STATBUS-148
title: >-
  health-gate-tolerates-4xx: the upgrade health probe passes on ANY status under
  500 — a version whose auth_status RAISEs on every call completes the upgrade
status: Done
assignee: []
created_date: '2026-07-08 21:34'
updated_date: '2026-07-11 23:49'
labels:
  - upgrade
  - product
  - recovery
  - install-recovery
  - health
dependencies: []
references:
  - cli/internal/upgrade/exec.go
  - STATBUS-145
  - STATBUS-046
  - doc-029
  - doc-021
priority: high
ordinal: 149000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the upgrade health gate answers the question it was built to ask — "can the new version actually serve its users?" — not merely "does the HTTP stack respond".
> BENEFIT: a release whose core auth RPC fails on every call can no longer sail through the upgrade gate to 'completed'; it parks at-target with a named reason (the class-B health-past-warmup park, doc-021), which is the designed terminal for can't-serve.
> STAGE: Stage 1. FOUND BY: the health-park arc's first contact (2026-07-08) — the arc's deliberate break (auth_status RAISEs) passed the gate and B COMPLETED.
> COMPLEXITY: mechanic-simple once ruled (ruled below); the health-park arc re-dispatch is the oracle.
> DEPENDS ON: nothing. The health-park arc (doc-029) stays red until this lands — correctly: the red is THIS finding.

THE MECHANISM (code-certain, arc-confirmed): healthCheck's functional probe POSTs {} to /rpc/auth_status and PASSES on `resp.StatusCode < 500` (exec.go:1424). PostgREST maps a PL/pgSQL RAISE EXCEPTION (P0001) to HTTP 400. So a version whose auth_status raises on EVERY call — meaning every real frontend load fails auth resolution, the app is broken for all users — returns 400 → passes the gate → the upgrade COMPLETES. The arc's break could not fail the predicate by construction; the run proved it (B → completed, wave-1 run 2026-07-08, log tmp/health-park-run1-logs.txt). The predicate defeats the probe's own stated intent: the comment at :1418-1419 says the POST "matches what the frontend sends" — a functional probe chosen precisely to test more than transport, then gated as if it were a transport check.

RULED FIX (architect, 2026-07-08): tighten the FUNCTIONAL probe's success predicate to 2xx (resp.StatusCode >= 200 && < 300). Rationale: auth_status is anonymous-callable by design and returns 200 on every healthy deployment; any 4xx from it means real clients cannot authenticate — "cannot serve at <version> past warmup", the exact class-B park case (doc-021). The change composes with 145 correctly: at the health step the delta has applied, observed state reads at-target, so the failure routes to parkForDeterministicFailure → PARK with the health reason — never a wrong rollback. waitForRestReady (admin /ready, different port + purpose) is untouched. THE FALSE-FAIL RISK IS THE RUN'S TO ANSWER (the only oracle): the regression arcs that traverse healthCheck (happy install, working, failing, preswap set) re-prove the tightened predicate on real VMs; wave 1 just proved them green under <500, the re-run proves them green under 2xx.

DO NOT "fix" arc-side instead: V2 could RAISE with ERRCODE 'PT500' to force PostgREST to return 500 under the existing predicate — REFUSED: that would make the arc pass while MASKING this product gap (the gate would still tolerate every real 4xx-broken release).

ALSO IN SCOPE (harness rider, one line): the health-park arc's failure diagnostics must pull the upgrade PROGRESS log + the daemon journal for the B window before VM teardown — the wave-1 log contains zero "Health check attempt" lines, so the run could not distinguish predicate-pass from break-never-applied; only the code trace settled it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 healthCheck's functional probe passes ONLY on 2xx (exec.go:1424 predicate tightened); waitForRestReady untouched; unit test pins the matrix (200 pass; 400/401/404 fail; 503 fail; transport error fail)
- [x] #2 Health-park arc re-dispatched and GREEN: B parks at-target with the health-past-warmup reason, the full doc-029 substrate asserts, C completes — the arc is this fix's oracle
- [x] #3 Regression set re-proven under the tightened predicate on real VMs (happy install + working + failing + one preswap arc traverse healthCheck) — no false-fail
- [x] #4 Arc failure diagnostics capture the upgrade progress log + daemon journal for the upgrade window before teardown (the wave-1 gap: zero health-attempt lines in the captured log)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-08 23:54
---
WAVE-4 PROGRESS (run 28982749357, on 08a3c9471): THE PARK IS PROVEN — B parked at t+179s with 'HEALTHCHECK_REST_DOWN: the application cannot serve at 25b02ffe past warmup — health check failed after 5 attempts; last: status=400 body P0001 healthpark fixture' (log line 15476). The 2xx-only gate refused the 400 exactly as ruled; the first-contact red is gone. AC#1 shipped earlier (d8dea08b2); AC#4's diagnostics trap shipped with it and FIRED this wave — the captured journal is what settled the follow-on question (the arc's remaining red was RULED HARNESS TIMING: the assert fired 10s into systemd's 30s auto-restart hold-off, the designed park shape — parking pass exits 1, RestartSec=30, next boot is the parked-skip boot). Mechanic fixing the arc's settle entry (poll is-active ≤~90s before the frozen-NRestarts window; r19's poll-then-settle shape). AC#2 (full arc green: parked-skip lines, un-park→re-park two-siren contract, step-5 fix-release leg) and AC#3 (named regression set under 2xx) land on the next wave's re-dispatch. Ledger note from the journal: the resume pass runs the health probe TWICE per pass (self-heal canary's + applyPostSwap's own) — ~50s of 400s per pass, correct behavior, remember when reading park timings.
---

author: foreman
created: 2026-07-09 00:53
---
WAVE-5 (run 28984873852): AC#3 CHECKED — the regression set is re-proven under the 2xx predicate on real VMs: working GREEN, failing GREEN (health check explicitly logged passing at attempt 1 code=200), preswap-checkout-kill GREEN, and every arc's A-install (the happy path) traversed healthCheck green. No false-fail anywhere. AC#2 (health-park full green) is now BLOCKED BY STATBUS-154 — the arc's third red is a third distinct real finding: the un-park→re-park leg re-parked genuinely but the park's DB write failed on the daemon's own teardown context (parked-in-log, parked=f in the row). The arc red is correct and stays red until 154's fix lands; 148's own gate behavior is fully proven (the park fired with the right reason on every attempt — the journal shows HEALTHCHECK_REST_DOWN parks throughout).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED on wave 10 (run 29171998401, 2026-07-12) — AC#2's oracle landed: the health-park arc went fully green. B parked at-target with the health-past-warmup reason (the 2xx-only gate refusing the 400 that used to sail through), the full doc-029 substrate asserted (settle, bounds, siren-once, parked-skip boots, un-park, re-park with second siren), and C — a genuine fix release — completed with data intact. The fix itself: healthCheck's functional probe passes only on 2xx (d8dea08b2, AC#1 with the unit-test matrix); the park with the named HEALTHCHECK_REST_DOWN reason was first proven wave 4 (run 28982749357); the regression set re-proved no false-fail under the tightened predicate on real VMs wave 5 (AC#3); the diagnostics rider (AC#4) shipped with the fix and earned its keep repeatedly — waves 4-9's diagnoses all read from the logs it captures. The arc stayed red through waves 5-9 because it kept catching REAL upstream findings (154's teardown race and invisible writer, 159's parked-blocks-claim) — the gate finding this ticket named was proven fixed from wave 4 onward.
<!-- SECTION:FINAL_SUMMARY:END -->
