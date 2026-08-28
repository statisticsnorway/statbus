---
id: STATBUS-299
title: >-
  watchdog-covers-initial-discover: a transient db outage at daemon start is
  killed as a deadlock — the one uncovered call site
status: To Do
assignee: []
created_date: '2026-08-28 13:12'
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
