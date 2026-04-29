-- Migration 20260429224008: slot keyed statistical history aggregation
--
-- Per-slot storage for public.statistical_history per-partition rows.
--
-- Design intent (user-mandated):
--
-- The hash_slot column on public.statistical_unit is stable per unit.
-- Aggregations should be incrementally cacheable: changing
-- partition_count_target should NOT invalidate the cache. Before this
-- migration, statistical_history rows were keyed by hash_partition (an
-- int4range whose width was derived from a dynamically-changing target),
-- which coupled storage to a moving geometry. That coupling caused
-- double-counting when the parent's spawn shape (singleton vs wide range)
-- diverged from existing rows' geometry, and triple-counting when the
-- target itself shifted between drains. (See test 311's earlier failure:
-- year=2023 NULL summary diverged from truth by exactly the count of dirty
-- slots.)
--
-- This migration decouples storage from compute geometry:
--
--   * public.statistical_history_def now GROUPs BY (unit_type, hash_slot)
--     and emits one row per occupied (slot, unit_type) for the period,
--     stamping hash_partition := int4range(hash_slot, hash_slot+1). The
--     external signature is unchanged.
--
--   * worker.derive_statistical_history_period uses range-overlap DELETE
--     on lower(hash_partition): any stored singleton whose slot falls in
--     the child's spawn range is removed before INSERT re-populates them.
--     Geometry-agnostic: works regardless of whether the parent spawned a
--     singleton (dirty branch) or a wide range (full-rebuild branch).
--
--   * worker.derive_statistical_history_period ELSE branch's DELETE drops
--     the `hash_partition IS NULL` filter so the manual escape hatch
--     (CALL with no hash_partition payload key) cleanly replaces the
--     entire period rather than colliding on the per-slot UNIQUE
--     constraint.
--
--   * worker.derive_statistical_history_facet_period — included as a
--     no-op CREATE OR REPLACE to make the slot-keyed contract visible
--     in one place. The facet partitions table is already per-slot
--     keyed (hash_slot integer column, not a range) and its DELETE
--     already uses range-overlap on hash_slot. Behaviour unchanged.
--
-- One-time data conversion:
--
-- Pre-existing per-partition rows in public.statistical_history were
-- written at variable widths (1024, 4096, etc., depending on the target
-- value at write time). Under per-slot storage they would coexist with
-- new singleton rows and contaminate reduce. The DELETE at the bottom of
-- this migration wipes them; the next analytics drain naturally takes
-- the bail-to-full-rebuild branch (its IF-NOT-EXISTS guard fires) and
-- writes fresh per-slot rows. Reduce then rebuilds NULL summaries from
-- those. NULL summaries persist briefly until that next drain — the
-- visible (RLS-allowed) rows on the table are all NULL summaries, and
-- they remain at their pre-migration values until reduce reruns.
--
-- Procedures NOT modified (intentional):
--   * worker.derive_statistical_history (parent)
--   * worker.derive_statistical_history_facet (parent)
--   * worker.statistical_history_reduce
--   * admin.adjust_partition_count_target
--
-- The parent's spawn shape is now compute-batching only — storage is
-- uniform per-slot regardless. partition_count_target adjustments are
-- non-events for storage. The cache the user designed hash_slot for is
-- finally honoured.

BEGIN;

-- ---------------------------------------------------------------------------
-- public.statistical_history_def — per-slot output
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.statistical_history_def(p_resolution history_resolution, p_year integer, p_month integer, p_hash_partition int4range DEFAULT NULL::int4range)
 RETURNS SETOF statistical_history_type
 LANGUAGE plpgsql
AS $statistical_history_def$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE -- 'year-month'
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE public.from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          -- When computing a partition range, filter by hash_slot within the range.
          -- Use explicit half-open bounds (not <@) so the btree index on
          -- statistical_unit(hash_slot) is used at 2.2M-row scale.
          AND (p_hash_partition IS NULL
               OR (su.hash_slot >= lower(p_hash_partition)
                   AND su.hash_slot <  upper(p_hash_partition)))
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            -- hash_slot is stable per unit (function of unit_type + unit_id),
            -- so c and p (when both present) carry the same value.
            COALESCE(c.hash_slot, p.hash_slot) AS hash_slot,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    stats_by_slot AS (
        SELECT
            lvc.unit_type,
            lvc.hash_slot,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY lvc.unit_type, lvc.hash_slot
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type, hash_slot,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        COALESCE(sbs.stats_summary, '{}'::jsonb) AS stats_summary,
        -- Slot-keyed storage: each output row corresponds to exactly one slot.
        -- The hash_partition column stores int4range(hash_slot, hash_slot+1).
        int4range(d.hash_slot, d.hash_slot + 1) AS hash_partition
    FROM demographics d
    LEFT JOIN stats_by_slot sbs ON sbs.unit_type = d.unit_type AND sbs.hash_slot = d.hash_slot;
END;
$statistical_history_def$;


-- ---------------------------------------------------------------------------
-- worker.derive_statistical_history_period — range-overlap DELETE on slot
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := NULLIF(payload->>'hash_partition', '')::int4range;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    IF v_hash_partition IS NOT NULL THEN
        -- Range-overlap DELETE on the slot value: stored rows are singletons
        -- whose lower(hash_partition) equals the slot, so this matches every
        -- stored row whose slot falls in the spawn's slot range. Works for
        -- any spawn shape (singleton dirty children OR wide full-rebuild
        -- children) because storage geometry is uniform per-slot.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_partition IS NOT NULL
           AND lower(hash_partition) >= lower(v_hash_partition)
           AND lower(hash_partition) <  upper(v_hash_partition);

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_hash_partition) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        -- Manual escape hatch: full-period rebuild. The DELETE drops the
        -- `hash_partition IS NULL` filter (vs rc.42), wiping every row for
        -- the period — both the NULL summary and any per-slot rows. The
        -- INSERT then writes fresh per-slot rows from def(...). Reduce
        -- rebuilds the NULL summary on its next run.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_period$;


-- ---------------------------------------------------------------------------
-- worker.derive_statistical_history_facet_period — symmetric (no-op)
-- ---------------------------------------------------------------------------
-- The facet partitions table is already per-slot keyed (hash_slot integer
-- column, not a range). Its DELETE already uses range-overlap on
-- hash_slot. No actual change; this CREATE OR REPLACE makes the
-- slot-keyed contract visible in one place across both derive paths.
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_facet_period$;


-- ---------------------------------------------------------------------------
-- One-time geometry conversion
-- ---------------------------------------------------------------------------
-- Pre-existing per-partition rows are at variable widths (legacy of the
-- previous range-keyed storage model). Wipe them so the next analytics
-- drain takes the bail-to-full-rebuild branch (its IF-NOT-EXISTS guard
-- fires) and writes per-slot rows at the new uniform geometry. Reduce
-- rebuilds NULL summaries from those on its next run.
DELETE FROM public.statistical_history WHERE hash_partition IS NOT NULL;

END;
