---
id: STATBUS-119
title: >-
  seed-not-reproducible: reference-table audit columns default to
  build-wall-clock
status: Done
assignee: []
created_date: '2026-06-30 21:53'
updated_date: '2026-07-01 11:48'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
worker.tasks (architect, 2026-07-01; from STATBUS-116 AC#4 residual — determination (i) migration-spawned, NOT worker-daemon; spot-confirmed: PERFORM worker.spawn at migrations 20260520204526:359 + 20260521112759:201). TWO reproducibility sub-details, neither a build-determinism BUG: (a) worker.tasks.scheduled_at = created_at + interval '1 day' (the cleanup bootstrap tasks import_job_cleanup/task_cleanup) is build-wall-clock-relative → another build-wall-clock-baked seed value, same class as the audit-default timestamps; pinning the build epoch (SOURCE_DATE_EPOCH) stabilizes it too. (b) DEV-vs-HERMETIC discrepancy (engineer catch): the collect_changes bootstrap task shows state=COMPLETED in the DEV statbus_seed (dev.sh's worker on statbus_local executed it) but stays PENDING in the hermetic/shipped seed + the migrate-only verify harness (the daemon never connects to the build DBs). So the DEV-built seed carries execution state the shipped seed doesn't → dev seed != shipped seed in worker.tasks state. The shipped hermetic seed is CONSISTENT (always pending) and correctly carries bootstrap task DEFINITIONS, not execution history. Minor: doesn't affect the AC#4 control (uses the verify harness) or shipped-seed reproducibility; a dev-path caveat. No quiesce needed (no daemon on hermetic build DBs by construction).

VIEW-DEPARSE non-idempotence (architect, 2026-07-01; from STATBUS-116 AC#4 INCR-vs-FULL schema diff) — a THIRD structural (non-timestamp) seed-reproducibility source. pg_get_viewdef is NOT a textual fixed-point across dump->restore: public.statistical_unit_def gains a redundant `::statistical_unit_type AS statistical_unit_type` alias on 6 UNION-branch targets in the restored/incremental seed vs the fresh full seed (alias == inferred column name -> behaviorally inert; data+ledger green corroborate). EMPIRICAL ONE-OFF: 1 of 100 views (142 UNIONs); narrow trigger = a type-cast-literal column whose inferred name equals the type, on a non-first UNION branch. STABLE one-round-trip fixed-point (the explicit alias is stored in the re-created view rule -> re-dump reproduces it -> no accumulating drift). Inherent to restored(incremental)-vs-fresh(full) representation; even epoch-pinning won't equalize it (not wall-clock). Semantically identical. KEY: information_schema.views.view_definition is ALSO pg_get_viewdef -> a catalog-introspection schema oracle does NOT escape this; the only fixes are deparse-normalization or canonicalize-by-round-trip. AC#4 dispositioned (architect): (a) targeted, SAFE cast-type-alias normalization in the S1 schema normalizer (collapse `::<type> AS <type>` -> `::<type>` only when the alias equals the cast type's own name).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED as a RED HERRING (King's ruling, 2026-07-01). The premise was wrong: this chased BYTE-reproducibility of the seed, but Postgres pg_dump is LOGICALLY reproducible, not byte-reproducible — proven by our own two full-from-empty builds producing different bytes (the PG18 \restrict nonce + audit timestamps) while being logically identical. Byte-reproducibility is neither achievable (Postgres doesn't provide it) nor needed: the build caching keys on the SOURCE fingerprint (commit + migrations — STATBUS-116's seedMeta), not output bytes; and the AC#4 identity gate already compares LOGICAL equivalence (strips the nonce, excludes audit timestamps, normalizes the redundant view alias). "The drift in recorded time is ok as long as the dump is logically identical" (King) — and it is. The three findings (audit-column build-wall-clock defaults; worker.tasks.scheduled_at; view-deparse non-idempotence) are all logical-equivalence-preserving representational noise, correctly handled by the AC#4 semantic digest. NO ACTION. (Sub-note if ever relevant: the DEV-vs-hermetic worker.tasks STATE difference — collect_changes completed in dev, pending in shipped — is a dev-tooling artifact, not a shipped-seed issue; the shipped hermetic seed is logically consistent.)
<!-- SECTION:FINAL_SUMMARY:END -->
