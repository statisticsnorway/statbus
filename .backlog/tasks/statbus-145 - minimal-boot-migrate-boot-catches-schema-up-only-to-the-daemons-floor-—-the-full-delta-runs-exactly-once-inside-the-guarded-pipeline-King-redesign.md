---
id: STATBUS-145
title: >-
  minimal-boot-migrate: boot catches schema up only to the daemon's floor — the
  full delta runs exactly once, inside the guarded pipeline (King redesign)
status: In Progress
assignee:
  - architect
created_date: '2026-07-07 09:23'
updated_date: '2026-07-11 20:21'
labels:
  - upgrade
  - recovery
  - design
  - product
  - needs-king-ratification
  - install-recovery
dependencies: []
references:
  - doc-027
  - doc-021
  - STATBUS-096
  - STATBUS-044
  - STATBUS-144
  - cli/internal/upgrade/service.go
  - cli/internal/migrate/migrate.go
  - cli/cmd/install_upgrade.go
  - cli/cmd/migrate.go
priority: high
ordinal: 146000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: startup migrates the schema only to the daemon's own operating floor; every upgrade's real migration delta runs EXACTLY ONCE, inside the guarded pipeline step where counting, classification, the ceiling, park, and data-safe rollback already live. No migration runs "blindly at startup".
> BENEFIT: kills the runaway double-fire (today a runaway migration burns 2×12h — boot-migrate fire + pipeline re-fire — before rollback: the King's cost observation), makes a mid-delta failure terminal in ONE occurrence via the existing observed-state rule (schema positively Behind + pre-completion → snapshot restore), dissolves the "blind at startup" objection structurally, and shrinks the 144 flagless-churn class to floor migrations only.
> STAGE: Stage 1 — design for the King's ruling (rule together with the 096 #6 evidence probe; comment #2 shows how they compose).
> COMPLEXITY: engineer-substantial but cheap at the core — the bounded migrate form ALREADY EXISTS (`./sb migrate up --to <version>`, cmd/migrate.go:163; migrate.Up honors migrateTo, migrate.go:766-768). The work is the floor derivation + guard test + two boot sites + scenario/doc updates. No schema change.
> DEPENDS ON: nothing hard. RESHAPES: STATBUS-096 (OOM contract), STATBUS-144 (classification site), STATBUS-044 (park-scenario kill window), doc-021 (step list + budget-boundary narrative).

KING'S DIRECTION (verbatim, 2026-07-07): "So 'boot-migrate' seems to be too much. Why couldn't you upgrade to the last commit that contains the first migration that we really need for the upgrade itself to run. It gets us to the point of importance, not runs every migration? By changing this strategy, that point should be moot." And the cost observation: "The problem with out-of-memory conditions or with migrations running for an extremely long time and getting killed is that if we do it multiple times we have like twelve hours times two before we finally eat all the RAM and the process is killed or disaborted due to timeout."

READING (as designed here — the King corrects via this entry if misread): boot-migrate catches the schema up only to what the DAEMON ITSELF needs to operate. That is the schema-skew guard's real requirement by its own comment — service.go:1866-1869: "The binary's column-name expectations must match the running schema before any service-level query touches public.upgrade" — today's apply-ALL overshoots the code's own stated justification. The floor is expressed as a migration VERSION rather than a commit (same meaning, cleaner unit: migrations are linear and timestamp-versioned). The full delta then runs inside applyPostSwap's migrate step (service.go:5421) — the one site that already has write-ahead step stamping, the 12h ceiling + orphan reap (:5431-5442), exit-code classification 20/22 → park-on-first (:5449-5455), the death budget via the early guard, and the observed-state disposition (Behind → data-safe rollback).

VERDICT UP FRONT: SOUND and cheap at the core. THE SINGLE MOST IMPORTANT TRACED CONSEQUENCE (comment #2): because "at-target" is DEFINED as db.migration max ≥ on-disk max (verifyUpgradeObservedStateEx, service.go:2482-2486), moving the delta out of boot flips every mid-delta failure disposition from "forward retry" to "positively Behind → one-shot snapshot restore". Upgrades become effectively ATOMIC: apply the delta once; any death or failure mid-delta restores the pre-upgrade snapshot (data-safe: maintenance on, read-only window on, stopped-DB backup); the operator re-triggers deliberately. That is exactly the King's stated posture — and it is a deliberate contract change that must be named, not slipped in.

Full analysis: comment #1 (floor mechanism, bounded form, what it dissolves), comment #2 (costs/risks, ordering trace, the atomicity flip, composition with the 096 evidence probe, build order).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King ratifies: the floor strategy, the atomicity flip (mid-delta failure → one-shot rollback via the existing Behind rule), and the flagless floor-only semantics (pending-above-floor logged loud, applied only by deliberate upgrade/install)
- [ ] #2 Floor mechanism shipped: derived from the daemon-relation set (public.upgrade, db.migration, public.system_info + builder-verified enumeration), sufficiency enforced mechanically (CI guard: migration touching the set ⇒ floor bump) + an empirical floor test (schema at exactly floor; daemon boot+recovery queries run 42703-clean); existing 42703 fail-opens retained as backstop
- [x] #3 Both boot sites switch to the bounded form (service.go:1934, install_upgrade.go:290 → migrate up --to FLOOR); the deliberate install step-table Migrations step stays apply-all (cmd/install.go:623)
- [ ] #4 Oracles re-proven: ceiling arc single-fire (1×ceiling → rolled_back, not 2×), OOM arc terminal rolled_back on first kill, park scenario kill window moved back to the pipeline migrate step
- [x] #5 doc-021 step list + budget-boundary narrative + both diagrams updated in the same commit as the shipped change (docs describe the present)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
KING RULED PROCEED (2026-07-08, via foreman): floor strategy + atomicity flip + flagless floor-only semantics approved; the 096 evidence probe approved as the naming refinement; the OOM single/recurring split question is SUPERSEDED by this build (mid-delta OOM → Behind → rolled_back structurally). AC#1 is thereby satisfied; ACs #2-#5 map to the slices below. Architect reviews every slice hands-on before commit; foreman dispatches and commits.

## SLICE 1 — floor substrate (engineer; zero behavior change; ship-safe alone)

1. Checked-in constant `DaemonSchemaFloor int64 = 20260703210000` (cli/internal/migrate or upgrade pkg — builder's call, one home). DECIDED: const + test-guard over build-time ldflags derivation — deterministic binary, reviewable diff, no build-step magic; the mechanical guard below makes forgetting impossible.
2. BUMP-GUARD test: a Go test scanning migrations/*.up.sql with version > floor for the daemon relation set — public.upgrade, db.migration, public.system_info, plus whatever the builder's enumeration of service.go's query surface adds (architect reviews the enumeration against the ~23 sites). Any hit fails with "migration <v> touches daemon relation <r> — bump DaemonSchemaFloor in the same commit". Scanning our own migration SQL is data-scan, not the banned error-prose classification.
3. EMPIRICAL FLOOR test: provision a scratch DB migrated `--to <floor>`, execute the daemon's boot+recovery query list, assert zero SQLSTATE 42703. Builder picks the cheapest harness that genuinely executes the queries (Go integration against the test cluster or a dev.sh test); the query list is the enumeration artifact from step 2.
4. The existing 42703 fail-open patterns (RecoveryBudgetGuard :5777-5782 and kin) stay untouched as last-resort backstop.

## SLICE 2 — the geometry change (engineer; THE ATOMICITY FLIP SHIPS HERE; architect hands-on review before commit)

1. Both boot sites switch to the bounded form: service.go:1934 and install_upgrade.go:290 → `migrate up --to <floor> --verbose`. The deliberate step-table Migrations step (cmd/install.go:623) stays apply-all.
2. New helper `migrate.HasPendingAbove(projDir, floor)`; flagless boot with pending-above-floor logs ONE loud line ("N migrations pending beyond the daemon floor — they apply on the next deliberate upgrade or ./sb install").
3. DEPENDENTS AUDIT in-slice (grep the dying invariant "boot-migrate applies everything"; each finding recorded in the review): resumePostSwap self-heal canary (HasPending gate :6019 — correct as-is, never short-circuits a delta-pending resume); markCurrentVersionCompleted + completeInProgressUpgrade (observed-state-gated — refuse on pending delta, correct); the Resuming-branch obs read (Behind → rollback IS the flip, desired); 017-defer (:1972 — domain shrinks to floor migrations, code unchanged, comment updated); the 144 exit-20 alive-idle branch (:1977-2013 — same: unchanged code, shrunken domain, comment updated).
4. IN THE SAME COMMIT (docs describe the present; diagrams land with the handling): doc-021 step-list + budget-boundary rewrite (boot window = floor-only, delta at the pipeline migrate step, the atomicity flip named as ratified); both diagrams (upgrade-timeline + upgrade-lifecycle); AND the assertion flips for every contract-changing arc so the next dispatch is truthful — OOM arc (terminal rolled_back on first kill; V-unrecorded + clean-slate fingerprint assertions return), between-migrations + mid-migration arcs (completed → rolled_back), ceiling arc gains the single-fire leg (exactly ONE ceiling marker in the journal; delta never runs at boot).
5. Unit tests: bounded boot-migrate command construction; floor no-op path; the loud-line branch.

## SLICE 3 — the 096 evidence probe (engineer; architect reviews under classifier discipline)

1. Post-failure probe at the now-single migrate-failure site (applyPostSwap's handler, :5424+): docker inspect of the db container (STRUCTURED fields: running/dead, ExitCode, OOMKilled, StartedAt vs the migrate start) + a bounded db-log tail scan for the postmaster crash constants ("terminated by signal 9" — PostgreSQL-authored, version-pinned image; the strerror(ENOSPC) authorship tier).
2. Conjunctive + positive-match-only (the ENOSPC asymmetry): evidence found → the failure/park/rollback REASON carries it as named data ("the database was killed by the OS while migration <v> ran — it likely exceeds this box's memory"); no evidence → today's path unchanged. Under-match degrades to leniency, never a wrong abort.
3. Unit tests pin the verbatim constants; the probe is best-effort (its own failure never changes disposition).

## SLICE 4 — the verification campaign (foreman dispatches; the run is the only oracle)

1. Re-prove the flipped contracts on real VMs: OOM arc (rolled_back on first kill), ceiling arc (single fire), between-migrations + mid-migration arcs (rolled_back). Regression confidence set: failing arc, working arc, one preswap kill arc, rollback-restore-watchdog.
2. PARK SCENARIO REAL-PATH REBUILD (per doc-028 + the King's carve-out ruling): mechanic builds from a short architect spec written AFTER slice 2 lands (the surviving park window under the new geometry = floor-migrate deaths + at-target post-delta crashes — e.g. repeated daemon kills at the health-check step, kill gate = the write-ahead step stamp). The r19-green fabricated scenario stays as the interim regression net until the rebuild is green — never delete proof coverage before its replacement is proven — then fabricate_resume_state drops to its ONE sanctioned caller (rune-wedge).
3. On green: reword the 071 coverage-map OOM cell ("rolls back" — now literally true on first occurrence), update doc-027 §C/§D to the new geometry, and close this ticket's AC#4/#5.

Build order: 1 → 2 → 3 → 4. Slices 1-3 are separate reviewable commits; slice 2 is the load-bearing review (the flip + in-commit docs + in-commit assertion flips).
<!-- SECTION:PLAN:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-07 09:24
---
DESIGN ANALYSIS 1/2 — (a) the floor, (b) the bounded form, (c) what it dissolves. (Architect, 2026-07-07; every claim traced against master HEAD today.)

(a) CAN THE BINARY KNOW ITS FLOOR? Yes, mechanically. The relations the daemon touches before the delta applies are a small closed set — public.upgrade (+ its enums/constraints), db.migration (the observed-state read, service.go:2462-2463), public.system_info (syncConfigToSystemInfo, :2987/:3005) — final enumeration is a build task with the floor test as its oracle. FLOOR = the max version among migrations that touch that set (today: 20260703210000, the park columns). Two derivation shapes, either sound: (i) BUILD-TIME — scan migrations/ for the relation set at build and stamp the floor via ldflags exactly like `commit`; nothing to remember. (ii) CHECKED-IN CONST + a CI guard that fails when a migration newer than the floor touches the set without a floor bump in the same commit. Both are sufficiency BY CONSTRUCTION (a mechanical scan of migration SQL — data-scan of our own files, not the banned error-prose classification), backstopped by an EMPIRICAL FLOOR TEST: migrate a template to exactly FLOOR, run the daemon's boot + recovery query set, assert zero 42703. The existing 42703 fail-open patterns (RecoveryBudgetGuard :5777-5782 and kin) remain as the last-resort backstop, so the rc.63 skew class stays covered belt-and-suspenders. NOTE on the King's phrasing: 'the last commit that contains the first migration we really need' is implemented as a migration-VERSION floor, not a commit — identical meaning (migrations are linear and timestamp-versioned), cleaner unit.

(b) WHAT BOOT-MIGRATE-TO-FLOOR LOOKS LIKE: zero new migrate machinery. The bounded form ALREADY EXISTS: migrate.Up(projDir, migrateTo, all, verbose) honors migrateTo (migrate.go:766-768) and the CLI already exposes `./sb migrate up --to <version>` (cmd/migrate.go:163). The change is: the two boot sites (service.go:1934 daemon, install_upgrade.go:290 install crash-ladder) pass `--to FLOOR`; the deliberate step-table 'Migrations' step (cmd/install.go:623) stays apply-all — the operator's explicit install remains the apply-everything action. A flagless boot with pending-above-floor logs ONE loud line ('N migrations pending beyond the daemon floor — they apply on the next deliberate upgrade or ./sb install') instead of applying them silently. On the NORMAL single-release upgrade the floor migrations shipped in earlier releases and are already applied — the boot catch-up is a NO-OP: the common-path boot window disappears entirely.

(c) WHAT IT DISSOLVES: (1) THE DOUBLE-FIRE — verified in today's code: a runaway migration fires the 12h ceiling at boot-migrate (:1934), 017-defers because the flag is present (:1972-1976), the resume re-runs the SAME migration at the pipeline step (:5421) and fires a SECOND 12h before postSwapFailure → Behind → rollback. 24h worst case — exactly the King's 'twelve hours times two'. After: the delta runs ONCE at :5421; the first ceiling fire routes to rollback; worst case 12h. (2) THE CRASH-WINDOW-BEFORE-THE-GUARDS: the heavy work leaves the boot window, so the budget-hoist apparatus (RecoveryBudgetGuard + StepBootMigrate stamp + parked-skip, cc660280f) becomes SECOND-LINE defense — kept, because it still covers floor-migrate deaths and unknown boot crashes. (3) THE 'BLIND' OBJECTION (doc-027): startup applies only the daemon's operating floor; the real delta runs inside the deliberate, classified, rollback-capable pipeline. (4) STATBUS-144 SHRINKS STRUCTURALLY: a broken DELTA migration never runs on a flagless boot (it is above floor) — the exit-20 alive-idle branch (:1977-2013) remains only for broken FLOOR migrations (our own upgrade-lifecycle migrations, rare and small).
---

author: architect
created: 2026-07-07 09:24
---
DESIGN ANALYSIS 2/2 — (d) costs/risks, (e) who-reads-what trace, THE ATOMICITY FLIP, composition with 096 #6, build order.

THE ATOMICITY FLIP (the one consequence that must be ratified, not slipped in). 'At-target' is DEFINED as db.migration max ≥ on-disk max (verifyUpgradeObservedStateEx :2482-2486; 'migrations missing with a reachable DB' is a POSITIVE Behind verdict by design, :2439-2443). Today that read almost always says AtNew on a resume because boot-migrate already applied the delta. Under the floor strategy the delta is pending until pipeline step 3.5 succeeds — so EVERY mid-delta failure or death now reads positively Behind → the DESIGNED pre-completion disposition: one-shot data-safe snapshot restore (maintenance on, read-only window on, stopped-DB backup; recoverFromFlag Resuming arm :1045-1052, postSwapFailure :5025-5027). Concretely: daemon death mid-delta → next pass floor-no-op → obs Behind → rolled_back. DB OOM-killed mid-delta → migrate fails → obs unreadable (db dead) → one more pass → EnsureDBUp revives → obs Behind → rolled_back: the delta ran ONCE. Ceiling → rolled_back on the first fire. Upgrades become effectively ATOMIC; the death budget still governs pre-swap and rollback-resume crashes. NAMED COST of the flip: a TRANSIENT blip mid-delta (psql conn hiccup, db alive) also rolls the whole upgrade back — no bounded retry for the delta step — costing a wasted multi-hour run + restore where today one forward retry might have completed. That is the fail-toward-safety posture the King states; it is the core tradeoff AC#1 asks him to ratify.

(d) REMAINING COSTS/RISKS: (1) Floor sufficiency — held by the mechanical relation-set scan + empirical floor test + 42703 fail-open backstops (comment #1a). (2) SAME-RELEASE ORDERING: if a release ships a daemon-table migration timestamped AFTER heavy migrations in the SAME release, those heavies ride the boot window up to the floor. Mitigation: discipline (daemon-table migrations get early timestamps within a release) + the floor test names offenders. Common case unaffected. (3) 017 half-applied migrations: above-floor → boot skips them; the pipeline re-hit classifies (exit 20 → Behind → the same snapshot restore, now at the classified site). At/below floor → today's 017-defer unchanged (:1972). The 067 committed-but-unrecorded case: dbMax < diskMax → Behind → rollback — same terminal as today, reached more directly. (4) Scenario churn: the park oracle's kill window moves BACK to the pipeline migrate step — a partial revert to the original committed construction (8641445eb), not new design. (5) Self-heal canary: HasPending=true until the delta applies → the canary never short-circuits a delta-pending resume (:6019-6022) — correct by construction.

(e) WHO READS WHAT DURING THE WINDOW: the delta applying later exposes NO new-version container to pre-delta schema. Verified order in applyPostSwap: db up (3.3) → reconnect (3.4) → MIGRATE (3.5, :5347/:5421) → THEN app/worker/rest start (3.6, :5460+). App/worker/rest are stopped from pre-swap step 3 until 3.6, so they only ever boot post-delta. Between floor and delta only the DAEMON queries the DB — floor-covered by definition. The db container running the new image against pre-delta data during 3.3-3.5 is already today's order.

COMPOSITION WITH 096 #6 (rule together): this redesign SUBSUMES THE DIRECTION HALF of the evidence-probe recommendation — rollback-on-first-occurrence for mid-delta db-death becomes STRUCTURAL (no probe needed to get the direction right). The probe remains as the NAMING + LATENCY refinement: it lets the failure reason say 'the database was killed by the OS while migration <v> ran' instead of a bare Behind-rollback narrative, and it can shortcut the one extra unreadable→Behind pass. It also simplifies under this design: ONE site (:5421's failure handler) instead of two. Recommendation: approve BOTH; build order = minimal-boot-migrate FIRST (it moves the classification site the probe attaches to), probe second as a small follow-up. The 096 single-OOM arc contract then flips to rolled_back-on-first-kill — which makes the King's original 071 map cell wording ('OOM → rolls back') literally true, now by structure rather than by classification.
---

author: architect
created: 2026-07-08 13:48
---
BUILD SEQUENCED (architect, 2026-07-08, on the King's PROCEED ruling): the four-slice plan is in this ticket's Implementation Plan — slice 1 floor substrate (const + bump-guard + empirical floor test, zero behavior change), slice 2 the geometry change (the atomicity flip ships here, with doc-021/diagrams AND the contract-flipping arc assertions in the SAME commit), slice 3 the 096 evidence probe (naming refinement at the now-single site, classifier-discipline pins), slice 4 the VM verification campaign + the park scenario's real-path rebuild (spec written after slice 2 lands) + the 071 map-cell rewording on green. Engineer builds 1-3, architect reviews each slice hands-on before commit, foreman dispatches slice 4's runs. The recurring-OOM split question is recorded SUPERSEDED by this build per the King's ruling.
---

author: architect
created: 2026-07-08 14:15
---
FLOOR-HARNESS RESIDUALS from the tester's for-the-record run (2026-07-08; durable entries per the flags-become-backlog rule):

1. PROVISIONING GAP + SHAPE RULING: the empirical test's provisioning recipe as designed is not executable — `./sb migrate up` targets only the config-file databases; there is no arbitrary-database affordance. RULED: the empirical test becomes SELF-PROVISIONING in-process — create a throwaway DB against the test cluster, call migrate.Up (or the package internals) with migrateTo=DaemonSchemaFloor, run the Prepare enumeration, drop the DB. This removes the CLI dependency AND the split-harness DSN choreography entirely (STATBUS_FLOOR_TEST_DSN + skip-when-unset shrink to a single is-the-cluster-reachable skip). Cleaner than the blessed split — the split existed only because provisioning was assumed to ride the CLI; that assumption is now refuted, so the design follows. Small; lands as a slice-1 follow-up commit or folds into slice 2's package, builder's call. The DO-NOT-POINT-AT-HEAD vacuity note survives: the throwaway DB is migrated to exactly the floor by construction.

2. SILENT ENV-OVERRIDE FOOTGUN — spun into its own ticket (STATBUS-146): `POSTGRES_APP_DB=statbus_floor_test ./sb migrate up` SILENTLY targeted the dev database (config file wins over process env; reported 'all migrations up to date' against the WRONG database). No harm this run — dev was at HEAD — but a command that accepts an env-looking knob and quietly acts on a DIFFERENT database is the wrong-place-write class, and in the Albania frame an operator whose override is silently ignored is a real hazard. The fail-fast doctrine points at refuse-loudly (a set-but-ignored knob must either work or refuse); full framing on 146.

(CALL-prepare verdict from the tester still pending; no design change until it lands.)
---

author: foreman
created: 2026-07-08 14:15
---
SLICE 1 SHIPPED 67565f60b (2026-07-08), dual-reviewed (architect ship-with-changes — all four applied: the package-wide enumeration gap [retention_plan/retention_apply from exec.go], the whole-SQL-surface scope rule, the self-consistency exclusion principle, the completeness-sweep test that makes one-file enumeration structurally unrepeatable; foreman first-hand test/vet/build). FOR-THE-RECORD EMPIRICAL RUN (tester, dev DB — schema-identical to floor while floor==tree max): ALL 10 entries PREPARE CLEAN, exit 0. THE CALL QUESTION RESOLVED: pgx protocol-level Parse resolves all three CALL entries (supersede_older, supersede_completed_prereleases, retention_apply) — the ::regprocedure fallback is NOT needed. Harness mechanics proven end-to-end; the run becomes schema-meaningful automatically once ordinary migrations accumulate above the floor. TWO HARNESS FINDINGS routed to the architect for this ticket's residual list: (1) the provisioning recipe isn't executable as designed — ./sb migrate up cannot target an arbitrary database; likely fix = the test provisions itself in-process via the migrate package; (2) FOOTGUN: POSTGRES_APP_DB env override is SILENTLY ignored in favor of the config file (the command reported against dev while apparently pointed elsewhere) — the wrong-place-write class, possibly its own ticket. SLICE 2 (the atomicity flip) in build now.
---

author: foreman
created: 2026-07-08 14:54
---
SLICE 2 SHIPPED cb356663d (2026-07-08) — THE GEOMETRY CHANGE IS IN, dual-reviewed in two halves (architect ship on the code core with the WIDENED-SCOPE finding: postSwapFailure + parkForDeterministicFailure also read observed-state, so ALL pre-delta resume failures now roll back and park shrinks to guard-parks + post-delta at-target — doc'd; architect ship-with-one-change on the truth half). Both boot sites → --to DaemonSchemaFloor (AC#3 checked; step-table stays apply-all); flip invariant structurally pinned (pipeline migrate step stays apply-all forever); HasPendingAbove + flagless loud line; behaviorally inert today (floor==tree max). ATOMICITY FLIP is EMERGENT — zero new code at the disposition site. doc-021 + both diagrams updated in-commit (AC#5 checked). FOUR arcs gated [PENDING-145-REDERIVE] (loud named skip before any VM cost; map re-tagged, no gated cell shows [PROVEN]): between-migrations, mid-migration, OOM (terminal flip = mechanic's, lands with slice 4), and MID-TX — added by the closing review on stale-proof grounds (its proven PATH no longer exists under 145; its recorded rationale mis-described its own construction; corrected to the mechanism-independent invariant: any parent death in the migration window leaves the ledger unadvanced → Behind → rolled_back). Ceiling arc un-gated + gained the single-fire leg (exactly one ceiling marker per journal). Gates are TIME-BOUNDED: slice 4 must remove them. NEXT: slice 3 (evidence probe) to the engineer; architect writes the park-rebuild spec against the committed geometry; then slice 4's oracle dispatches.
---

author: foreman
created: 2026-07-08 15:18
---
SLICE 3 SHIPPED 9b4710900 (2026-07-08), dual-reviewed (architect ship-with-changes; foreman first-hand). The 096 evidence probe at the single migrate-failure site: structured docker inspect + bounded postmaster-log tail, PER-LEG AFFIRMATIVE notes — the originally-ruled conjunction was found structurally NEAR-MUTE by the architect's adversarial trace (the two legs describe different kill anatomies that rarely co-occur: backend-OOM logs but doesn't exit the container; container-kill exits but silences the logger) and split so each leg claims only its own observed fact (OOMKilled → causal memory wording; bare exit-137 → facts only, innocent grace-kill possible; log-constant alone → backend death, no memory claim). Probe never touches disposition. TWO RIDERS: the empirical floor test's silent skip is now a SELF-ENFORCING TRIGGER (floor < tree max + DSN unset → FAIL with the provisioning recipe — the guard that finally matters can never be silently skipped); migrate.Up's doc comment records its real contract (create-db baseline required — bare CREATE DATABASE fails at the auth schema; all=true required for multi-migration catch-up) — both facts established by RUNNING the comment-#4 self-provisioning ruling and refuting it (the split DSN harness stays, re-ruled). SLICES 1-3 ALL SHIPPED. Remaining: slice 4 — the oracle campaign (four gated arcs + ceiling single-fire + regression set + the health-park arc, in build now per doc-029 Rev 2 with the mechanic's V3 correction adopted).
---

author: foreman
created: 2026-07-11 20:21
---
STATUS SYNC (foreman, 2026-07-11): status corrected To Do → In Progress — this has been the campaign's center for three days. SHIPPED: slice 1 (67565f60b: DaemonSchemaFloor + bump-guard + completeness sweep + empirical floor test), slice 2 (cb356663d: both boot sites floor-bounded --to DaemonSchemaFloor; the apply-all flip invariant structurally pinned at applyPostSwap), slice 3 (9b4710900: per-leg OOM evidence probe). SLICE 4 (the oracle campaign) RESULTS, all on the 071 map: the atomicity flip is RUN-PROVEN — mid-delta death → Behind → rolled_back (between-migrations run 28976918080; OOM run 28955342618 — the King's original 'rolls back' wording literally true); pre-delta death → STATBUS-017 defer → forward → completed (mid-migration + mid-tx, run 28980487041, re-proven as hard contracts wave 4); ceiling single-fire proven wave 1. The PARK LEG is proven through the first park + parked-skip boots + siren-once (wave 7). REMAINING FOR FULL ACCEPTANCE: the health-park arc's complete green (un-park→re-park + fix-release legs) — blocked by STATBUS-154's final fix (the convicted markCurrentVersionCompleted writer), whose package is in build; wave 8 is the closing oracle. One [ASSESS] map note stands (mid-V1-inside-the-resume's-delta — variant arc only on the King's ask).
---
<!-- COMMENTS:END -->
