---
id: STATBUS-096
title: >-
  migration-kill-tests: recover from OOM-kill of Postgres + internal
  timeout-kill, mid-migration
status: Done
assignee: []
created_date: '2026-06-18 21:18'
updated_date: '2026-07-11 20:22'
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

author: foreman
created: 2026-07-07 08:31
---
REOPENED by the King's morning review (2026-07-07), two grounds: (1) WORDING — 'the box revives the database on its own boot' was sloppy: NO box restart is involved anywhere in this story. Precise mechanics: only the Postgres CONTAINER is killed; the upgrade daemon (a separate host process, systemd user service) survives, and it is the DAEMON'S OWN CODE that runs `docker compose up -d db` — unconditionally at the start of every daemon process pass (service.go:1808) and again inside the resume step — then waits for health and re-attempts the pending migration. Read 'boot' in prior comments as 'a boot pass of the upgrade daemon process', never 'the box'. (2) PRINCIPLE CHALLENGE (King, verbatim): 'isn't the problem here that you ratified 3 retries before aborting, while I tried to tell you we must immediately determine if it is a transient or permanent error? And you seem to do neither, just try again? And in the real case of a runaway migration, we have an incorrect strategy in principle?' — routed to the architect for a max-effort adversarial review of the retry-vs-classify strategy at the migration-failure site, plus the principled ordered walkthrough of how a box gets into boot-migrate applying migrations at startup. Done-status is SUSPENDED until that adjudication; the green runs stand as evidence, but whether they prove the RIGHT contract is exactly the open question.
---

author: architect
created: 2026-07-07 08:47
---
ADVERSARIAL ADJUDICATION 1/2 — THE TRUTH TABLE + IS THE RECURRING-OOM CYCLE BOUNDED? (architect, 2026-07-07, fresh context — every row re-traced in today's code, no inheritance from prior rulings.)

What the system ACTUALLY does per migration-failure class:

1. DETERMINISTIC SQL ERROR (psql exit 3 → migrate exit 20, exit_codes.go:72-75). Resume-pipeline site (service.go:5449-5455): classified on FIRST occurrence → positively-Behind → data-safe rollback, else PARK (parkForDeterministicFailure :5042). Zero retries. Boot-migrate flagged: defer to the snapshot-restore owner (:1972-1976). Boot-migrate flagless: one loud report + alive-idle (:1977-2013, STATBUS-144). The charge 'you just try again' does NOT hold for errors that speak.

2. TIME RUNAWAY: killed at the 12h ceiling (watchdog.go:150; service.go:5431-5442), orphan backend reaped, observed-state Behind → rollback → rolled_back. ONE occurrence, no retry. Run-proven (ceiling arc, run 28842366163).

3. SILENT DAEMON DEATH mid-migration: counted at next pass start (RecoveryBudgetGuard :5826); two consecutive deaths at one step → park (recovery_escalation.go:117-123); 3 deaths overall → park. Run-proven (r19).

4. CONNECTION LOST BECAUSE THE DB ITSELF DIED (this ticket's OOM class): psql exit 2 → migrate exit 1 UNCLASSIFIED (exit_codes.go:21,31) → classUnknown → A. THE KING'S CHARGE IS FACTUALLY CORRECT HERE: this class is classified NOWHERE. No code reads the db container's exit state (docker inspect OOMKilled/ExitCode) or the postmaster's crash markers — grep-verified across cli/. The system cannot distinguish 'the database died under this migration' from 'psql hiccup'.

IS THE RECURRING CASE BOUNDED? YES — and the premise behind the fear ('the budget counts daemon deaths, not migration failures') is wrong. recovery_attempts counts RECOVERY PASSES (incremented at pass start, :5722-5734), and a failed migration always ends its pass in a process error-exit: boot-migrate site → 017-defer → recoverFromFlag's post_swap arm queries the conn the db kill broke → error (resumePostSwap :5961-5965) → Run returns (:2030-2032) → exit → systemd restart → next pass counts. Resuming arm: unreadable → ONE bounded backoff (:1085); recurrence after a cleared backoff → data-safe ROLLBACK (:1071-1080). 3.5 site: classUnknown → postSwapFailure returns error (:5456/:5022) → same exit-and-count. Concrete recurring trace (db killed every time V runs, daemon never touched): pass 1 (handoff, attempts=1) V runs, db dies, pass exits; pass 2 (attempts=2) V runs, db dies, exits; pass 3 (attempts=3) same-step-twice at boot-migrate → PARK + siren once, migrate skipped, daemon alive-idle. V ran TWICE, db killed TWICE, bounded. Alternating dying-steps → budget park at pass 4 instead. NO eternal revive-OOM-revive cycle exists in shipped code. (The db container self-revives too — restart: unless-stopped, postgres/docker-compose.yml:12 — plus EnsureDBUp at :1808 on every pass.)

TWO HONEST CAVEATS the bound does not excuse: (a) the park reason is CAUSE-BLIND — 'two consecutive crash-deaths at step boot-migrate' never tells the operator the DATABASE was dying underneath, and on a Norway-size migration those two classification runs can cost up to 2×12h of maintenance window plus two production-db kills to learn what one docker-inspect after the first kill already knew. (b) The park terminal leaves the box IN MAINTENANCE (cleanStaleMaintenance keeps the file while a row is in_progress, :3366-3388) with the schema genuinely Behind (V's tx died uncommitted) — the data-safe rollback exists but only a deliberate ./sb install reaches it (the guard parks with canRollBack=false; F1 forbids auto-rollback of parked rows). 'Alive-idle' describes the daemon, not the site. Verdict continues in 2/2.
---

author: architect
created: 2026-07-07 08:47
---
ADVERSARIAL ADJUDICATION 2/2 — THE PRINCIPLE + RECOMMENDATION (architect, 2026-07-07).

THE PRINCIPLE. The ratified doctrine's own defense of the budget is one sentence (044 comment #7): re-running is the classification instrument ONLY where no signal speaks. That rationale is self-limiting, and at this site it cuts AGAINST the shipped code: when a migration's connection dies, a signal DOES speak — the db container's state (docker inspect: dead/restarted, ExitCode 137, OOMKilled, StartedAt newer than the migrate start) and the postmaster's canonical crash line in the db log ('terminated by signal 9' — PostgreSQL-authored constant text on a version-pinned image, the same authorship tier as the already-accepted strerror(ENOSPC) marker, recovery_escalation.go:308-315). We read none of it. By the doctrine's own rule the King's position WINS on this site: the memory-runaway is misfiled as A/unknown (bounded rerun) when readable evidence files it as C (resource — retrying amplifies: every rerun kills the production db again). The cost asymmetry that once justified rerun-as-classifier has also flipped: at the old 30-min bound an experiment was cheap; under the deliberate 12h ceiling each experiment can cost half a day of maintenance window.

WHERE THE SHIPPED DESIGN STANDS ITS GROUND (the fair steelman, so the ruling is on the true tradeoff): (a) ONE db-death under a migration proves the db died of memory, NOT that the migration is the culprit — ambient pressure can kill the same backend; the second run is what upgrades correlation to determinism. (b) B/C failures already park on first; the budget only ever governed signals believed mute. (c) 'You do neither, just try again' is FALSE for the classes that speak and for time-runaways (one-shot ceiling abort + rollback); it is TRUE for exactly one class: db-death-under-migration.

RECOMMENDATION (rulable; supersedes the queued single/recurring map-cell split). Add a post-failure EVIDENCE PROBE at both migrate-failure sites — the pattern already pre-blessed for the manifest-404 arm (post-failure disambiguation probe, 046 comment #9). On an UNCLASSIFIED migrate failure: probe the db container — docker inspect (structured: running/dead, ExitCode, OOMKilled, StartedAt vs migrate start) plus a bounded db-log tail for the postmaster crash constants. POSITIVE evidence → class-C disposition on FIRST occurrence through the existing parkForDeterministicFailure route: positively-Behind → data-safe rollback (the common case here — the killed migration's tx never committed); at-target/unverifiable → park; either way the reason NAMES the evidence ('the database was killed by the OS while migration <v> ran — it likely exceeds this box's memory; data restored / fix, then re-trigger'). NO evidence → today's bounded behavior unchanged; under-match degrades to leniency, never a wrong abort (the ENOSPC asymmetry). Marker-discipline pins apply verbatim: conjunctive (migrate failed + connection-class exit + container evidence), positive-match-only, unit-tested constants.

WHAT IT COSTS: one probe helper + one classification arm + tests + the recurring-OOM arc — and one deliberate CONTRACT FLIP the King must bless: the single-OOM arc's current green contract (forward re-run → completed) becomes rolled_back-on-first-evidenced-kill. Residual risk, named: an AMBIENT OOM (migration innocent) now aborts an upgrade a re-run might have completed — the operator re-schedules deliberately. That is the intended trade: on a box whose database just died under migration load, a human-decided re-attempt replaces an automatic second experiment.

WHAT THE RUNAWAY-MIGRATION STORY BECOMES: symmetric, one-shot, evidence-named on both axes. Time-runaway: ceiling kill → rollback (shipped, run-proven). Memory-runaway: OS kills the db → evidence read → rollback (or park if genuinely at-target) on FIRST occurrence. The 071 map cell 'OOM → rolls back' becomes literally TRUE on first occurrence — the King's original wording, vindicated — rather than only after a park and an operator un-park. The ordered boot-migrate walkthrough the King also asked for is doc-027 (pointer on 044 comment #14).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: the box recovers from real kills mid-migration — no fabrication. DELIVERED and, after the King's reopen, RE-DELIVERED under the corrected principle. History in full: both scenarios first went green 2026-07-07 (OOM forward-completed run 28841893851; ceiling rolled_back run 28842366163). The King REOPENED on the retry-vs-classify principle challenge; the architect's adversarial adjudication (comments #5/#6) found the charge factually correct for exactly one class (db-death-under-migration, classified nowhere) and recommended the evidence probe + contract flip. THE RESOLUTION CAME STRUCTURALLY VIA STATBUS-145 (the King's minimal-boot-migrate redesign, his PROCEED ruling superseding the single/recurring split question): under the atomicity flip a mid-delta OOM kill reads positively Behind → one-shot data-safe rollback — no second experiment on a dying database. RE-PROVEN under the new geometry: OOM arc GREEN, terminal ROLLED_BACK on the FIRST kill, V unrecorded, clean-slate fingerprint matching baseline (run 28955342618, wave 1 of the slice-4 campaign) — the King's original 071 map-cell wording ('OOM → rolls back') is now LITERALLY TRUE, by structure. The naming refinement (per-leg evidence probe: OOMKilled → causal memory wording; bare 137 → factual; log-constant → factual) shipped as 145 slice 3 (9b4710900). Ceiling single-fire re-proven wave 1 (one ceiling marker, delta never runs at boot). The recurring-OOM variant arc is retired as superseded — recurrence is bounded by the recovery budget and the first kill already rolls back. All four ACs stand checked under the flipped contract.
<!-- SECTION:FINAL_SUMMARY:END -->
