---
id: STATBUS-145
title: >-
  minimal-boot-migrate: boot catches schema up only to the daemon's floor — the
  full delta runs exactly once, inside the guarded pipeline (King redesign)
status: To Do
assignee:
  - architect
created_date: '2026-07-07 09:23'
updated_date: '2026-07-07 09:24'
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
- [ ] #3 Both boot sites switch to the bounded form (service.go:1934, install_upgrade.go:290 → migrate up --to FLOOR); the deliberate install step-table Migrations step stays apply-all (cmd/install.go:623)
- [ ] #4 Oracles re-proven: ceiling arc single-fire (1×ceiling → rolled_back, not 2×), OOM arc terminal rolled_back on first kill, park scenario kill window moved back to the pipeline migrate step
- [ ] #5 doc-021 step list + budget-boundary narrative + both diagrams updated in the same commit as the shipped change (docs describe the present)
<!-- AC:END -->

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
<!-- COMMENTS:END -->
