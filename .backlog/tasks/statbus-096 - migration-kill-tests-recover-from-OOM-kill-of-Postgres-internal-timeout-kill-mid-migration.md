---
id: STATBUS-096
title: >-
  migration-kill-tests: recover from OOM-kill of Postgres + internal
  timeout-kill, mid-migration
status: Done
assignee: []
created_date: '2026-06-18 21:18'
updated_date: '2026-07-07 05:18'
labels:
  - upgrade
  - testing
  - install-recovery
dependencies:
  - STATBUS-095
  - STATBUS-071
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
- [x] #1 A test migration pauses mid-run and signals it (NOTIFY handshake) so the kill is deterministic
- [x] #2 OOM scenario: PostgreSQL killed (external) mid-migration → box recovers → asserted on a real VM
- [x] #3 Timeout scenario: internal timeout-kill (short threshold) mid-migration → box recovers → asserted on a real VM
- [x] #4 No fabrication: the migration really runs and is really killed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OOM scenario — what it models (King, 2026-06-18): a migration that runs on a BIG database, does NOT handle the load (tries to do something it shouldn't — e.g. pulls a whole large table into memory, an unbounded build), eventually consumes all memory, and is killed by the OS OOM-killer. Kill source = the OS (EXTERNAL), killing PostgreSQL. This is distinct from the time-based runaway: memory blowup -> external OOM-kill (this task, scenario 1); time overrun -> internal 12h timeout-kill (STATBUS-095, scenario 2). The test reproduces the EFFECT deterministically (kill Postgres mid-migration via the NOTIFY handshake) without actually exhausting memory; the property under test is simply: when the OS OOM-kills Postgres mid-migration, the box recovers.

OWNERSHIP (foreman, 2026-06-18): build = engineer; review = architect (correctness of the kill timing + the recovery assertions) then foreman (diff); commit + VM re-fire = foreman.

DEPENDS / BUILDS ON: the STATBUS-071 arc framework (arc-helpers.sh + the NOTIFY-handshake) — start only once both arcs (working + failing) are green. Scenario 2 (timeout) depends on STATBUS-095 (the 12h timeout must exist to test it).

CLARITY ON THE TWO KILLS (do not conflate): scenario 1 OOM = the OS kills PostgreSQL from OUTSIDE (a bad migration on a big DB eats all memory); scenario 2 timeout = OUR code kills the migration from INSIDE (the 12h limit, short threshold in test). Both must end in a clean autonomous recovery on the box. The handshake (NOTIFY + pg_sleep + external kill) is the King's design and gives the deterministic kill moment.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-07 04:10
---
CONSTRUCTION RULING (architect, 2026-07-07). SCOPE FIRST: scenario 2 (the internal timeout kill) IS STATBUS-095's arc — it folds there (ruling on 095, comment #1); this ticket keeps exactly ONE build: the OOM arc. NO product knob needed — mechanic-buildable now, independent of 095.

DETERMINISM RULING (the foreman's flag, settled): the harness VM is a CX23 (2 vCPU / 4 GB shared with the whole stack) — real memory pressure is NOT a deterministic trigger there: the kernel OOM-killer picks its victim by heuristics and can take the daemon, sshd, or the worker instead of postgres, which is exactly the flaky class we forbid. The King already ruled the honest shape in this ticket's own notes: reproduce the EFFECT deterministically — kill Postgres from OUTSIDE mid-migration — without exhausting memory. So the trigger is `docker kill --signal=SIGKILL <db-container>` at the confirmed midpoint: the postmaster dies by SIGKILL exactly as under the OOM-killer, uncommitted work is lost, and WAL recovery runs on the next start — the property under test ('when the OS OOM-kills Postgres mid-migration, the box recovers') is fully exercised. OPTIONAL higher-fidelity variant, NOT required and not now: a cgroup bound on the db container (docker update --memory) + a memory-hungry V — scopes the kill to the container so it IS deterministic, but adds machinery for the same observable; file it as a nicety only if the King ever wants the kernel's own killer in the loop.

ARC CONSTRUCTION (postswap-migration-oom-arc, mechanic, the proven V_fail lineage): construct B = A + V_sleep (body `SELECT pg_sleep(3600);`, hand-authored WITHOUT its own BEGIN/END — the constructor must not wrap it) via 118; real register → schedule → daemon dispatches. MIDPOINT (anti-vacuity, the proven pattern): poll pg_stat_activity for the active pg_sleep backend — the mid-run confirmation the ticket's NOTIFY-handshake sketch wanted, delivered by the mechanism the park and mid-tx work already proved (no LISTEN client needed; the sketch predates those proofs) → THEN `docker kill --signal=SIGKILL` the db container, and assert the container observed dead (docker ps) — the kill-landed leg.

EXPECTED OBSERVABLE CHAIN (stated with the honest uncertainty marked — the run is the oracle): migrate's psql loses its connection → the migrate step fails → the daemon's observed-state read initially cannot reach the DB → STATBUS-109's db-unreachable backoff-retry holds IN-PROCESS (this will be 109's first live firing in an arc — assert its named log line as a bonus leg) → the db container comes back (compose restart policy) + WAL recovery → the re-read says Behind (V's tx died uncommitted with its backend) → data-safe rollback → TERMINAL rolled_back. If the container does NOT auto-restart, the backoff exhausts → the same data-safe rollback (restoreDatabase is volume-level; rollback's own services-up brings the db back) → rolled_back either way. ASSERTION SPEC: midpoint pg_sleep-active + container-dead; the 109 backoff-retry marker (db-unreachable) in the log; terminal rolled_back (completed/failed → hard fail); V unrecorded (db.migration max == baseline); clean-slate fingerprint == post-A baseline; demo data intact; flag absent; NRestarts bounded — the DAEMON is never killed here, so the bound is the failing-arc's proven shape (the exit-42 handoff bump only); any daemon death would itself be a finding.

BUILDER: mechanic per this ruling; architect reviews the arc before commit. Runs whenever a batch slot opens — no dependency on 095's knob.
---

author: foreman
created: 2026-07-07 04:30
---
ADJUDICATION (architect, 2026-07-07): the mechanic's map-before-build trace REFUTED the construction ruling's causal narrative and the architect CONFIRMED it and went further — backoffRetry has exactly one call site (service.go:1085, the Resuming branch), and Run()'s boot does EnsureDBUp (docker compose up -d db, service.go:1808) on EVERY pass before any recovery branch, so after a single db kill the FRESH RE-RUN is destiny, not one arm of a race. The as-built arc (V_sleep=3600s, terminal rolled_back) would deterministically stall-red — derivable, not oracle territory. RESHAPE DISPATCHED (mechanic): V_sleep→60s, expected terminal COMPLETED (single-OOM contract = FORWARD recovery: boot revives db, uncommitted migration re-runs fresh, completes), assertion swap (V RECORDED + fixture present replace V-unrecorded/fingerprint), NRestarts ≤3 logged-observed, 109/017 markers best-effort. KING DECISION QUEUED: the 071 map cell literally says 'OOM → rolls back' — that wording matches the RECURRING-OOM story (a migration that OOMs every run → re-armed kill each midpoint → budget/same-step → Behind → rolled_back), which the architect pre-blessed as a SEPARATE follow-up arc, built only after the single-OOM arc is green and gated on the King blessing the split (single→completed, recurring→rolled_back) since it edits his cell's wording. The map cell is NOT edited until that nod.
---

author: foreman
created: 2026-07-07 04:59
---
OOM ARC GREEN ON FIRST CONTACT (run 28841893851, HEAD 39b94be8d, 2026-07-07 — all jobs green): the single-OOM contract proven live on a real VM. Real register+schedule dispatch, midpoint pg_stat_activity poll confirmed the migration genuinely mid-sleep (AC#1's deterministic-kill requirement, delivered by the proven poll pattern in place of the ticket's original NOTIFY sketch — architect-ruled substitution), db container SIGKILLed and observed dead, then the FORWARD recovery exactly as the reshaped contract predicted: the boot's own EnsureDBUp revived the db, the uncommitted migration re-ran fresh, terminal COMPLETED with V recorded + the fixture table present (ran end-to-end), demo data intact, flag absent, NRestarts within bound. AC#1, #2, #4 checked. AC#3 (the internal timeout kill) is the ceiling arc — folded to STATBUS-095 piece 2, on CI now (run 28842366163). STILL KING-GATED: the 071 coverage-map cell rewording (its 'rolls back' text matches the RECURRING-OOM story) + the recurring-OOM variant arc — the map cell stays untouched until the King blesses the split (single→completed, recurring→rolled_back).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: the box recovers from real kills mid-migration — no fabrication. DELIVERED, both scenarios run-proven on real VMs 2026-07-07, both green on FIRST CONTACT. OOM (this ticket's build, 39b94be8d, CI run 28841893851): real register+schedule, migration confirmed genuinely mid-sleep via the pg_stat_activity poll (the deterministic-midpoint requirement, delivered by the proven poll pattern superseding the original NOTIFY sketch), db container SIGKILLed (reproducing the OS OOM-killer's effect deterministically — real memory pressure on a shared 4GB box is the forbidden flaky class) and observed dead, then FORWARD recovery: the boot's own EnsureDBUp revived the db, the uncommitted migration re-ran fresh to COMPLETED with V recorded + fixture table present, demo data intact. The single-OOM contract is forward completion — established by the mechanic's map-before-build refutation of the original rolled_back narrative, architect-confirmed (backoffRetry's sole call site service.go:1085; EnsureDBUp unconditional at :1808). Timeout scenario (folded to STATBUS-095 piece 2): ceiling arc GREEN, run 28842366163 — internal 20s kill → rolled_back, clean slate. OPEN FOLLOW-UP (deliberately NOT lost): the RECURRING-OOM variant (OOMs every run → death budget → rolled_back) is pre-blessed as a separate arc, gated on the King blessing the single/recurring split since it rewords the 071 coverage-map cell — tracked on 071's open-decision list and this ticket's comments #2/#3.
<!-- SECTION:FINAL_SUMMARY:END -->
