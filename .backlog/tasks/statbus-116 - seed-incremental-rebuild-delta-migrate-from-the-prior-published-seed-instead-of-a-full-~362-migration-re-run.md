---
id: STATBUS-116
title: >-
  seed-incremental-rebuild: delta-migrate from the prior published seed instead
  of a full ~362-migration re-run
status: In Progress
assignee:
  - engineer
created_date: '2026-06-30 16:47'
updated_date: '2026-06-30 20:11'
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
