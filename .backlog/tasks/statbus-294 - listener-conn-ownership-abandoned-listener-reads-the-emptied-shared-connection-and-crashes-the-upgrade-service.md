---
id: STATBUS-294
title: >-
  listener-conn-ownership: abandoned listener reads the emptied shared
  connection and crashes the upgrade service
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-27 23:41'
updated_date: '2026-08-28 07:09'
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
NORTH STAR: the upgrade service must survive its own connection teardown. A listener that the service has abandoned must be unable to touch anything shared — today it can, and when it does, the whole service crashes.

THE ISSUE. When an upgrade starts, the service tells its database-notification listener to stop and waits ten seconds. If the listener does not stop in time, the service gives up and continues — its own comment says "leaking goroutine and continuing" (service.go:2612-2619) — leaving the listener running. The upgrade path then empties the shared connection field: d.listenConn = nil (service.go:5984, called from :5979). The abandoned listener does not hold its own connection; it re-reads that shared field at the top of every loop (service.go:2625). Its next pass therefore calls WaitForNotification on nothing and the process dies with SIGSEGV inside pgx v5.9.2 conn.go:419. Two parts of the program disagree about who owns the connection: one abandons it, the other keeps using it. This is also an unsynchronised data race (write at :5984, read at :2625).

EVIDENCE. Verbatim stack captured from arc run 33115731212 (transient-db-backoff): panic at conn.go:419 +0x1c reached from listenLoop at service.go:2625, fault address 0x90. The +0x1c says the function was freshly entered (the listener had looped, not parked), and 0x90 is the field's offset from a nil base — the connection was EMPTIED, not merely closed. A closed connection would return an error; the crash requires the nil write.

SCOPE NOTE, so nobody re-merges two problems: in the observed run the service crashed AND then failed to come back — but the failure to come back was the scenario's deliberately-paused database container ("cannot start a paused container"), not this bug. systemd restarted the service normally (restart counter 1). This ticket is the crash only.

THE FIX — three mechanical changes, two files, no open design decisions:
1. OWNERSHIP: startListenLoop (service.go:2557-2569) reads d.listenConn into a local and passes it to listenLoop as a parameter; listenLoop (:2622-2635) uses the parameter at :2625 and returns immediately if handed nil. An abandoned listener then holds a connection that is only ever CLOSED, never emptied — WaitForNotification returns an error and the existing error branch (:2626-2628) already exits cleanly. The crash becomes impossible by construction, and the race disappears because the abandoned listener no longer touches shared state.
2. NO ETERNAL BLOCK: the channel sends at :2630 and :2632 become select with <-ctx.Done(), so an abandoned listener that receives a notification cannot wait forever for a reader that no longer exists (a leak with the same ownership root).
3. HONEST LOGS: exec.go:1019, :1057, :1060 apply %v to installedID *int and print the ADDRESS (installed=0xc000013240) where a number belongs; print the value, <nil> when absent.

REJECTED: recover-and-relisten (this ticket's original proposal). It treats the symptom, would restart a listener on a connection the upgrade closed on purpose — re-creating the exact confusion — and cannot restore the one-listener-at-a-time rule. Fix 1 is smaller and removes the possibility instead of catching it.

WHAT IS ACHIEVED: no connection teardown can crash the upgrade service, the listener's lifecycle has exactly one owner, and the logs state facts instead of addresses.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-28 07:15
---
HISTORY. This ticket was filed 2026-08-27 23:41 from mid-diagnosis notes and rewritten 2026-08-28 after the engineer re-verified every claim against the code and the captured stack trace (arc run 33115731212). The description above IS the grounded version. Three original claims did not survive the grounding and are corrected there: (1) "service unrestartable" — refuted; systemd restarted it normally, and the failure to come back was the scenario's deliberately-paused database container, an unrelated cause; (2) "calls WaitForNotification on the CLOSED connection" — corrected to EMPTIED (d.listenConn = nil at service.go:5984); a closed connection returns an error, only the nil write crashes; (3) the original recover-and-relisten fix proposal — rejected for the reasons in the description.
---
<!-- COMMENTS:END -->
