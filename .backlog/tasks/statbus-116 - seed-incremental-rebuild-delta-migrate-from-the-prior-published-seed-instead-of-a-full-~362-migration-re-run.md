---
id: STATBUS-116
title: >-
  seed-incremental-rebuild: delta-migrate from the prior published seed instead
  of a full ~362-migration re-run
status: In Progress
assignee:
  - engineer
created_date: '2026-06-30 16:47'
updated_date: '2026-06-30 22:03'
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
<!-- COMMENTS:END -->
