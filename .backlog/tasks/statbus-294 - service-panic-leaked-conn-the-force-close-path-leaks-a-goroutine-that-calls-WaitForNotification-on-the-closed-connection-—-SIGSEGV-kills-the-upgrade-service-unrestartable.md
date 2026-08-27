---
id: STATBUS-294
title: >-
  service-panic-leaked-conn: the force-close path leaks a goroutine that calls
  WaitForNotification on the closed connection — SIGSEGV kills the upgrade
  service unrestartable
status: To Do
assignee: []
created_date: '2026-08-27 23:41'
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
