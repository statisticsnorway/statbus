---
id: STATBUS-299
title: >-
  watchdog-covers-initial-discover: a transient db outage at daemon start is
  killed as a deadlock — the one uncovered call site
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-28 13:12'
updated_date: '2026-08-28 13:18'
labels:
  - upgrade
  - cli
dependencies: []
priority: high
type: bug
ordinal: 292000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a transient database outage must never be treated as a daemon deadlock. Today, at exactly one call site, it is: systemd's watchdog SIGABRTs a healthy upgrade service that is doing a deliberately bounded reconnect — the daemon is killed for surviving the outage correctly.

THE MECHANISM, from rc.15's journal (fleet run 33163032285, transient-db-backoff; captured by 296's diagnostics): the scenario pauses the db. The daemon handles it correctly end to end — bounded backoff (attempts 1-6, budget 1m0s), data-safe park refusal, 294's listener going deaf-but-alive with its loud announce line — and then, 120 seconds later to the second, "Watchdog timeout (limit 2min)! Killing process (sb) with signal SIGABRT". The stack at the kill: main goroutine blocked in connect() ← reconnect() ← ensureConnected() ← discover() ← Run() (service.go:3804/3865/3853/4079/2430), deep in pgx's connectOne/peekMessage — a live network read against the still-paused db.

WHY THE HOLE EXISTS — two correct designs meeting at one uncovered site: connect() bounds itself to connectTimeout = 5 minutes (service.go:3703). Run()'s steady-state heartbeat deliberately runs ON the main goroutine (its own comment: a separate ticker would keep pinging systemd through a real deadlock, making the hang invisible — a hung main goroutine must stop heartbeating so systemd kills it). Every OTHER long-running phase has its own dedicated WATCHDOG=1 ticker goroutine — six sites counted. But the INITIAL discover() runs synchronously BEFORE the select loop starts (service.go:2437-2438), so the heartbeat never gets a chance to fire, and a transient outage lasting longer than 120s reads exactly like a deadlock. The 5-minute reconnect bound and the deliberate on-main-goroutine heartbeat are each correct in isolation; together at this one call site they leave a ~118-second-wide hole in which a recoverable outage kills the daemon.

WHY IT MATTERS: this is the exact class the transient-db-backoff scenario exists to prove cannot happen — a box that rides out a db blip. On an NSO box, a 2+ minute db hiccup at daemon start (host reboot ordering, slow disk, container restart) means the upgrade service dies by SIGABRT and restarts, possibly repeatedly, instead of simply waiting out the blip inside its already-designed 5-minute budget.

FIX SHAPE, architect to rule (the tension is with a DELIBERATE design): the initial discover needs watchdog cover that does not defeat the hung-main-goroutine detection the on-main-thread heartbeat exists for. The obvious shape is the file's own established pattern — a dedicated bounded WATCHDOG ticker goroutine scoped to exactly the initial-discover phase, like the six existing sites — but the architect should rule whether reconnect-with-cover is distinguishable enough from hang (the reconnect loop can prove liveness by its own attempts; a ticker pinging on attempt-progress rather than time would heartbeat only while the loop demonstrably advances).

EVIDENCE STATUS: 294's fix is CONFIRMED WORKING by this same journal (announce line present, clean listener shutdown, no panic anywhere). The upstream backoff-and-park logic is confirmed correct. The bug is only the missing cover at the first discover.

WHAT IS ACHIEVED: a db blip at daemon start is ridden out inside the existing 5-minute budget, the watchdog still catches real deadlocks, and the scenario built to prove this passes because it is true.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-28 13:18
---
RULING, with a verification that reshaped the options: reconnect (:3866) calls connect EXACTLY ONCE — no loop — and connectTimeout bounds that single call. So the initial discover contains ONE attempt, which refutes three candidates outright: attempt-progress cover AS ASSUMED (would ping once then go silent five minutes — indistinguishable from the hang it detects); moving discovery into the select loop (the heartbeat lives on the main goroutine — a 5-minute blocking call on that goroutine stops it wherever it sits; the problem is not ordering but that a call outlasting WatchdogSec lives on the heartbeat's goroutine at all); shrinking the bound below WatchdogSec (the ride-out must survive 180s and the watchdog fires at 120s — no single-attempt design satisfies both, which is exactly why this intersection was uncovered).

THE RULING: the mechanic's INSIGHT is right — a heartbeat must attest to PROGRESS, not the passage of time — so give it the retry loop it presumes. Restructure the initial connect into bounded sub-attempts: per-attempt timeout ≈30s (well under WatchdogSec, so a genuinely wedged attempt stops pinging and real-hang detection is PRESERVED inside the covered phase); total budget unchanged at 5 minutes (the 180s ride-out and 3-postswap-watchdog-reconnect survive untouched); WATCHDOG=1 pinged on each attempt boundary, never on a timer. This is better engineering independent of the watchdog: a single 5-minute attempt takes 5 minutes to report ANY failure; bounded retries report the first failure in seconds with the same patience overall — we are not bending the connection design to the watchdog, we are fixing a connection design that was already too coarse, and the cover falls out of it. Raising WatchdogSec stays rejected (weakens real-deadlock detection everywhere).

rc.16: CUT WITHOUT 299, with 297+300 aboard — the run's purpose is validating those two, not promoting. 299's production impact is bounded (transient window; systemd's restart is the correct response; noisy, not dangerous — unlike 297's crash-loop where retrying could never help). ONE CONDITION, not ceremony: PRE-DECLARE IN WRITING before the run that transient-db-backoff is expected to red, with cause and ticket — a predicted red recorded in advance stays a prediction confirmed; the same red explained afterwards is how a team learns to accept reds, and this project has no flaky tests. Pre-declaration is what keeps that rule intact while knowingly running a red.

STAFFING: engineer (holds the file from 294; connection-path restructure with watchdog interaction, not mechanical). Mechanic keeps 300.
---
<!-- COMMENTS:END -->
