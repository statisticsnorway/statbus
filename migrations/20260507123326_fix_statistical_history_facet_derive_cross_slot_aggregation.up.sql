-- Migration 20260507123326: fix statistical_history_facet_derive cross-slot aggregation
--
-- Pre-existing rc.42 bug. The helper INSERTs rows from
-- public.statistical_history_facet_def(p_resolution, p_year, p_month, p_hash_partition)
-- (RETURNS SETOF statistical_history_facet_partitions — i.e. PER-SLOT rows
-- carrying a hash_slot column) into public.statistical_history_facet (keyed
-- by dim+temporal sans hash_slot). When the def function emits multiple
-- rows for the same dim+temporal across slots, the INSERT violates the
-- target's UNIQUE constraints (statistical_history_facet_year_key /
-- statistical_history_facet_month_key — both partial, both keyed on
-- dim+temporal without hash_slot).
--
-- The bug is documented inline in the up migration of
-- 20260429233218_collapse_facet_reduce_to_global_merge:
--   "statistical_history_facet — public.statistical_history_facet_derive is
--    broken (it INSERTs per-slot rows from the def function into a
--    per-period-dim table, hitting the unique constraint). Use the new
--    collapsed reduce instead..."
--
-- The pipeline path was rerouted in Phase 3 (the collapsed
-- worker.statistical_history_facet_reduce now handles MERGE from
-- per-slot partitions into the per-period-dim target). The buggy
-- public.statistical_history_facet_derive remained as a (broken) operator-
-- recovery surface, mirroring public.statistical_unit_facet_derive but
-- with the per-slot/per-period-dim shape mismatch unresolved.
--
-- This migration fixes the function by aggregating across slots in the
-- SELECT — SUM each measure column and jsonb_stats_merge_agg(stats_summary),
-- GROUP BY the target's natural dim+temporal key. Result: one row per
-- (resolution, year, month, dim8) — exactly what the target table accepts.
--
-- Pattern mirrors public.statistical_unit_facet_derive:
--   1. DELETE rows in temporal scope (clears the slate inside the txn)
--   2. INSERT aggregated rows via LATERAL join over periods x def-fn
--
-- No ON CONFLICT — the target has TWO partial unique indexes (year-only
-- and year-month) and PG's ON CONFLICT can only target one. The DELETE
-- already clears all rows in scope so there is nothing to conflict with;
-- the unit version's ON CONFLICT was for concurrent-worker safety, which
-- doesn't apply to this operator-recovery surface.

BEGIN;

CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $statistical_history_facet_derive$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Clear target rows for the requested temporal scope.
    DELETE FROM public.statistical_history_facet AS shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    WHERE shf.resolution = tp.resolution
      AND shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month;

    -- Bulk INSERT with cross-slot aggregation. The def function returns
    -- per-slot rows (RETURNS SETOF statistical_history_facet_partitions);
    -- target is keyed by (resolution, year, month, dims_8). GROUP BY the
    -- target's natural key and SUM/jsonb_stats_merge_agg across slots.
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count, physical_country_change_count,
        physical_address_change_count, unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        f.resolution, f.year, f.month, f.unit_type,
        f.primary_activity_category_path, f.secondary_activity_category_path,
        f.sector_path, f.legal_form_id, f.physical_region_path,
        f.physical_country_id, f.unit_size_id, f.status_id,
        SUM(f.exists_count)::integer,
        SUM(f.exists_change)::integer,
        SUM(f.exists_added_count)::integer,
        SUM(f.exists_removed_count)::integer,
        SUM(f.countable_count)::integer,
        SUM(f.countable_change)::integer,
        SUM(f.countable_added_count)::integer,
        SUM(f.countable_removed_count)::integer,
        SUM(f.births)::integer,
        SUM(f.deaths)::integer,
        SUM(f.name_change_count)::integer,
        SUM(f.primary_activity_category_change_count)::integer,
        SUM(f.secondary_activity_category_change_count)::integer,
        SUM(f.sector_change_count)::integer,
        SUM(f.legal_form_change_count)::integer,
        SUM(f.physical_region_change_count)::integer,
        SUM(f.physical_country_change_count)::integer,
        SUM(f.physical_address_change_count)::integer,
        SUM(f.unit_size_change_count)::integer,
        SUM(f.status_change_count)::integer,
        public.jsonb_stats_merge_agg(f.stats_summary)
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) AS f
    GROUP BY f.resolution, f.year, f.month, f.unit_type,
             f.primary_activity_category_path, f.secondary_activity_category_path,
             f.sector_path, f.legal_form_id, f.physical_region_path,
             f.physical_country_id, f.unit_size_id, f.status_id;
END;
$statistical_history_facet_derive$;

END;
