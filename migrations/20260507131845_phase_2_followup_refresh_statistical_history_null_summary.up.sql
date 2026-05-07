-- Migration 20260507131845: phase-2 follow-up — refresh statistical_history NULL summary
--
-- ## Bug being fixed
--
-- Phase 2 (migration `20260429224008_slot_keyed_statistical_history_aggregation`)
-- shipped a one-time cleanup at its tail:
--
--     DELETE FROM public.statistical_history WHERE hash_partition IS NOT NULL;
--
-- This wiped pre-existing wide-range per-slot rows (legacy rc.42 geometry)
-- so subsequent imports would write fresh per-slot rows under the new
-- singleton geometry. The cleanup did NOT touch NULL-partition summary
-- rows, on the assumption that the next reduce-cycle would re-derive them
-- from the rebuilt per-slot rows.
--
-- However: any pre-Phase-2 inflation in NULL-summary rows (e.g. from the
-- rc.42-era double-counting bugs) survived the cleanup. Imports running
-- AFTER Phase 2 only trigger derive over the date range they import — so
-- summary rows for years not touched by post-cleanup imports remain at
-- their stale (inflated) values indefinitely.
--
-- Demo (rc.02 deploy) confirms the symptom: 2023 `legal_unit` and
-- `enterprise` summary rows show `exists_count = 48` against truth = 24
-- (exact 2x inflation). Other years are clean because subsequent imports
-- re-derived them. See `tmp/mechanic-demo-drift-investigation.md`.
--
-- Phase 3 (`20260429233218`) re-derived `statistical_unit_facet` and
-- `statistical_history_facet` but explicitly skipped `statistical_history`
-- — that's where this gap lives.
--
-- ## Fix
--
-- Inline equivalent of "TRUNCATE + full re-derive + reduce", scoped to
-- statistical_history. We don't call `public.statistical_history_derive`
-- because that function has a separate rc.42-era bug (its ON CONFLICT
-- clauses target `(resolution, year, unit_type)` without `hash_partition`,
-- but every UNIQUE index on `statistical_history` partitions on
-- `hash_partition`-NULL-ness — fix tracked separately, parallels the
-- `statistical_history_facet_derive` fix in `20260507123326`).
--
-- Sequence:
--   1. TRUNCATE statistical_history fully (both NULL summary and any
--      per-slot rows).
--   2. INSERT per-slot rows from `public.statistical_history_def(resolution,
--      year, month)` for every period returned by
--      `public.get_statistical_history_periods(NULL, '-infinity', 'infinity')`.
--      Output rows carry `hash_partition = int4range(slot, slot+1)` and
--      hit the partition_*_key indexes — no ON CONFLICT needed because
--      we just emptied the table.
--   3. CALL worker.statistical_history_reduce to compute the
--      `hash_partition IS NULL` summary rollup as `SUM(per-slot)` per
--      `(resolution, year, month, unit_type)`. This is the surface the UI
--      and reports query.
--
-- Mirrors Phase 3's pattern for statistical_history_facet:
--     TRUNCATE public.statistical_history_facet;
--     CALL worker.statistical_history_facet_reduce('{}'::jsonb);
-- Adapted to statistical_history's single-table architecture (per-slot
-- rows AND summary live in the same table, distinguished by
-- hash_partition IS NULL).
--
-- ## Down migration
--
-- Re-runs the same cleanup (idempotent). The fix corrects bad data —
-- there is no "undo" without re-running the buggy code that caused the
-- inflation. Symmetric with Phase 3's down migration.

BEGIN;

-- Step 1: Wipe all rows.
TRUNCATE public.statistical_history;

-- Step 2: Re-derive per-slot rows for every period (year + year-month
-- resolutions, all years that have any statistical_unit data).
INSERT INTO public.statistical_history
SELECT h.*
  FROM public.get_statistical_history_periods(
           p_resolution := null::public.history_resolution,
           p_valid_from := '-infinity'::date,
           p_valid_until := 'infinity'::date) AS tp
  CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) AS h;

-- Step 3: Build the NULL-summary rollup from per-slot rows.
CALL worker.statistical_history_reduce('{}'::jsonb);

END;
