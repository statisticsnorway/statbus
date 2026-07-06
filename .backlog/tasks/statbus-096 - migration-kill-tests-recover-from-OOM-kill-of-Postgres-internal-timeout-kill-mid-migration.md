---
id: STATBUS-096
title: >-
  migration-kill-tests: recover from OOM-kill of Postgres + internal
  timeout-kill, mid-migration
status: To Do
assignee: []
created_date: '2026-06-18 21:18'
updated_date: '2026-07-06 16:05'
labels:
  - upgrade
  - testing
  - install-recovery
dependencies:
  - STATBUS-095
  - STATBUS-071
priority: medium
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the box recovers from real kills mid-migration — external OOM-kill of Postgres and our internal timeout-kill — no fabrication.
> BENEFIT: the two remaining unproven rows in the coverage map ("eats all memory → OS kills it" and "runs past the ceiling → aborted") become run-proven — the failure modes big real databases actually produce, verified before a Norway-size migration meets them in production.
> STAGE: Stage 1 proof.
> COMPLEXITY: engineer-substantial (NOTIFY-handshake kill choreography on the arc framework); VM runs are the oracle.
> DEPENDS ON: STATBUS-095 (scenario 2 needs the timeout to exist), STATBUS-071 (framework).

---

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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OOM scenario — what it models (King, 2026-06-18): a migration that runs on a BIG database, does NOT handle the load (tries to do something it shouldn't — e.g. pulls a whole large table into memory, an unbounded build), eventually consumes all memory, and is killed by the OS OOM-killer. Kill source = the OS (EXTERNAL), killing PostgreSQL. This is distinct from the time-based runaway: memory blowup -> external OOM-kill (this task, scenario 1); time overrun -> internal 12h timeout-kill (STATBUS-095, scenario 2). The test reproduces the EFFECT deterministically (kill Postgres mid-migration via the NOTIFY handshake) without actually exhausting memory; the property under test is simply: when the OS OOM-kills Postgres mid-migration, the box recovers.

OWNERSHIP (foreman, 2026-06-18): build = engineer; review = architect (correctness of the kill timing + the recovery assertions) then foreman (diff); commit + VM re-fire = foreman.

DEPENDS / BUILDS ON: the STATBUS-071 arc framework (arc-helpers.sh + the NOTIFY-handshake) — start only once both arcs (working + failing) are green. Scenario 2 (timeout) depends on STATBUS-095 (the 12h timeout must exist to test it).

CLARITY ON THE TWO KILLS (do not conflate): scenario 1 OOM = the OS kills PostgreSQL from OUTSIDE (a bad migration on a big DB eats all memory); scenario 2 timeout = OUR code kills the migration from INSIDE (the 12h limit, short threshold in test). Both must end in a clean autonomous recovery on the box. The handshake (NOTIFY + pg_sleep + external kill) is the King's design and gives the deterministic kill moment.
<!-- SECTION:NOTES:END -->
