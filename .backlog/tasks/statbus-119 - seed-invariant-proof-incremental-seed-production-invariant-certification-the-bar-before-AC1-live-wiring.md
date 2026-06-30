---
id: STATBUS-119
title: >-
  seed-invariant-proof: incremental-seed production-invariant certification (the
  bar before AC#1 live wiring)
status: To Do
assignee: []
created_date: '2026-06-30 21:53'
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
priority: medium
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The DEEPER PROOF that the incremental-seed shortcut is SOUND — the bar that must be GREEN before AC#1 (live incremental-seed wiring) is enabled.** Distinct from STATBUS-116's "clean unit" (the determinism fixes + object-diff + FULL-vs-FULL control the engineer lands tonight, which keeps incremental DISABLED). Architect adversarial verification, 2026-06-30.

## Why (what the current AC#4 gate cannot certify)
- **Governing frame:** a green digest means "the harness bug was real," NOT "the invariant is proven." The gate must *certify the production invariant*, not just stop being red.
- Fork (i) **round-trip preservation is PROVEN** (dump→restore is fingerprint-preserving; the RED was instrument bugs). So the invariant `restore(faithful prior) + delta == full` is true **by construction IFF the seed build is deterministic** — the open question.
- **Coverage gap:** the proof's V_prev = second-highest version → delta = the **single last migration**. Production (AC#1) applies delta = a **release's many new migrations** on a **restored prior-RELEASE seed**. Never exercised.
- **Determinism is NOT yet established** — a confirmed at-risk set bakes wall-clock into seed content (below).
- **Schema-oracle viability undecided** — raw `pg_dump --schema-only` is OID/creation-order-sensitive across two builds; only the `\restrict`-stripped FULL-vs-FULL control reveals whether S1 (normalized pg_dump) survives or needs a catalog-introspection oracle.

## At-risk seed content (architect scan, live-catalog verified)
CONFIRMED migration-seeded tables with **volatile `now()` audit defaults** (bake migrate-time clock → make FULL-vs-FULL legitimately diverge): `import_definition`, `import_mapping`, `import_source_column`, `import_data_column`, `import_step`. (`activity_category` etc. have volatile defaults too but are loaded via import functions — confirm whether populated in the migrate-only seed.) → **Predicts the db.migration-excluded control STILL diverges.** `app.current_date` pin (migration 20260602070530) covers DERIVATION only, NOT these audit defaults.

## The bar (each item GREEN before AC#1 enable)
1. **Object-level diff on mismatch** — never accept a RED we can't NAME (schema: differing objects; data: differing table+rows). Harden beyond the digest-prefix print.
2. **Seed determinism resolved** — decide per the audit-timestamp finding: (a) exclude `created_at/updated_at/edit_at` from the data digest as build-metadata (like `db.migration`) — simplest; or (b) pin the seed-build clock; or (c) deterministic literals in the seeding migrations. Then **FULL-vs-FULL must be GREEN.**
3. **Multi-migration delta** — apply a *release's worth* of migrations on a restored **prior-RELEASE** seed, not just the single last migration.
4. **Multiple V_prev cut points** — not a single second-highest cut.
5. **Determinism GUC + derivation handling** — pin `app.current_date` in the seed-verify build; if any build step runs worker derivation, quiesce + pin (mirror the arc's `wait_for_worker_quiesce`).
6. **Schema-oracle robustness (conditional)** — if the `\restrict`-stripped FULL-vs-FULL control still shows schema non-determinism (OID/creation-order), switch the schema dim from raw `pg_dump` bytes to an **ORDER-BY'd catalog-introspection digest** (information_schema + pg_catalog). Adopt **pending the control's classification** (don't pre-adopt). If the diff shows *genuinely different objects* → a real schema-reproducibility bug (a migration creating objects from an unordered query) → fix that migration regardless.
7. **Cross-cutting (own finding):** the arc clean-slate fingerprint (`arc-helpers.sh:209`) shares the same raw-`pg_dump` schema-oracle flaw — it strips `\restrict` but is still OID-order-exposed across builds. Apply the same schema-oracle robustness there; it affects drift-detection beyond this feature.

## Verification
- FULL-vs-FULL GREEN (determinism), then INCR-vs-FULL GREEN with a multi-migration delta across ≥2 V_prev cuts, object-diff clean. Only then is `restore(faithful prior) + delta == full` certified for the production path → AC#1 may enable.

## Prioritization note (for the King)
Part of the **seed/release build-arc**, NOT the stated top priority (install/upgrade-green). Gates AC#1's live wiring; until certified, incremental stays disabled (the STATBUS-116 clean unit already enforces this).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Object-level diff emitted on any seed-identity mismatch (named differing schema objects + data table/rows), not just digest prefixes
- [ ] #2 Seed build is DETERMINISTIC: the volatile audit-timestamp columns on migration-seeded tables (import_definition/mapping/source_column/data_column/step, +any confirmed others) are resolved (excluded as build-metadata, clock-pinned, or made literal) and FULL-vs-FULL is GREEN across repeated builds
- [ ] #3 INCR-vs-FULL proven GREEN with a MULTI-migration delta applied on a restored prior-RELEASE seed (not the single-last-migration case), across at least 2 distinct V_prev cut points
- [ ] #4 Determinism GUC (app.current_date) pinned in the seed-verify build; worker-derivation (if any build step runs it) quiesced + pinned
- [ ] #5 Schema oracle decided by the \restrict-stripped control: raw-pg_dump retained if schema-green, else switched to an ORDER-BY'd catalog-introspection digest; any genuinely-different-objects diff traced to its migration and fixed
- [ ] #6 The arc clean-slate fingerprint's shared raw-pg_dump schema-oracle flaw is addressed with the same robustness
- [ ] #7 AC#1 live incremental-seed wiring remains DISABLED until all the above are green
<!-- AC:END -->
