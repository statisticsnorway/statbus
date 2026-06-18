---
id: STATBUS-096
title: >-
  migration-kill-tests: recover from OOM-kill of Postgres + internal
  timeout-kill, mid-migration
status: To Do
assignee: []
created_date: '2026-06-18 21:18'
labels:
  - upgrade
  - testing
  - install-recovery
dependencies: []
priority: medium
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Verify the box recovers from real kills that happen WHILE a migration is running. No fabrication — a real migration, really running, really killed.

THE MECHANISM (King, 2026-06-18) — pause-then-kill handshake, zero product change:
- A test migration runs `NOTIFY <chan>;` then `SELECT pg_sleep(N);` with NO BEGIN. Because the runner invokes psql without --single-transaction (migrate.go:401), the NOTIFY commits immediately and reaches a listener while the migration is still sleeping.
- A test listener does `LISTEN <chan>`, blocks until the NOTIFY arrives, waits a moment to be sure the migration is genuinely inside the sleep, then kills.

SCENARIOS:
1. OOM: while the migration sleeps, kill PostgreSQL from the OUTSIDE (simulates the OS OOM-killer). Assert the box recovers cleanly.
2. Timeout: trigger the migration-timeout kill (the 12h-timeout requirement, run with a short threshold) — an INTERNAL kill by our own code — while the migration runs. Assert the box recovers the same way a real 12h kill would.
3. Room for further kill scenarios (King: "possibly other scenarios as well").

Builds on the real-upgrade arc framework (STATBUS-071). Scenario 2 depends on the migration-timeout task.

Source: King, 2026-06-18.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test migration pauses mid-run and signals it (NOTIFY handshake) so the kill is deterministic
- [ ] #2 OOM scenario: PostgreSQL killed (external) mid-migration → box recovers → asserted on a real VM
- [ ] #3 Timeout scenario: internal timeout-kill (short threshold) mid-migration → box recovers → asserted on a real VM
- [ ] #4 No fabrication: the migration really runs and is really killed
<!-- AC:END -->
