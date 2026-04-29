-- Migration 20260429233218: collapse facet reduce to global merge
--
-- Phase 3 of the counting-bug investigation: facet drilldown over-count.
--
-- Diagnosis (from foreman + engineer collaboration, see
-- tmp/engineer-refresh-path-trace.md and the diag logs at
-- tmp/facet-diag.log + tmp/facet-diag-r4.log):
--
-- Both worker.statistical_unit_facet_reduce and
-- worker.statistical_history_facet_reduce had a 3-path body:
--   * Path A — full refresh: TRUNCATE + INSERT from staging.
--   * Path B — scoped MERGE for ≤128 dirty hash slots, with a separate
--     DELETE step gated by `dim_tuple IN pre_dirty_dims`.
--   * Path C — full MERGE for >128 dirty, with WHEN NOT MATCHED BY SOURCE
--     THEN DELETE (geometry-agnostic global cleanup).
--
-- Path B's DELETE step is structurally incomplete: it can only reach
-- target rows whose dim+temporal tuple is in pre_dirty_dims (the snapshot
-- of staging at dirty slots, taken BEFORE children rewrite). Stale target
-- rows whose dim+temporal isn't in any subsequent drain's pre_dirty
-- cannot self-heal. Once they accumulate (e.g., from a partial-contributor
-- delete that doesn't mark all contributing slots dirty), only Path A or
-- Path C-style global cleanup can clear them. The empirical demo dump
-- showed inflated counts and phantom rows that disappear when
-- public.statistical_unit_facet_derive('-infinity', 'infinity') runs but
-- persist through the worker pipeline.
--
-- Fix: collapse all three paths into a single global MERGE matching the
-- shape of the existing Path C — `MERGE … WHEN MATCHED … WHEN NOT MATCHED
-- BY TARGET … WHEN NOT MATCHED BY SOURCE THEN DELETE`. Self-healing by
-- construction; the propagation contract becomes "every target row has
-- staging support" enforced at every reduce. The 128-slot threshold and
-- the pre_dirty_dims apparatus become dead state (left in place for this
-- RC; can be dropped in a follow-up cleanup migration once we confirm no
-- other consumer references them).
--
-- Performance: the global MERGE is bounded by O(target_size +
-- staging_size). Staging is pre-aggregated, so this is bounded by
-- distinct_dim_combos × periods. EXPLAIN ANALYZE on the demo dump (see
-- tmp/facet-perf-old.txt) shows 10.9 ms for 237 staging rows + 223 target
-- rows; the new collapsed body uses the same MERGE statement so timings
-- are identical.
--
-- One-time data cleanup at the bottom of this UP migration runs
-- public.statistical_unit_facet_derive(-inf, inf) and
-- public.statistical_history_facet_derive(-inf, inf) to clear any
-- pre-existing drift from the buggy Path B. Without this, deploy-day
-- drift would persist in target until the next derive cycle.
--
-- Procedures NOT modified:
--   * worker.derive_statistical_unit_facet (parent) — still snapshots
--     pre_dirty_dims into the staging table, which is now ignored by
--     reduce. Harmless waste; cleaned up in a follow-up.
--   * worker.derive_statistical_history_facet (parent) — same.
--   * worker.derive_statistical_unit_facet_partition (child) — unchanged.
--   * worker.derive_statistical_history_facet_period (child) — unchanged.

BEGIN;

-- ---------------------------------------------------------------------------
-- worker.statistical_unit_facet_reduce — collapse to global MERGE
-- ---------------------------------------------------------------------------
-- Diff vs in-DB definition: removes the path A (TRUNCATE+INSERT) and
-- path B (scoped MERGE+DELETE) branches. The single body is exactly the
-- former path C MERGE, run unconditionally. v_dirty_hash_slots is still
-- read for diagnostic logging in p_info but no longer affects the body.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_facet_reduce$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only. The MERGE below
    -- is geometry-agnostic and operates on the full staging-aggregate, so
    -- the dirty set no longer gates which rows get touched.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_unit_facet AS target
    USING (
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
    ) AS source
       ON target.valid_from = source.valid_from
      AND target.valid_to = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (target.count <> source.count
                      OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET count = source.count,
                        stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                     physical_region_path, primary_activity_category_path,
                     sector_path, legal_form_id, physical_country_id, status_id,
                     count, stats_summary)
             VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                     source.physical_region_path, source.primary_activity_category_path,
                     source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                     source.count, source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
END;
$statistical_unit_facet_reduce$;


-- ---------------------------------------------------------------------------
-- worker.statistical_history_facet_reduce — collapse to global MERGE
-- ---------------------------------------------------------------------------
-- Same shape change as statistical_unit_facet_reduce. Note the additional
-- end-of-procedure work (TRUNCATE dirty_hash_slots, pg_notify) that's
-- specific to this reducer — preserved verbatim from rc.42.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_facet_reduce$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_history_facet AS target
    USING (
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer AS exists_count,
            SUM(exists_change)::integer AS exists_change,
            SUM(exists_added_count)::integer AS exists_added_count,
            SUM(exists_removed_count)::integer AS exists_removed_count,
            SUM(countable_count)::integer AS countable_count,
            SUM(countable_change)::integer AS countable_change,
            SUM(countable_added_count)::integer AS countable_added_count,
            SUM(countable_removed_count)::integer AS countable_removed_count,
            SUM(births)::integer AS births,
            SUM(deaths)::integer AS deaths,
            SUM(name_change_count)::integer AS name_change_count,
            SUM(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(sector_change_count)::integer AS sector_change_count,
            SUM(legal_form_change_count)::integer AS legal_form_change_count,
            SUM(physical_region_change_count)::integer AS physical_region_change_count,
            SUM(physical_country_change_count)::integer AS physical_country_change_count,
            SUM(physical_address_change_count)::integer AS physical_address_change_count,
            SUM(unit_size_change_count)::integer AS unit_size_change_count,
            SUM(status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id
    ) AS source
       ON target.resolution = source.resolution
      AND target.year = source.year
      AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (
            target.exists_count <> source.exists_count
         OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET
            exists_count = source.exists_count,
            exists_change = source.exists_change,
            exists_added_count = source.exists_added_count,
            exists_removed_count = source.exists_removed_count,
            countable_count = source.countable_count,
            countable_change = source.countable_change,
            countable_added_count = source.countable_added_count,
            countable_removed_count = source.countable_removed_count,
            births = source.births,
            deaths = source.deaths,
            name_change_count = source.name_change_count,
            primary_activity_category_change_count = source.primary_activity_category_change_count,
            secondary_activity_category_change_count = source.secondary_activity_category_change_count,
            sector_change_count = source.sector_change_count,
            legal_form_change_count = source.legal_form_change_count,
            physical_region_change_count = source.physical_region_change_count,
            physical_country_change_count = source.physical_country_change_count,
            physical_address_change_count = source.physical_address_change_count,
            unit_size_change_count = source.unit_size_change_count,
            status_change_count = source.status_change_count,
            stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary)
        VALUES (
            source.resolution, source.year, source.month, source.unit_type,
            source.primary_activity_category_path, source.secondary_activity_category_path,
            source.sector_path, source.legal_form_id, source.physical_region_path,
            source.physical_country_id, source.unit_size_id, source.status_id,
            source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
            source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
            source.births, source.deaths,
            source.name_change_count, source.primary_activity_category_change_count,
            source.secondary_activity_category_change_count, source.sector_change_count,
            source.legal_form_change_count, source.physical_region_change_count,
            source.physical_country_change_count, source.physical_address_change_count,
            source.unit_size_change_count, source.status_change_count,
            source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);

    -- Clean up dirty partitions at the very end, after all consumers have read them.
    -- (statistical_unit_facet_reduce ran earlier in the pipeline and read dirty_hash_slots
    -- for diagnostic logging; truncating here is safe because no later step needs it.)
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$statistical_history_facet_reduce$;


-- ---------------------------------------------------------------------------
-- One-time data cleanup
-- ---------------------------------------------------------------------------
-- Pre-existing drift from the buggy Path B may have left phantom rows or
-- inflated counts in either facet target table. We reconcile by:
--
-- 1. statistical_unit_facet — call public.statistical_unit_facet_derive,
--    which DELETEs from target by temporal-overlap then INSERTs from the
--    statistical_unit_facet_def VIEW (which already aggregates across
--    slots). Geometry-clean.
--
-- 2. statistical_history_facet — public.statistical_history_facet_derive
--    is broken (it INSERTs per-slot rows from the def function into a
--    per-period-dim table, hitting the unique constraint). Use the new
--    collapsed reduce instead: TRUNCATE the target then CALL the freshly-
--    defined worker.statistical_history_facet_reduce, which MERGEs from
--    statistical_history_facet_partitions (per-slot) into the per-
--    period-dim target via WHEN NOT MATCHED BY TARGET INSERT. The MERGE
--    correctly aggregates across slots.
--
-- After this migration ships, every reduce naturally maintains the
-- invariant; this one-time run handles the transitional cleanup so
-- production deploys see a clean state.
SELECT public.statistical_unit_facet_derive('-infinity'::date, 'infinity'::date);

TRUNCATE public.statistical_history_facet;
CALL worker.statistical_history_facet_reduce('{}'::jsonb);

END;
