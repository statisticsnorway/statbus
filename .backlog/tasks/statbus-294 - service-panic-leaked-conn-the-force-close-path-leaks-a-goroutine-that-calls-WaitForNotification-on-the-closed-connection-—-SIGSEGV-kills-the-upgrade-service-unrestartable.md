---
id: STATBUS-294
title: >-
  service-panic-leaked-conn: the force-close path leaks a goroutine that calls
  WaitForNotification on the closed connection — SIGSEGV kills the upgrade
  service unrestartable
status: To Do
assignee: []
created_date: '2026-08-27 23:41'
updated_date: '2026-08-28 07:02'
labels:
  - upgrade
  - cli
dependencies: []
priority: high
type: bug
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during the rc.11 chain diagnosis (2026-08-28, arc transient-db-backoff, run 33115731212): the upgrade service's force-close path (service.go:2612-2618) gives up on a connection close after 10s and — per its own comment — 'leaks the goroutine and continues'. The leaked goroutine then calls d.listenConn.WaitForNotification(ctx) at service.go:2625 on the closed/nil connection → SIGSEGV nil dereference → the whole service panics and dies. In the observed run systemd could not restart it ('cannot start a paused container'), so no terminal upgrade state was ever recorded — the box wedged with its upgrade row non-terminal.

Adjacent smell at the same site, fix or ticket alongside: 'retention: plan query failed (scope=all, installed=0xc000013240)' prints a POINTER where a value belongs — a %v on a *T that should be dereferenced or formatted.

Historical note: this panic path predates rc.11 (the code is old) and manifested rarely — the scenario was green at the Aug-19 run. It surfaced tonight under the phantom-candidate load produced by STATBUS-293's comparison bug, and may return to dormancy once 293 lands; dormant is not fixed. The deliberate leak-and-continue was itself the what-must-survive-a-failure trap: the leaked goroutine held a reference into the thing that was being torn down.

Fix shape (engineer proposes at build): the leaked goroutine must never touch the connection after the close decision — either the close path signals it (context cancellation it actually honors before the WaitForNotification call) or the goroutine owns the connection lifecycle entirely; and the service should treat a listener-goroutine panic as recoverable (recover + re-establish listen) rather than process-fatal, since a dead upgrade service is the silent-wedge class (262) all over again.

WHAT IS ACHIEVED: no connection teardown can kill the upgrade service, and a listener failure degrades loudly instead of wedging the box silently.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-28 07:02
---
GROUNDED FROM BYTES (King-directed re-verification; stack trace from arc run 33115731212 was still retrievable and is quoted below). Four of the ticket's five causal links VERIFY; the fifth is REFUTED.

THE ISSUE, plain: the stop path force-closes the listener conn (service.go:2599-2603), cancels its context (:2605), waits at most 10s and on timeout RETURNS ANYWAY — comment says 'leaking goroutine and continuing' (:2612-2619). The upgrade path then sets the SHARED field d.listenConn = nil (:5981-5985, called from :5979). The abandoned listener reads that shared field ON EVERY ITERATION (:2625) — not a conn it holds — so its next pass calls WaitForNotification on nil and dies in pgx v5.9.2 conn.go:419, the function's first field access (stack: SIGSEGV addr=0x90, +0x1c — freshly entered, so the listener had LOOPED, delivered one notification at :2632, and re-read the emptied field; addr=0x90 = field offset from a nil base, pinning EMPTIED not closed). Two parts of the program disagree about who owns the connection: one abandons it, the other keeps using it. Also an unsynchronised data race on d.listenConn (write at :5984 vs read at :2625).

REFUTED: 'service unrestartable' is WRONG — the same log shows status=2/INVALIDARGUMENT then 'Scheduled restart job, restart counter is at 1': systemd DID restart it. What failed was 'cannot start a paused container' — that scenario deliberately pauses the DB; unrelated cause. The crash and the failure-to-recover are two different problems the ticket merged. Also corrected: 'calls on the CLOSED conn' → closed would return an error; the crash requires the field EMPTIED at :5984.

SECOND SMELL LOCATED: exec.go:1019, :1057, :1060 — installed=%v applied to installedID *int prints the ADDRESS (installed=0xc000013240); print the value (<nil> when absent).

THE FIX, exact and mechanical (2 files, no further design decision): (1) OWNERSHIP — startListenLoop (:2557-2569) reads d.listenConn into a local and passes it as a parameter; listenLoop (:2622-2635) uses the parameter at :2625 and returns if handed nil. An abandoned listener then holds a conn that is only ever CLOSED, never emptied — WaitForNotification returns an error and the existing error branch (:2626-2628) already exits cleanly with context cancelled. Crash impossible by construction; race gone because the abandoned listener stops touching shared state. (2) the sends at :2630/:2632 become select with <-ctx.Done() so an abandoned listener can't block forever handing a notification to a reader that no longer exists (leak, not crash — same ownership confusion). (3) exec.go three sites: dereference-or-<nil> formatting.

TICKET'S PROPOSED FIX REJECTED: recover-and-relisten treats the symptom, would restart a listener on a conn the upgrade closed ON PURPOSE (re-creating the confusion), and cannot restore the one-listener-at-a-time rule. Fix (1) is smaller and removes the possibility instead of catching it.
---
<!-- COMMENTS:END -->
