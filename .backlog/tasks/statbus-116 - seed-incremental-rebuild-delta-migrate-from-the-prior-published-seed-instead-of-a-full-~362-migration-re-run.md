---
id: STATBUS-116
title: >-
  seed-incremental-rebuild: delta-migrate from the prior published seed instead
  of a full ~362-migration re-run
status: In Progress
assignee:
  - engineer
created_date: '2026-06-30 16:47'
updated_date: '2026-06-30 21:07'
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
- [ ] #1 When a prior published seed is available AND the fingerprint of migrations <= its recorded version matches, the seed build restores the prior seed, applies only the delta migrations, and re-dumps — no full from-empty re-run
- [ ] #2 On fingerprint mismatch (a migration <= prior version was retroactively edited/removed) OR no prior seed exists, the build falls back to a full rebuild from empty
- [ ] #3 A periodic full-baseline rebuild path exists to bound drift accumulation (cadence or explicit trigger)
- [ ] #4 The incrementally-built seed is verified identical to a full-rebuild seed (schema + data fingerprint)
- [ ] #5 Measured: a warm incremental seed build drops from ~2m to seconds; recorded in the task
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
<!-- COMMENTS:END -->
