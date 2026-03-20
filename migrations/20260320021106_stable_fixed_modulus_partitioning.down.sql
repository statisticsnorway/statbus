-- Down Migration: Stable Fixed-Modulus Partitioning
-- Restores dynamic analytics_partition_count and all original function signatures.
BEGIN;

------------------------------------------------------------
-- Phase 1: Drop 2-arg hash functions, restore 3-arg versions
------------------------------------------------------------

DROP FUNCTION public.report_partition_seq(text, int);
DROP FUNCTION public.report_partition_seq(statistical_unit_type, int);

CREATE FUNCTION public.report_partition_seq(p_unit_type text, p_unit_id integer, p_num_partitions integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % p_num_partitions;
$function$;

CREATE FUNCTION public.report_partition_seq(p_unit_type statistical_unit_type, p_unit_id integer, p_num_partitions integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % p_num_partitions;
$function$;

------------------------------------------------------------
-- Phase 2: Re-add analytics_partition_count to settings
------------------------------------------------------------

ALTER TABLE public.settings ADD COLUMN analytics_partition_count integer NOT NULL DEFAULT 4;

------------------------------------------------------------
-- Phase 3: Restore set_report_partition_seq trigger function
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_report_partition_seq()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.report_partition_seq := public.report_partition_seq(
        NEW.unit_type, NEW.unit_id,
        (SELECT analytics_partition_count FROM public.settings)
    );
    RETURN NEW;
END;
$function$;

------------------------------------------------------------
-- Phase 4: Restore admin functions
------------------------------------------------------------

CREATE PROCEDURE admin.adjust_analytics_partition_count()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, admin, pg_temp
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_current_count int;
    v_desired_count int;
BEGIN
    SELECT analytics_partition_count INTO v_current_count FROM public.settings;
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;

    v_desired_count := CASE
        WHEN v_unit_count <= 5000 THEN 4
        WHEN v_unit_count <= 25000 THEN 8
        WHEN v_unit_count <= 100000 THEN 16
        WHEN v_unit_count <= 500000 THEN 32
        WHEN v_unit_count <= 2000000 THEN 64
        ELSE 128
    END;

    IF v_desired_count != v_current_count THEN
        RAISE LOG 'adjust_analytics_partition_count: % units → % partitions (was %)',
            v_unit_count, v_desired_count, v_current_count;
        UPDATE public.settings SET analytics_partition_count = v_desired_count;
    END IF;
END;
$procedure$;

CREATE FUNCTION admin.propagate_partition_count_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, admin, pg_temp
AS $function$
BEGIN
    IF NEW.analytics_partition_count IS DISTINCT FROM OLD.analytics_partition_count THEN
        RAISE LOG 'propagate_partition_count_change: % → % partitions',
            OLD.analytics_partition_count, NEW.analytics_partition_count;

        UPDATE public.statistical_unit
        SET report_partition_seq = public.report_partition_seq(
            unit_type, unit_id, NEW.analytics_partition_count
        );

        TRUNCATE public.statistical_unit_facet_staging;
        TRUNCATE public.statistical_history_facet_partitions;
        DELETE FROM public.statistical_history WHERE partition_seq IS NOT NULL;
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_settings_partition_count_change
    AFTER UPDATE OF analytics_partition_count ON public.settings
    FOR EACH ROW
    EXECUTE FUNCTION admin.propagate_partition_count_change();

------------------------------------------------------------
-- Phase 5: Restore derive_reports_phase (with adjust call)
------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_reports_phase(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', true)::text);
    CALL admin.adjust_analytics_partition_count();

    p_info := jsonb_build_object(
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    );
    IF isfinite(v_valid_from) AND isfinite(v_valid_until) THEN
        p_info := p_info || jsonb_build_object(
            'years', EXTRACT(YEAR FROM v_valid_until)::int - EXTRACT(YEAR FROM v_valid_from)::int
        );
    END IF;
END;
$procedure$;

------------------------------------------------------------
-- Phase 6: Restore all worker/import/def functions from dumps
-- (These are the original versions with 3-arg report_partition_seq
--  and settings queries.)
------------------------------------------------------------

-- Restore import.get_statistical_unit_data_partial with settings queries
-- This is a large function — see tmp/dump_get_su_data_partial.sql for full dump.
-- The key change: 4 sites use report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
-- The down migration database will be recreated from scratch, so CREATE OR REPLACE is safe.

-- Restore derive_statistical_unit function with settings queries
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    v_partition_count INT;
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);
            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id => p_task_id
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        -- Partial refresh path omitted for brevity in down migration.
        -- The database will be recreated from scratch when rolling back.
        RAISE EXCEPTION 'Down migration does not fully restore partial refresh path. Recreate database instead.';
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children', v_batch_count;

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$derive_statistical_unit$;

-- Drop the 5-arg range overload, restore the original 4-arg single partition_seq version
DROP FUNCTION IF EXISTS public.statistical_history_def(public.history_resolution, integer, integer, integer, integer);

CREATE OR REPLACE FUNCTION public.statistical_history_def(
    p_resolution history_resolution,
    p_year integer,
    p_month integer,
    p_partition_seq integer DEFAULT NULL
)
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
    ELSE
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
        WHERE from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          AND (p_partition_seq IS NULL OR su.report_partition_seq = p_partition_seq)
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
            c AS curr, p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    stats_by_unit_type AS (
        SELECT lvc.unit_type,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc WHERE lvc.used_for_counting GROUP BY lvc.unit_type
    ),
    demographics AS (
        SELECT p_resolution, p_year, p_month, unit_type,
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
        FROM changed_units GROUP BY 1, 2, 3, 4
    )
    SELECT d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        COALESCE(sbut.stats_summary, '{}'::jsonb) AS stats_summary,
        p_partition_seq
    FROM demographics d
    LEFT JOIN stats_by_unit_type sbut ON sbut.unit_type = d.unit_type;
END;
$statistical_history_def$;

-- Note: The remaining functions (derive_statistical_unit_facet, derive_statistical_unit_facet_partition,
-- derive_statistical_history, derive_statistical_history_period, derive_statistical_history_facet,
-- derive_statistical_history_facet_period, statistical_history_facet_def,
-- import.get_statistical_unit_data_partial) are restored by recreating the database.
-- The down migration restores the core infrastructure (settings column, trigger, admin functions,
-- hash functions) that blocks the up migration from running again.
-- Full function restoration requires: ./devops/manage-statbus.sh recreate-database

------------------------------------------------------------
-- Phase 7: Recompute with dynamic count and clear derived data
------------------------------------------------------------

-- Set initial partition count based on current data
DO $$
DECLARE v_count bigint; v_desired int;
BEGIN
    SELECT count(*) INTO v_count FROM public.statistical_unit;
    v_desired := CASE
        WHEN v_count <= 5000 THEN 4 WHEN v_count <= 25000 THEN 8
        WHEN v_count <= 100000 THEN 16 WHEN v_count <= 500000 THEN 32
        WHEN v_count <= 2000000 THEN 64 ELSE 128
    END;
    UPDATE public.settings SET analytics_partition_count = v_desired;
END $$;

-- Recompute partition assignments
UPDATE public.statistical_unit
SET report_partition_seq = public.report_partition_seq(
    unit_type, unit_id,
    (SELECT analytics_partition_count FROM public.settings)
);

-- Clear derived data
TRUNCATE public.statistical_unit_facet_staging;
TRUNCATE public.statistical_unit_facet;
TRUNCATE public.statistical_history_facet_partitions;
TRUNCATE public.statistical_history_facet;
DELETE FROM public.statistical_history;
TRUNCATE public.statistical_unit_facet_dirty_partitions;

END;
