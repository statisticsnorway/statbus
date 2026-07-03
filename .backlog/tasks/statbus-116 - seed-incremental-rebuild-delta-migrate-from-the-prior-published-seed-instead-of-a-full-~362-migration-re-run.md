---
id: STATBUS-116
title: >-
  seed-incremental-rebuild: delta-migrate from the prior published seed instead
  of a full ~362-migration re-run
status: In Progress
assignee:
  - engineer
created_date: '2026-06-30 16:47'
updated_date: '2026-07-03 20:58'
labels:
  - build-caching
  - seed
  - performance
dependencies: []
priority: medium
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build-speed caching win (King's idea, confirmed viable in the caching review — tmp/engineer-caching-review.md).

CREDIT — the existing seed caching is deliberate and good: the seedMeta content-fingerprint already decides optimally WHETHER to rebuild the seed (image-level skip, including post_restore.sql edits), and the seed reuses the db buildcache to skip the cold extension compile when warm. This task changes HOW the seed rebuilds when it MUST — it does not touch the whether-to-rebuild decision.

THE GAP: when a rebuild is needed, the seed-builder runs ALL ~362 migrations from an empty database (postgres/Dockerfile:514). That is the ~2-min tentpole of a warm image build.

THE SHORTCUT (King): restore the prior published seed image (statbus-seed:<prev>, which records its MigrationVersion V_prev in seed.json) -> `migrate up` applies ONLY migrations with version > V_prev (the migration ledger is ordered, deterministic, append-tracked, so the incremental result is byte-identical to a full re-run) -> re-dump. ~2m -> seconds.

CORRECTNESS GATE (must-have): incremental is ONLY safe if the migrations already baked into the prior seed (version <= V_prev) have NOT been retroactively edited — a changed/removed migration <= V_prev will not reapply, causing silent drift. So: fingerprint-hash the set of migrations <= V_prev and compare to the prior seed's recorded fingerprint; on ANY mismatch (or when no prior seed exists) fall back to a full rebuild from empty. Plus a periodic full-baseline rebuild to bound drift accumulation.

Net: warm seed build ~2m -> seconds, with a hard correctness fallback. Evidence + measured baseline in tmp/engineer-caching-review.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 When a prior published seed is available AND the fingerprint of migrations <= its recorded version matches, the seed build restores the prior seed, applies only the delta migrations, and re-dumps — no full from-empty re-run
- [x] #2 On fingerprint mismatch (a migration <= prior version was retroactively edited/removed) OR no prior seed exists, the build falls back to a full rebuild from empty
- [x] #3 A periodic full-baseline rebuild path exists to bound drift accumulation (cadence or explicit trigger)
- [x] #4 The incrementally-built seed is verified identical to a full-rebuild seed (schema + data fingerprint)
- [x] #5 Measured: a warm incremental seed build drops from ~2m to seconds; recorded in the task
- [ ] #6 RECOMMENDED pre-AC#1-enable check (NOT an AC#4 gate; AC#4 certifies on single-delta): before enabling incremental live, run ONE prod-shaped multi-migration-delta INCR-vs-FULL (real prior-RELEASE seed + that release's delta, vs full). Only test exercising physical-state-independence across a release's restored-base boundary; FULL-vs-FULL can't see it. NARROW/low-prob (unordered-SELECT anti-pattern) BUT high-severity (silent corrupt seed) + cheap. King gates AC#1 via Fork A.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
FOUNDATION (decision half) COMMITTED c7b0ac286. Remaining (execution half), in order:
1. AC#4 identity-check proof harness (GREENLIT, in progress) — semantic schema+data digest compare of incremental-built vs full-built seed; builds both once, not per-CI; live wiring must not flip to incremental until green.
2. AC#1 execution — restore-prior-seed + delta-migrate in postgres/Dockerfile (gated on AC#4 green + Fork A King decision).
3. AC#3 baseline — Fork B ruled B1: IncrementalDepth in seed.json (force full at depth>=N) + release=full.
4. AC#5 measurement.
PARKED FOR KING — Fork A: prior-seed selection (A1 floating base tag [rec] vs A2 ancestor-walk); correctness-neutral, build/caching-architecture call.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROBUSTNESS FOLLOW-UPS for seed-identity (architect, 2026-06-30; OPTIONAL — NOT AC#4 gates, NOT King decisions). AC#4 certifies on (proven round-trip) + (green FULL-vs-FULL) + (green INCR-vs-FULL) via the blessed audit-column exclusion. Nice-to-haves for later hardening: (1) Multi-migration delta on a restored prior-RELEASE seed + >=2 V_prev cut points (today delta = single last migration). DOWNGRADED to nicety: green FULL-vs-FULL proves every migration deterministic, and proven round-trip => INCR==FULL for any delta/V_prev by construction. (2) Sequence last_value in the digest: --schema-only excludes setval and the data digest is rows-only, so a sequence-only divergence wouldn't be CAUGHT (sound by construction via the -Fc round-trip, but unverified) -- add `SELECT last_value` per sequence. (3) Catalog-introspection schema oracle: MOOT now -- the \restrict-strip made the schema digest deterministic (FULL-vs-FULL schema GREEN, OID-order hypothesis empirically disposed), so raw-pg_dump-minus-\restrict suffices; revisit only if schema determinism regresses. (4) Audit-exclusion GUARD: the catalog rule 'exclude columns whose DEFAULT is a volatile function' is future-proof but MUST assert the excluded set is audit-only -- fail loud if a temporal-validity (valid_*/_from/_to/_until) or other semantic column ever acquires a volatile default (would silently hide real drift). Verified clean today (0 such columns). Seed-not-byte-reproducible root finding tracked separately in STATBUS-119.

CORRECTION to the robustness-followups note above (architect, 2026-06-30): multi-delta is NOT pure nicety — there is a NARROW hole. The by-construction argument assumes migrations are functions of SEMANTIC state; FULL-vs-FULL cannot verify that, because both builds migrate from empty → IDENTICAL physical layout (same OID/row order) → a PHYSICAL-state-dependent migration (an unordered SELECT whose row-order affects semantic output, e.g. id assignment) is consistently-wrong in BOTH builds → FULL-vs-FULL stays GREEN and blind to it. INCR applies the delta on a RESTORED prior (different physical layout) → such a migration would diverge. round-trip preservation is SEMANTIC (proven via the order-independent digest), NOT PHYSICAL. Single-delta INCR-vs-FULL exercises only the LAST migration's restored-base boundary; production applies MANY migrations, the FIRST on a restored prior-release base. ⇒ ONE production-shaped multi-migration-delta INCR-vs-FULL (real prior-release seed + its delta) is a NARROW GENUINE GATE for the physical-state-dependence class (recommended pre-AC#1-ship), not a hard tonight-blocker (low-probability: unordered-order-dependent SELECTs are an anti-pattern the SQL conventions discourage, and clean append-only reference data usually preserves order through -Fc dump/restore). Additional V_prev cuts beyond one = diminishing-returns hardening. AC#4 tonight is unaffected (it certifies the bug-fix + determinism); this is about AC#1's live wiring.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-30 20:44
---
FOUNDATION COMMITTED — c7b0ac286 (seed: STATBUS-116 foundation — migrations fingerprint + incremental-vs-full decision gate). The DECISION half: migrate.UpMigrationsFingerprintUpTo + seedMeta.MigrationsFingerprint (recorded by DumpSeed) + SeedBuildDecision (pure, fail-safe-to-full on every uncertainty). Build+tests green; tests cover every gate branch. The EXECUTION half is the remaining units below.

UNIT ORDER (ship bit by bit):
1. AC#4 identity-check proof harness — GREENLIT, engineer building now. Decision-agnostic (works against the existing full path). Semantic compare (pg_dump -Fc not byte-stable): normalized schema digest + per-table data digest. A ./dev.sh / `sb db seed verify-identical` that builds both seeds ONCE — NOT every CI build. SEQUENCING RULE: live Dockerfile/CI must NOT flip to incremental until this is green.
2. AC#1 execution — restore-prior-seed + delta-migrate wiring in postgres/Dockerfile. GATED on AC#4 green AND on Fork A (King).
3. AC#3 baseline — Fork B RULED B1: IncrementalDepth counter in seed.json forces full at depth>=N; release builds always --full. Internal build-detail, foreman call. Built in this unit.
4. AC#5 — measurement, recorded.

FORK A (PARKED for the King): which prior seed does an incremental restore from — A1 floating base tag `statbus-seed:incremental-base` (team rec, least CI machinery) vs A2 ancestor-walk. Correctness-NEUTRAL (gate falls back to full on any <=V_prev mismatch regardless), but it's a build/caching-architecture call the King wants. Does not block AC#4.
---

author: foreman
created: 2026-06-30 21:07
---
AC#4 harness COMMITTED — 29dd68392 (seed: STATBUS-116 seed verify-identical proof). New `sb db seed verify-identical`: S1 schema digest (normalized pg_dump --schema-only) + per-table data digest (md5 string_agg(t::text ORDER BY t::text)) + ledger pre-check; manufactures its own prior (migrate --to V_prev) so decision-agnostic; dedicated disposable statbus_seed_verify DB (never the real seed); live postgres/Dockerfile UNTOUCHED. Pure cores differentially unit-tested (6 tests, all green; foreman re-verified build/test/vet/gofmt first-hand).

AC#4 NOT YET CHECKED — the harness existing is not the proof; the RUN is the oracle. Verify run sequenced (engineer, background): `./sb db seed verify-identical`. AC#4 checks on a GREEN '✓ seed identity PROVEN' run. A RED run is a real finding (incremental drift or harness bug) — investigate, do NOT enable incremental.

After AC#4 green: AC#1 live-incremental wiring (restore-prior + delta-migrate in postgres/Dockerfile) remains gated on Fork A (parked for the King).
---

author: foreman
created: 2026-06-30 21:20
---
AC#4 RUN RED — root-caused to a HARNESS BUG, NOT real incremental drift (the proof catching the harness's own bug = test-first-as-discovery working). AC#4 stays UNCHECKED (correctly red).

Verdict per-component: schema ✗ DIFFERS, data ✗ DIFFERS, ledger ✓ MATCHES.

BUG 1 (foreman-confirmed code-level): migrateNamedDb passed all=(migrateTo==0); migrate.go:768 does `if !all && len(pending)>1 { pending = pending[:1] }`, so the PRIOR build (migrateTo=V_prev≠0 → all=false) applied only the FIRST pending migration → the manufactured 'prior' was a 1-migration STUB, not all-up-to-V_prev. The migrate.go:762 cap already bounds to V_prev, so the fix is all=TRUE always. BUG 2 (benign side-effect): migrate.Up triggered maybeRebuildTestTemplate in dev mode (rebuilt statbus_test_template; statbus_seed + dev DB untouched) — fix: set CADDY_DEPLOYMENT_MODE=standalone in migrateNamedDb.

OPEN UNEASE (why this is NOT yet settled): both INCR and FULL end at all 374 migrations (→ ledger ✓), so it is NOT obvious why a stub-prior makes schema+data differ — if migrations are deterministic, restore-then-delta should equal fresh. The engineer's 'reach them differently' is hand-wavy. So: (a) the RE-RUN with the fix is the oracle (digests are proven-sensitive → a green is trustworthy); (b) architect is adversarially verifying diagnosis-completeness + the FOUNDATIONAL invariant 'restore faithful prior + delta == full migrate' (the assumption the whole feature + AC#1 wiring rests on). AC#4 proven only on GREEN re-run + architect concurrence; still-red = real finding.
---

author: foreman
created: 2026-06-30 21:37
---
AC#4 investigation update — fork (i) RESOLVED FALSE; only (ii) remains. Engineer ran a direct dump→restore round-trip on the real statbus_seed: schema diff = ONLY 2 lines (PG18 \restrict/\unrestrict random psql tokens; 29,774 other lines identical), data 0/88 tables differ. Foreman verified /tmp/rt_schema.diff first-hand. → the seed dump→restore round-trip IS fingerprint-preserving (the architect's key worry = FALSE). The earlier RED = two NAMED harness digest-normalization bugs, NOT real drift: (1) normalizeSchemaDump doesn't strip the \restrict/\unrestrict random token; (2) the data digest includes db.migration's volatile cols (id SERIAL / applied_at now() / duration_ms). The S1 schema-digest ruling SURVIVES (the non-determinism is benign PG18 psql-meta noise, not OID-ordering / schema-reproducibility).

ONLY remaining fork: (ii) migration non-determinism (the round-trip doesn't re-run migrations). Greenlit harness fixes: strip \restrict/\unrestrict (+ a differential test) + exclude db.migration; re-run with a FULL-vs-FULL CONTROL first (real test for any residual volatile seed table), then INCR-vs-FULL. Architect running a non-determinism scan of the delta migrations. CLEAN scan + GREEN re-run ⇒ mechanism SOUND ⇒ AC#4 proven. Incremental stays DISABLED; commit HELD until the harness is deterministic + green.
---

author: foreman
created: 2026-06-30 22:52
---
AC#4 CERTIFIED + COMMITTED 2b6ca801e (seed: harden the seed verify-identical proof; certify incremental == full). The `sb db seed verify-identical` harness is now build-deterministic + round-trip-faithful, and the live single-delta run PROVES incremental == full: CONTROL FULL==FULL deterministic, then INCR-vs-FULL schema=c9e93e6a data=f08e1801 ledger=6a6f2079 ALL IDENTICAL (V_prev=20260616104500).

SCOPE (precise): AC#4 certifies SEMANTIC identity of reference data + schema between an incrementally-built and a full-rebuilt seed — build-volatile audit-timestamp columns + worker.tasks (operational queue) excluded as build-noise; at the SINGLE-DELTA last-migration restored-base boundary. NOT physical-state-independence across a release's many migrations — that's the recommended pre-AC#1-enable multi-delta check (AC#6).

The harness named + fixed, each differentially tested: BUG-1 all=true (the 1-migration-stub prior); \restrict/\unrestrict PG18 random-token strip; catalog-driven audit-column exclusion + a fail-loud SELF-GUARD (can't silently exclude a business-temporal column as the schema evolves); worker.tasks table-exclude (migration-driven deterministic, foreman-verified Dockerfile:512-516 migrate-only, no worker daemon); the round-trip pg_get_viewdef redundant-cast-alias normalize on statistical_unit_def (collapses ONLY alias==type-name, never a real rename). Control-first gates the verdict on a deterministic instrument. Foreman reviewed the full diff (seed_verify.go +346/-67, test +125) first-hand; build/test/vet/gofmt green; harness only, incremental stays DISABLED.

Three structural seed non-reproducibility findings surfaced + folded into STATBUS-119 (audit-timestamp defaults, worker.tasks scheduled_at, view-deparse non-idempotence — all semantically inert). dev-seed ≠ shipped-seed worker.tasks state noted there too.
---

author: foreman
created: 2026-07-02 06:27
---
HANDOFF STATE (2026-07-02). COMMITTED: foundation c7b0ac286 (fingerprint + SeedBuildDecision gate), AC#4 harness 29dd68392 + certified 2b6ca801e (`sb db seed verify-identical` — semantic INCR==FULL PROVEN single-delta: schema+data+ledger identical; logical-equivalence oracle, King-validated). FORK A DECIDED (King) = ANCESTOR-WALK: walk to the CLOSEST published seed; migrations/ UNCHANGED vs ancestor → reuse AS-IS (no rebuild); delta-migrate ONLY when migrations/ changed. AC#1 wiring DISPATCHED to the engineer 2026-07-02 (his warm foundation; disjoint from recovery-core): ancestor-walk + restore-prior + delta-migrate in postgres/Dockerfile, composing with AC#2 fingerprint-fallback (retro-edit ≤ancestor → FULL rebuild). CRITICAL GATE: incremental stays DISABLED behind the AC#6 pre-enable physical-state check — build the wiring, do NOT flip live (AC#4 exists; AC#6 multi-delta is the pre-enable gate). REMAINING: AC#1 wiring (in progress) → AC#6 multi-delta pre-enable check → enable + AC#3 baseline (Fork B ruled B1: IncrementalDepth in seed.json + release=full) + AC#5 measure. Robustness follow-ups (multi-V_prev, sequence-last_value digest, catalog-introspection) in the task Impl-Notes = niceties, not gates. STATBUS-119 (byte-reproducibility) CLOSED red-herring.
---

author: foreman
created: 2026-07-02 06:34
---
ARCHITECT AC#1 CONCRETE SPEC READY → tmp/plans/statbus-116-ac1-wiring-spec.md (numbered, grounded first-hand against committed code; engineer building to it, 2026-07-02). Key findings that shape the build: (1) CORRECTION — the seed-builder is a `docker build` STAGE (postgres/Dockerfile:452): no daemon, can't `docker pull`, so the Fork-A ancestor-walk runs on the HOST (CI/dev) and the prior seed is INJECTED as a build-context (idiomatic, Dockerfile:449 already does this); restore+delta+dump runs IN-STAGE via a new `sb db seed build`. This is BUILD-time (Dockerfile:514 tentpole), NOT executeUpgrade/upgrade-time. (2) Incremental = the full path + ONE optional restore step → refactor risk near-zero. (3) GAP: seed_verify.go's restoreVerifyDB uses `docker compose exec` → won't work in-stage; write a HOST-psql pg_restore variant (PgRestoreCommand, mirror PgDumpCommand). (4) GATE (centerpiece): build ALL wiring INERT; incremental stays OFF until ONE reviewable line-flip images.yaml SEED_INCREMENTAL_ENABLED=true, taken AFTER AC#6 green — default off → byte-identical to today's full rebuild; commit defaults it off. Two-gate: HOST enable-gate (AC#6) + STAGE correctness-gate (AC#2 SeedBuildDecision fallback, already committed c7b0ac286). (5) STAGING: 2 commits — (A) refactor the 3 inline Dockerfile calls into `sb db seed build` proven inert via a CI seed-image build; (B) add select-prior + incremental branch + gated images.yaml walk. Each CI-verified (the run is the oracle).
---

author: foreman
created: 2026-07-02 06:42
---
AC#1 DECISION CORE BUILT + TESTED + GATED (engineer 2026-07-02) — commit HELD for the fresh foreman's first-hand review (critical-path Go). Files (uncommitted, disjoint): cli/cmd/seed_plan.go (264) + cli/cmd/seed_plan_test.go (136). WHAT: `const SeedIncrementalEnabled = false` — the AC#6 GATE, a single greppable switch; while false, decideSeedBuild returns FULL with ZERO I/O (no git, no registry) → the live CI seed build is UNTOUCHED. decideSeedBuild(enabled, probes) is a PURE core: gate→full; else ancestor-walk (closest first-parent ancestor with a published statbus-seed image) → migrations/ unchanged vs it = REUSE as-is / changed = SeedBuildDecision (the committed AC#2 fingerprint gate) → incremental|full; any probe error → full. PlanSeedBuild(projDir) wires real probes (git rev-list --first-parent cap 50 / docker manifest inspect [remote, no pull] / git diff --quiet -- migrations / docker pull+extract ancestor seed.json). `sb db seed plan` = read-only, prints mode/prior/reason for CI. 9 differential tests on the pure core (gate-off-runs-no-I/O via fail-if-called sentinels; no-ancestor→full; closest-ancestor-wins; unchanged→reuse; changed→incremental; fingerprint-mismatch→full; probe-errors→full) + a guard that SeedIncrementalEnabled stays false until AC#6. Build/vet/gofmt/full-cli-tests GREEN. ARCHITECTURE: the ancestor-walk runs OUTSIDE the hermetic seed-builder (no .git/no docker daemon in-stage); CI resolves the plan + delivers the prior seed as a `prior-seed` build-context (mirrors the existing statbus-sb + migrations multi-context pattern, postgres/Dockerfile:447-450). SCOPING DECISION (foreman): the Dockerfile restore-prior+delta branch + images.yaml activation (the 'flip-live' surfaces) are DEFERRED to the AC#6 gate-flip — NOT built now (gated-off + CI-only-exercisable = untested rot). RECONCILIATION for the fresh foreman: the architect's spec stages an INTERMEDIATE CI-TESTABLE step (commit A = refactor the 3 inline Dockerfile seed-build calls into `sb db seed build`, proven inert via a CI seed-image build) that is distinct from the engineer's `sb db seed plan` decision-core and could land BEFORE the flip as de-risking; settle the exact staging with the architect. Engineer has the precise flip plan ready (SEED_MODE build-arg, prior-seed build-context, restore→migrate up --target seed→dump). NEXT (fresh foreman): review + commit the decision core → then the architect-spec staging (inert `sb db seed build` refactor → AC#6 multi-delta pre-enable check → flip).
---

author: foreman
created: 2026-07-02 06:47
---
⚠ COMMENT #8 IS SUPERSEDED — TREE MOVED PAST THAT REPORT (foreman first-hand, 2026-07-02). The engineer continued past his decision-core report + my stand-by. Actual `git status` now: MODIFIED cli/cmd/seed.go + cli/internal/migrate/migrate.go (LIVE files), UNTRACKED cli/cmd/seed_ancestor.go + seed_build.go + seed_build_test.go; seed_plan.go/seed_plan_test.go are GONE (restructured). So the state is NO LONGER the 'gated new-files-only, live CI build UNTOUCHED, zero-I/O-when-off' condition comment #8 describes — it now includes uncommitted modifications to LIVE files (seed.go, migrate.go) that the foreman has NOT reviewed. Likely the architect's `sb db seed build` inert-refactor (spec commit A), but UNVERIFIED. Foreman has asked the engineer to report: (1) did he see the stand-by, (2) what each changed file does, (3) PROOF the live full-rebuild path is still byte-identical when SeedIncrementalEnabled=false, (4) build/test status. DO NOT trust comment #8's 'safe' characterization until the engineer's current report + a fresh-foreman first-hand review of seed.go + migrate.go confirm the live build is untouched. Nothing committed. HANDOFF NOTE: 116 AC#1 is MID-FLIGHT, not at a clean resting point — the fresh foreman reviews the ACTUAL tree (git status + git diff cli/cmd/seed.go cli/internal/migrate/migrate.go), not the earlier decision-core-only description.
---

author: foreman
created: 2026-07-02 06:54
---
FROZEN SNAPSHOT + FIRST-HAND CHARACTERIZATION (foreman, 2026-07-02) — supersedes #8/#9. The engineer built the FULL architect-commit-A LIVE seed-build refactor, well past his 'decision core' report + two foreman stand-bys; the tree was actively churning (postgres/Dockerfile then .github/workflows/images.yaml appeared modified across successive status checks), so I sent a FREEZE. COMPLETE uncommitted 116 tree state (foreman read the diffs first-hand):
  M cli/cmd/seed.go — IncrementalDepth field (omitempty) + DumpSeed gains an incrementalDepth param; the live `seed dump` caller passes 0 → full-build seed.json is byte-identical (omitempty omits depth=0).
  M cli/internal/migrate/migrate.go — PgRestoreCommand ADDED (purely additive host-psql pg_restore variant, the architect-flagged in-stage gap; NO existing function changed — live migrate path untouched).
  M postgres/Dockerfile — LIVE seed-builder REFACTOR: the 3 inline calls (create-db; migrate up --target seed; dump) → a single `sb db seed build --commit`; adds ARG SEED_INCREMENTAL=0 (default) + a REQUIRED `prior-seed` build-context (EMPTY by default → no /build/.prior-seed/seed.json → no prior → full rebuild).
  M .github/workflows/images.yaml — wires the prior-seed build-context + SEED_INCREMENTAL knob.
  ?? cli/cmd/seed_build.go (212) — the `sb db seed build` command (calls DumpSeed + PgRestoreCommand; depth+1 bookkeeping).
  ?? cli/cmd/seed_ancestor.go (118) — `sb db seed select-prior` (the ancestor-walk).
  ?? cli/cmd/seed_build_test.go (103).
GATE DESIGN is SOUND ON INSPECTION: SEED_INCREMENTAL=0 default + empty prior-seed context → full from-empty rebuild the engineer's own Dockerfile comment claims is 'byte-identical to the pre-AC#1 3-call sequence.' THE CRITICAL CAVEAT: that byte-identical claim is UNPROVEN — this is a LIVE-PATH refactor whose ONLY oracle is a CI seed-image build, which has NOT run. Do NOT assume inert until that CI run is green. COMMITTED BASELINE UNAFFECTED (everything uncommitted; master clean at HEAD). NEXT (fresh foreman): (1) get the engineer's FROZEN report (is the tree a coherent compiling checkpoint? build/test status?), (2) review seed_build.go + seed_ancestor.go + the Dockerfile/images.yaml diffs first-hand, (3) drive the CI seed-image build to PROVE SEED_INCREMENTAL=0 == the old 3-call path (the architect's commit-A inert-proof), (4) ONLY THEN commit. Do NOT commit a live-path refactor on inspection alone. COORDINATION NOTE: the engineer is productive but ran well ahead of the stand-bys — the fresh foreman should re-establish an explicit checkpoint-before-continue cadence with him on live files.
---

author: foreman
created: 2026-07-02 15:05
---
AC#1 COMMITTED 2dc944975 (foreman review + King go-ahead, one commit — King: 1-vs-2 is fine, no review objections). Foreman reviewed seed_build.go + seed_ancestor.go FIRST-HAND and VERIFIED the load-bearing equivalence: the live full-path substitution `sb migrate up --target seed` -> `migrateNamedDb(projDir, seedDbName, 0)` is SOUND — both apply ALL migrations to the SAME database (loadSeedDbName [db.go:135] and ResolveTargetDB('seed') [migrate.go:1276] both resolve to POSTGRES_SEED_DB; migrateTo=0 -> all=true). Gate proven OFF (SEED_INCREMENTAL=0 default + empty prior-seed context -> full rebuild). resolveSeedPath pure routing correct (incremental only if enabled AND SeedBuildDecision-incremental AND prior!=nil AND depth+1<cap). Foreman re-ran build/vet/targeted-seed-tests GREEN before committing. 7 files: seed.go (IncrementalDepth field + DumpSeed 3rd param, live caller passes 0), migrate.go (PgRestoreCommand ADDED, additive), seed_ancestor.go (select-prior ancestor-walk), seed_build.go (orchestrator), seed_build_test.go (9 pure tests), postgres/Dockerfile (3 inline calls -> `sb db seed build` + required prior-seed build-context + SEED_INCREMENTAL arg), images.yaml (gated prior step). STILL UNPROVEN: the refactored full path must build GREEN in the CI seed-image job (gate off) — the inert-proof, the ONLY oracle, NOT YET RUN (needs a push). NEXT: push -> CI seed-image inert-proof GREEN -> AC#6 multi-delta pre-enable check -> the one-line flip (SEED_INCREMENTAL_ENABLED=true) + AC#3 cadence + AC#5 measure. GUARDRAIL also committed c12750b32 (pre-commit hook exempts _upgrade_arc fixtures from doc/db pairing — the King-directed replacement for the 118 --no-verify workaround).
---

author: foreman
created: 2026-07-02 15:31
---
AC#1 REFACTOR INERT-PROOF GREEN IN CI (foreman verified first-hand, 2026-07-02). Pushed origin/master (07ab1b129..1563e6887) -> Images run 28601676512 (run #303) = SUCCESS including the `seed` job. Verified the refactored path ACTUALLY RAN (NOT a cache skip) by reading the seed job log: the seed-builder stage executed `sb db seed build --commit 1563e688...` -> decision log `seed build: enable-gate=false prior-present=false decision-incremental=false -> PATH=FULL (from empty)` -> create-db -> migrate -> `Seed dumped: migration 20260617174936, commit 1563e688 (4.4 MB)` -> seed.pg_dump + seed.json asserts pass -> statbus-seed image built + pushed green. So the live seed-build refactor (`sb db seed build` replacing the 3 inline create-db/migrate/dump calls) is PROVEN INERT with the gate off — the full rebuild is unbroken end-to-end in real CI. The AC#1 REFACTOR/hosting half is DONE: committed 2dc944975 + CI-proven. The incremental FEATURE itself is NOT yet enabled/proven — AC#1 checkbox stays UNCHECKED until: AC#6 multi-delta pre-enable safety check -> the one-line flip (repo var SEED_INCREMENTAL_ENABLED=true) -> AC#5 measure + AC#3 cadence. Gate remains OFF (proven off in the CI log). Also note: the `Notify cloud services` job failed on this push (13s) — pre-existing, unrelated: it SSHes to cloud server statbus_jo and runs that server's own `./sb upgrade check` (exit 1); not introduced by this change.
---

author: foreman
created: 2026-07-02 17:48
---
AC#6 BUILD PLAN APPROVED (foreman reviewed first-hand, 2026-07-02 ~17:50) — tmp/plans/statbus-116-ac6-plan.md (engineer, grounded vs committed code). Shape: new `sb db seed verify-multidelta --prior-image <ref>` — restore a REAL published prior-RELEASE seed image (frozen physical layout from a past CI build) + that release's MANY-migration delta, vs a full from-empty rebuild; the ONLY test that can see physical-state-dependent migrations across the restored-base boundary (AC#4's manufactured-from-empty prior is structurally blind to them). Reuses the certified verify-identical apparatus verbatim (computeSeedDigest/control/verdict untouched); new code confined to seed_verify.go + a small test; ZERO live-path files; incremental stays DISABLED. FOREMAN RULING: explicit --prior-image ONLY (engineer's Option A) — no auto-select in this slice; deterministic, guarantees a genuine multi-delta, evidence records the exact release boundary proven. Two loud guards specced: eligibility (SeedBuildDecision fingerprint — refuse a retro-edited base) + multi-delta (≤1 delta → fail; cannot silently degenerate to AC#4). Engineer building; commit held for foreman review; then the RUN (real release image, live local stack) is the AC#6 oracle → GREEN + King go-ahead → the one-line flip.
---

author: foreman
created: 2026-07-02 18:08
---
AC#6 TOOLING COMMITTED 573655b81 + ORACLE RUN DISPATCHED (foreman, 2026-07-02 ~18:10). Foreman reviewed the full diff first-hand (+254/-21, seed_verify.go + test only): the priorSource refactor keeps verify-identical's flow literally intact (same secondHighestVersion→migrate-to-V_prev→dump inside manufacturedPriorSource); imagePriorSource extracts a real published seed via extractSeedFromImage + parses V_release fail-loud; BOTH guards present and loud (eligibility via SeedBuildDecision; multi-delta ≤1→refuse); delta counted from the FULL build's db.migration ledger (correct oracle); 2 new pure differential tests. Foreman re-ran build/vet/targeted tests GREEN before committing. Engineer's 3 in-spirit deviations accepted (pure-predicate tests over DB-stub; --keep-dbs parity; cobra required flag). Accepted nicety-gap: guards run AFTER the ~4-min control phase, so a bad image ref fails late — harmless for an on-demand tool. ORACLE RUN dispatched to the engineer against the operator's inventory (rc.04 c4692562 → rc.03 d0992498 → rc.02 b3db8bac if the multi-delta guard rejects closer bases). GREEN → AC#6 checks → the one-line flip goes to the King. Commit-msg hook note: 'AC#6'-style shorthand trips the bare-ticket-reference guard (hash+digits) — write 'criterion 6' in commit messages.
---

author: foreman
created: 2026-07-02 18:44
---
🔴 CRITERION-6 ORACLE RED AGAINST rc.03 — REAL DATA DRIFT CAUGHT (engineer, 2026-07-02 ~18:45; log tmp/seed-verify-multidelta-rc03.log). The full mechanism worked end-to-end: CONTROL passed (FULL==FULL deterministic → instrument valid, the RED is real), git-derived eligibility passed ('0 changed migrations ≤ V_prior=20260603093525 between d0992498 and HEAD'), multi-delta guard passed (delta=2). Then INCR-vs-FULL: schema IDENTICAL, ledger IDENTICAL, DATA DIFFERS — exactly TWO tables: public.import_data_column + public.import_mapping. Same DDL + same migrations applied, different DATA on a restored-base vs from-empty → this is precisely the physical-state-dependence class the architect predicted (task Impl-Notes CORRECTION) and criterion 6 was built to expose — invisible to the criterion-4 FULL-vs-FULL proof, visible only on a real frozen-layout prior. Without this gate, flipping incremental on would have shipped silently-divergent seeds. INCREMENTAL STAYS DISABLED. NEXT: engineer inspecting the actual differing rows (--keep-dbs re-run; captures tmp/ac6-rc03-{full,incr}-data.txt) to classify: (a) order-dependent id assignment in the populating migration = REAL seed-content bug → fix the migration; vs (b) benign surrogate-key-only difference → digest-exclusion candidate like the blessed audit-column cases — BUT that call routes through the architect (adversarial verification) + foreman; no exclusion gets blessed on the engineer's word alone. The three tooling fixes (platform pin, cold-cache cid, git-derived eligibility) stand regardless; eligibility diff held for commit with the verdict.
---

author: foreman
created: 2026-07-02 18:50
---
DRIFT DIAGNOSED (engineer, tmp/ac6-rc03-finding.md; kept DBs preserved for inspection): the RED is localized, surrogate-key-only nondeterminism — 10 rows, ALL step_id=19 (legal_relationship); natural-key content hash IDENTICAL with-and-without-id proof; GENERATED ALWAYS identity ids permuted (128-138); import_mapping diverges only by FK-following those ids. Mechanism: the step-19 import_data_column INSERT (migration 20260218215337 or a later reinsert) lacks a deterministic ORDER BY, unlike the external_idents/stat_variables generators — id assignment is physical-order-dependent. PRE-EXISTING, invisible to criterion-4 by construction. Engineer recommends FIX (add ORDER BY on a stable natural key; pre-first-release migration edit) over digest-normalization (weaker — the id is a real FK target). ROUTED TO ARCHITECT for adversarial verification before any action: completeness of 'benign' (scan ALL consumers of import_data_column.id), pin the exact INSERT file:line, rule fix-vs-normalize, and check the known prior GENERATED-ALWAYS issue in git history first. Incremental stays DISABLED; engineer moved to the 109 build meanwhile.
---

author: foreman
created: 2026-07-02 19:27
---
DRIFT FIX SHIPPED + LOCAL PROOF GREEN (foreman, 2026-07-02 ~19:27). Three commits, each foreman-reviewed first-hand: 55cae593d (git-derived eligibility for pre-fingerprint priors — validated live by the rc.03 run), 8b5912a9a (the ORDER BY derived_priority fix in migration 20260218215337 — data-only, committed via the pairing hook's own documented data-only override), b19ca9d5d (test 018: ids_follow_priority=t GREEN — enforces the invariant forward; header attributes the discovery to the multi-delta oracle; the brittle perturbation variant deliberately SKIPPED per no-flaky-tests). GREEN-PATH RULING (engineer analysis, foreman-ratified): rc.03 can never re-green post-fix — correctly (eligibility refuses the edited migration; its baked ids predate the fix); no local prior can distinguish fixed-from-unfixed (from-empty priors share FULL's layout — the same blindness that hid this from criterion 4). The TRUE confirming run = verify-multidelta against the NEXT post-fix published seed once a genuine migration delta accumulates — deferred BY CONSTRUCTION. ⇒ PENDING ON THE KING: the enable-flip timing fork — (a) wait for the deferred confirming run (conservative; the ~2min→seconds win arrives with the next migration-bearing cycle), or (b) flip earlier on test-018 + the certified single-delta proof, with the multi-delta run as a post-enable confirming gate. Criterion 6's checkbox waits for the confirming run either way.
---

author: foreman
created: 2026-07-03 11:11
---
FLIP SEQUENCE IN MOTION (King D4 flip-early ruling; foreman executing during the away window, 2026-07-03). COMMITTED: 494481aa7 (depth cap N=5 — now the PRIMARY drift bound: the release=full clause DISSOLVED under grounding, releases never build a seed, they reuse the master-push image; releases.yaml rebuilds app/worker/db/proxy only) + ce383effc (the gated flip machinery in images.yaml: on-demand git unshallow + sb-extract from the statbus-sb image, ALL inside the enabled branch after the gate's exit 0; checkout stays depth-1; disabled path byte-identical — foreman traced the diff line-by-line). INERT-PROOF RUN: images run 28656755124 (triggered by this push, variable UNSET) — must show seed job green + decision log PATH=FULL. THEN THE FLIP: `gh variable set SEED_INCREMENTAL_ENABLED --body true` → dispatch images.yaml → observe PATH=INCREMENTAL + first live incremental seed + AC-5 timing measurement. KILL-SWITCH (documented before flipping, works from any state): `gh variable set SEED_INCREMENTAL_ENABLED --body false` (or delete the variable) → the very next build is full-from-empty; no commit/revert needed; the in-stage SeedBuildDecision fingerprint gate + the empty-prior fallback additionally force FULL on any anomaly regardless of the variable.
---

author: foreman
created: 2026-07-03 11:21
---
🔴 FIRST ENABLED RUN RED → KILL-SWITCH PULLED (foreman, 2026-07-03 11:20 — ~4 min from failure to disable; the King's flip-early ruling working as intended: real exercise found a real integration gap on day one). Sequence: inert-proof run 28656755124 GREEN (gate took the disabled exit verbatim; decision log enable-gate=false → PATH=FULL; seed published at migration 20260703104910 — a POST-FIX seed, now the future prior for the deferred confirming run). Variable set true 11:16 → first enabled run 28657019171 FAILED in-stage: `migrate seed db up: released-tag detection for migration 20260218215337: git tag -l v*: exit status 128` — the restored prior evidently predates the ORDER BY fix, the ledger-hash mismatch invoked the migration-immutability/channel machinery, which needs git — and the hermetic seed-builder has NO .git by design. Variable back to FALSE 11:20; recovery run 28657218995 dispatched (expect green full-from-empty). TWO DIAGNOSIS QUESTIONS with the engineer: Q1 (load-bearing) why the decision wasn't FULL or REUSE — the ancestor walk should have picked the post-fix ce383eff seed (published minutes earlier; manifest propagation timing?) AND SeedBuildDecision's fingerprint gate must force FULL on a pre-fix prior; one gate didn't fire — trace which. Q2 (structural) the in-stage build can NEVER run the git-requiring channel machinery — an in-stage ledger mismatch must fall back to FULL (decided on the host) instead of dying. VARIABLE STAYS FALSE until both answered + fixed; re-enable = same one-variable procedure.
---

author: foreman
created: 2026-07-03 11:39
---
DIAGNOSIS COMPLETE — CORRECTS comment 19's hypotheses (engineer, tmp/statbus-116-first-enable-failure.md; foreman-reviewed). BOTH GATES FIRED CORRECTLY: the walk picked statbus-seed:ce383eff (closest published, post-fix ancestor) and the fingerprint gate rightly ruled incremental — 20260218215337.up.sql is byte-identical ce383eff↔HEAD. THE REAL DEFECT: the PUBLISHED ce383eff seed artifact is INTERNALLY INCONSISTENT — restored-ledger content_hash for 20260218215337 = cd82bc76 (PRE-fix) while its seed.json fingerprint is post-fix; the file gate compares FILES and cannot see a stale restored ledger. Suspected mechanism (to be architect-verified): a build-cache artifact in the image chain supplying pre-fix applied-migrations while seed.json regenerates from current files. STRUCTURAL GAP confirmed: migrate up's immutability check (migrate.go:1452-1519) on any restored-ledger mismatch calls the released-tag git machinery — impossible in the hermetic builder (no .git); fires only on the incremental path. ⚠ BROADER TAIL ESCALATED: a FRESH INSTALL restoring the published ce383eff seed on a real box (git present) hits the same mismatch → the channel/immutability machinery — possibly a live install issue TODAY, independent of the flip. Fix design routed to the ARCHITECT (after his 125 package): typed in-stage full-fallback (ErrStaleRestoredMigration), a dump-time consistency assert so this artifact class can never publish, deployed-severity adjudication, interim republish question. Variable stays FALSE; re-enable only after the fix + a verified-consistent published seed.
---

author: foreman
created: 2026-07-03 12:00
---
UNIFIED SEED-FIDELITY DESIGN RATIFIED (foreman) → doc-025 rev 2; ENGINEER BUILDING A-E as one package. ONE INVARIANT, TWO CARRIERS: seed-restore + migrate up must equal migrate-from-empty. Instance 1 (metadata): NOT a cache artifact — deterministic; migration 20260426220000 hardcodes 344 April-frozen hash literals, the sanctioned in-place ORDER-BY fix changed the file but no literal → EVERY from-empty build since Jul 2 ships a stale ledger hash (republish structurally useless). Instance 2 (effects): ALTER ROLE writes the CLUSTER catalog a database dump can never carry → the exemption was never armed on any seed-restored box (arc deadlock explained; mechanic's smoking gun + architect extension: the 2024 statement_timeout/lock_timeout/safeupdate role GUCs are ALSO silently missing on all seed-restored boxes today — pre-existing class). CORRECT HOME EXISTS WITH PRECEDENT: post_restore.sql already re-arms the role-membership GRANTs for exactly this class. DESIGN: A) in-run re-stamp of backfilled rows; B) DumpSeed publish gate (ledger==files or die); C) seed-build channel + typed in-stage full-fallback (no git); D) HOTFIX — delete migration 20260703104910 (no released tag; orphan rows skip benignly) + ALTER ROLE → post_restore.sql + mirror the 2024 GUCs; E) static gate blocking cluster-scoped statements in future migrations. FOREMAN RULINGS: post_restore = HARD-FAIL (fail-fast doctrine); build greenlit. SEVERITY (good news): production (old migrated installs) SAFE; stable-channel fresh installs self-heal the hash via the sanctioned bless flow; the broken-first-upgrade tail confined to arc VMs + recent seed-restored fresh installs — CAUGHT BEFORE the external standalone rollout would have shipped it to every new operator box. PROOF: two oracles after the package lands — arc re-run (D) + seed job with flip FALSE (A attested by B); only then does the King re-flip.
---

author: foreman
created: 2026-07-03 19:21
---
doc-025 SEED-FIDELITY PACKAGE COMMITTED + PUSHED: 98093f69f (11 paths). A: ledger re-stamp at content_hash column flip; B: DumpSeed publish gate (hard-fail on ledger≠files); C: UPGRADE_CHANNEL=seed-build channel + typed ErrStaleRestoredMigration → loud FULL-rebuild fallback (no git in the hermetic stage); D: migration 20260703104910 deleted (verified in no tag), 4 role-GUC ALTER ROLEs in BOTH post_restore.sql (re-arm) and init-db.sh (birth — architect-required: at-target seed restore skips the Migrations step so post_restore alone never arms at install), post_restore now HARD-FAILs; E: migration-cluster-statement-gate.sh pre-commit hook active. Reviews: architect APPROVE + foreman first-hand full read. Suite 84/85 (1 = pre-existing 092 doc drift, fixed in 447999ff9). ORACLES RUNNING: images seed job run 28679520295 (expect PATH=FULL + publish gate pass; flip still false) + arc harness run 28679526112 (working+failing). Both green → AC1-3 provable and King asked to re-flip SEED_INCREMENTAL_ENABLED=true (kill-switch unchanged, comment 18).
---

author: foreman
created: 2026-07-03 19:24
---
🟢 ORACLE 1 GREEN (images run 28679520295, seed job 85060143596, foreman verified log first-hand): decision log `enable-gate=false prior-present=false decision-incremental=false -> PATH=FULL (from empty)`; Part A fired on the exact doc-025 §1 defect — `⟳ re-stamped backfilled content_hash for migration 20260218215337: cd82bc76 → 71befa05` (April-frozen pre-fix literal corrected to the live post-ORDER-BY-fix hash at the column flip); `Seed dumped: migration 20260703111119, commit a3eb522c (4.4 MB)` — dump runs only after Part B's pre-dump assert, zero publish-gate failure text. statbus-seed:a3eb522c is the FIRST metadata-consistent published seed since Jul 2 — and the natural incremental prior once the King re-flips. Remaining oracle: arc run 28679526112 (Part D proof) still executing.
---

author: foreman
created: 2026-07-03 19:40
---
🟢 ORACLE 2 GREEN (arc run 28679526112) — BOTH doc-025 oracles now green. Working arc: seed-restored install healthy → forward-apply B completed t+55s, health check attempt 1. Failing arc: rolled_back t+79s → V_fixed completed t+58s. Zero HEALTHCHECK_REST_DOWN. Combined with oracle 1 (comment 23: PATH=FULL, re-stamp fired cd82bc76→71befa05, publish gate passed, consistent seed statbus-seed:a3eb522c published): the doc-025 comment-21 proof condition is MET. → THE RE-FLIP DECISION NOW SITS WITH THE KING: `gh variable set SEED_INCREMENTAL_ENABLED --body true` then dispatch images.yaml; expected: ancestor walk picks statbus-seed:a3eb522c (consistent prior), PATH=INCREMENTAL, AC-5 timing measured; kill-switch unchanged (set the variable false — comment 18); Part C's in-stage ErrStaleRestoredMigration fallback now guards the stale-prior class that killed run 28657019171.
---

author: foreman
created: 2026-07-03 20:01
---
KING RULING (2026-07-03, direct, in-conversation): the SEED_INCREMENTAL_ENABLED repo variable is RETIRED — no external enable flag. Reason (King): "enable the right code and test it and make sure it works." The flag was rollout scaffolding (inert wiring, 4-minute kill on the first-enable failure) and its job is done; the safety now lives entirely in code — fingerprint mismatch→FULL, stale restored prior→typed error→FULL rebuild, no prior→FULL, depth≥5→FULL, and the publish gate makes an inconsistent artifact unshippable. An external variable also made the same commit build differently from mutable side-channel state — not reproducible from the repo. NEW SHAPE: incremental enabled unconditionally in code; kill-switch = ordinary git revert of the enabling commit. ENGINEER BUILDING NOW: remove the images.yaml variable conditional (ancestor walk always runs on push), remove the enable-gate param from the decision core + the SEED_INCREMENTAL build-arg plumbing, retire the stays-false guard test. Architect glances (verify no in-code gate weakened) → foreman review+commit+push. The push's own seed job = the FIRST LIVE INCREMENTAL RUN: expect ancestor walk → statbus-seed:a3eb522c prior → PATH=INCREMENTAL → AC-5 timing measured (or a loud named fallback to FULL, also correct behavior). Operator watches.
---

author: foreman
created: 2026-07-03 20:09
---
FLAG RETIRED — COMMITTED 7910fbbbc + PUSHED (architect GO; foreman first-hand review; engineer build). 4 files, net −38: images.yaml resolves the ancestor prior unconditionally (no vars.SEED_INCREMENTAL_ENABLED, no enable build-arg); seed_build.go drops the enable-gate param (resolveSeedPath(incremental, prior)); the retired must-not-flip-live guard test is superseded by a STRICTLY STRONGER truth-table invariant (TestResolveSeedPath_IncrementalOnlyWhenAllGatesPass: exactly ONE input combination yields incremental, yesCount==1 asserted); Dockerfile drops ARG SEED_INCREMENTAL. Architect ruling recorded: prior-resolution infra errors fail the job LOUD by design — a degrade-to-empty wrapper would reintroduce ambient-state-dependent builds (the exact class removed) and mask infra failures as silent fulls. Kill-switch = git revert of 7910fbbbc. FIRST LIVE INCREMENTAL RUN in flight: images run 28681327764 — expect prior-present=true → PATH=INCREMENTAL restoring statbus-seed:a3eb522c, depth 0→1, publish gate re-attesting the incremental output, and the AC-5 timing measurement (full-path in-stage baseline ~60-70s). Operator watching with exact criteria; foreman backstop watcher running.
---

author: foreman
created: 2026-07-03 20:12
---
🟢 FIRST LIVE INCREMENTAL RUN GREEN (images run 28681327764, seed job 85065399384, foreman verified log first-hand). Evidence: `incremental base: ghcr.io/statisticsnorway/statbus-seed:a3eb522c` (ancestor walk → the consistency-attested prior); `seed build: prior-present=true decision-incremental=true -> PATH=INCREMENTAL (restore prior + delta-migrate)`, reason `migrations <= 20260703111119 unchanged since the prior seed`; `restoring prior seed … (depth 0 -> 1)`; `Seed dumped: migration 20260703111119, commit 7910fbbb (4.4 MB)` — publish gate re-attested the incremental artifact. TIMING (criterion 5): in-stage decision t+3.2s → dump complete t+19.3s ≈ 16s work, vs ~60s for the full path in the SAME stage yesterday (run 28679520295: t+3.2 → t+63.4) — and the original ~2min from-empty tentpole. Delta this run = 0 pending migrations (pure restore+re-dump). CHECKED: criterion 1 (live incremental restore+delta+re-dump, no from-empty run), criterion 2 (no-prior/mismatch→FULL — proven live in runs 28656755124 + 28679520295 where prior-absent → PATH=FULL, plus the truth-table test), criterion 3 (depth cap N=5, committed 494481aa7, depth counter now live at 1), criterion 5 (measured above). REMAINING: criterion 6 only — the deferred confirming run: `sb db seed verify-multidelta` against a post-ORDER-BY-fix published seed once a genuine multi-migration delta accumulates (per comment 17; the King's flip-early ruling made it post-enable). The feature is LIVE; kill-switch = git revert 7910fbbbc.
---

author: foreman
created: 2026-07-03 20:58
---
🟢 FIRST DELTA-MIGRATE INCREMENTAL RUN GREEN (images run 28682974989, push of c1c4cbb7a; foreman verified log first-hand) — the variant the first incremental run didn't exercise (that one had zero pending migrations). Evidence: `incremental base: ghcr.io/statisticsnorway/statbus-seed:7910fbbb` (walk found the NEWEST prior, one commit back); `PATH=INCREMENTAL (restore prior + delta-migrate)`; `restoring prior seed … (depth 1 -> 2)` — the AC-3 depth counter CHAINS live (2 of cap 5; three more chained increments force the full baseline — the designed cadence observed working); `[migrate] ▶ applying 20260703210000_add_recovery_park_degraded_columns… ✔ applied in 69ms` — a REAL migration delta applied onto the restored base; `Seed dumped: migration 20260703210000, commit c1c4cbb7 (4.4 MB)` at t+20.3s in-stage (vs ~60s full path). Publish gate re-attested the delta-built artifact. The complete lifecycle — walk → restore → delta-migrate → attest → publish, with depth chaining — is now proven on real pushes twice over. Criterion 6 (the deep verify-multidelta identity check against a published prior with a genuine multi-migration delta) is now RUNNABLE as designed: post-fix published priors with real deltas exist (a3eb522c → 7910fbbb → c1c4cbb7 chain). That run is the ticket's last open item.
---
<!-- COMMENTS:END -->
