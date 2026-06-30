---
id: STATBUS-119
title: >-
  seed-not-reproducible: reference-table audit columns default to
  build-wall-clock
status: To Do
assignee: []
created_date: '2026-06-30 21:53'
updated_date: '2026-06-30 21:58'
labels:
  - seed
  - incremental-seed
  - determinism
  - testing
  - STATBUS-116
dependencies:
  - STATBUS-116
references:
  - cli/cmd/seed_verify.go
  - cli/internal/migrate/fingerprint.go
  - test/install-recovery/lib/arc-helpers.sh
  - >-
    migrations/20260602070530_pin_wall_clock_reads_to_app_current_date_guc_for_deterministic_history_derivation.up.sql
  - STATBUS-116
priority: low
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The published seed image's CONTENT varies per CI build of the same commit.** Reference-table audit columns (`created_at`/`updated_at`/`edit_at`/`last_used_at`/`uploaded_at`/`discovered_at`) default to the build wall-clock (`now()`/`statement_timestamp()`/`clock_timestamp()`), so two CI builds of the *same commit* produce byte-different seeds. A real finding, **independent of STATBUS-116**, surfaced during the seed-identity adversarial verification (architect, 2026-06-30).

## Evidence
- Live catalog: **63 columns / 40 tables** carry `now()`/`clock_timestamp`/`statement_timestamp` defaults. Confirmed migration-seeded + volatile + real rows: `import_definition`, `import_mapping`, `import_source_column`, `import_data_column`, `import_step` (now() `created_at`/`updated_at`). `activity_category.created_at` = **3 distinct values over 38 days** → the default fired at migrate-time, not a literal.
- Empirically confirmed by the FULL-vs-FULL control: **schema deterministic** (✓ after `\restrict`-strip), **data diverges** (✗) purely on these audit timestamps.
- All volatile defaults are **AUDIT METADATA** — verified ZERO on semantic columns, ZERO on business-temporal (`valid_*`/`_from`/`_to`/`_until`) columns.

## Implications (reproducible builds — the King's value)
- **Not content-addressable:** the same commit's seed image differs byte-wise per build → defeats content-addressable caching / dedup of seed images.
- **Reproducible-builds principle:** a build artifact (the seed) should be a deterministic function of its *source* (the commit). Today it's a function of (commit, build-wall-clock).

## Accept vs fix
- **Accept:** tolerate per-build variance; the seed-identity gate (STATBUS-116) handles it by excluding volatile-default (audit) columns from its *semantic* comparison (architect-blessed — those columns are all benign audit metadata).
- **Fix (reproducible seed):** pin a deterministic build epoch (`SOURCE_DATE_EPOCH`/`BUILD_DATE`) so `now()`/`statement_timestamp()` resolve to a stable value during seed building → byte-reproducible seed. NOTE: even with this, the INCR-vs-FULL identity check *still* needs the audit-column exclusion (a prior-release seed pinned a different epoch than the current build).

## Prioritization (for the King)
Part of the **seed/release build-arc** + reproducible-builds; NOT the stated top priority (install/upgrade-green). Independent of STATBUS-116 (which proceeds via the audit-column exclusion regardless).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DECISION recorded: accept per-build seed variance (status quo; the STATBUS-116 seed-identity gate already tolerates it via the blessed audit-column exclusion) vs FIX it (pin a deterministic build epoch)
- [ ] #2 IF fix chosen: the seed build pins a deterministic epoch (SOURCE_DATE_EPOCH/BUILD_DATE) so now()/statement_timestamp()/clock_timestamp() resolve to a stable value during seed building — two CI builds of the SAME commit produce a byte-identical seed image (content-addressable)
- [ ] #3 Documented that the seed-identity INCR-vs-FULL check still requires the audit-column exclusion regardless of the fix (a prior-release seed pins a different epoch than the current build)
<!-- AC:END -->
