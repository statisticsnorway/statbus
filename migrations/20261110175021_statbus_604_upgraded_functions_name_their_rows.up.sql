-- STATBUS-604: bring a database upgraded from v2026.11.3 to the same five
-- function bodies a fresh database gets.
--
-- STATBUS-604 made every whole-table UPDATE/DELETE name its rows, partly by
-- editing released migrations in place (declared at the release cut). A fresh
-- database replays those edited files; an upgraded one applied the released
-- files long ago, so it keeps the old bodies, whose bare whole-table statements
-- pg_safeupdate refuses. The function-by-function comparison of a fresh seed
-- with a database migrated by v2026.11.3 and then upgraded found exactly these
-- five (tmp/604-fn-drift.txt); views, triggers, constraints and indexes match.
--
-- The bodies below are the fresh seed's definitions (\sf). Each whole-table
-- statement says WHERE true with the reason beside it.
BEGIN;

CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
BEGIN
    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- First NULL out all batch_seq, then re-assign to relevant rows.
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL WHERE true$$, p_data_table_name); -- every row: renumbered below
        
        EXECUTE format($$
            WITH numbered AS (
                SELECT row_id, 
                       ((row_number() OVER (ORDER BY row_id) - 1) / %2$L + 1)::INTEGER as batch_num
                FROM public.%1$I
                WHERE action = 'use'
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER
            WHERE true -- every row: the analysis phase numbers all rows
        $$, p_data_table_name, p_batch_size);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$function$
;

CREATE OR REPLACE PROCEDURE public.statistical_history_period_refresh()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    DELETE FROM public.statistical_history_period WHERE true; -- every row: rebuilt below from get_statistical_history_periods()
    INSERT INTO public.statistical_history_period (resolution, year, month, prev_stop, curr_start, curr_stop)
    SELECT resolution, year, month, prev_stop, curr_start, curr_stop FROM public.get_statistical_history_periods();
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.timesegments_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_is_partial_refresh BOOLEAN;
    v_establishment_ids INT[]; v_legal_unit_ids INT[]; v_enterprise_ids INT[]; v_power_group_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments WHERE true; -- every row: rebuilt below from timesegments_def
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
        -- Full refresh: record all years from the new timesegments
        INSERT INTO public.timesegments_years (year)
        SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
        FROM public.timesegments AS t
        ON CONFLICT (year) DO NOTHING;
    ELSE
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            v_power_group_ids := public.int4multirange_to_array(p_power_group_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
        END IF;
        -- Partial refresh: record years from the batch's timesegments (O(batch_size))
        -- Handles historical data: extracts actual years from whatever dates are processed.
        INSERT INTO public.timesegments_years (year)
        SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
        FROM public.timesegments AS t
        WHERE (p_establishment_id_ranges IS NOT NULL AND t.unit_type = 'establishment' AND t.unit_id = ANY(v_establishment_ids))
           OR (p_legal_unit_id_ranges IS NOT NULL AND t.unit_type = 'legal_unit' AND t.unit_id = ANY(v_legal_unit_ids))
           OR (p_enterprise_id_ranges IS NOT NULL AND t.unit_type = 'enterprise' AND t.unit_id = ANY(v_enterprise_ids))
           OR (p_power_group_id_ranges IS NOT NULL AND t.unit_type = 'power_group' AND t.unit_id = ANY(v_power_group_ids))
        ON CONFLICT (year) DO NOTHING;
    END IF;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the staging cache
    -- is empty (fresh install, unclean shutdown of the UNLOGGED table). A
    -- full rebuild drops the whole cache first: slots whose units no longer
    -- exist are never dirty and would otherwise keep counting in the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_unit_facet_staging WHERE true; -- every row: a full-range derive rebuilds all staging
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    IF v_dirty_hash_slots IS NOT NULL THEN
        -- One child per partition range holding a dirty slot, the same ranges
        -- as the full rebuild (STATBUS-543).
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (d.slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM unnest(v_dirty_hash_slots) AS d(slot)
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_apply(IN p_replace boolean DEFAULT false)
 LANGUAGE plpgsql
 SET enable_mergejoin TO 'off'
AS $procedure$
DECLARE
    v_up_to bigint := (SELECT flushed_generation FROM worker.statistical_history_facet_delta_state);
BEGIN
    LOCK TABLE public.statistical_history_facet_delta_staging IN EXCLUSIVE MODE;
    IF p_replace THEN
        DELETE FROM public.statistical_history_facet_delta WHERE true; -- every row: p_replace rebuilds the delta table
    END IF;

    IF to_regclass('pg_temp.hd_sum') IS NOT NULL THEN DROP TABLE pg_temp.hd_sum; END IF;
    CREATE TEMP TABLE hd_sum AS
    SELECT unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           sum(exists_added_count)::int AS exists_added_count, sum(exists_removed_count)::int AS exists_removed_count,
           sum(countable_added_count)::int AS countable_added_count, sum(countable_removed_count)::int AS countable_removed_count,
           sum(exists_moved_in_count)::int AS exists_moved_in_count, sum(exists_moved_out_count)::int AS exists_moved_out_count,
           sum(countable_moved_in_count)::int AS countable_moved_in_count, sum(countable_moved_out_count)::int AS countable_moved_out_count,
           sum(births)::int AS births, sum(deaths)::int AS deaths, sum(name_change_count)::int AS name_change_count,
           sum(primary_activity_category_change_count)::int AS primary_activity_category_change_count,
           sum(secondary_activity_category_change_count)::int AS secondary_activity_category_change_count,
           sum(sector_change_count)::int AS sector_change_count, sum(legal_form_change_count)::int AS legal_form_change_count,
           sum(physical_region_change_count)::int AS physical_region_change_count,
           sum(physical_country_change_count)::int AS physical_country_change_count,
           sum(physical_address_change_count)::int AS physical_address_change_count,
           sum(unit_size_change_count)::int AS unit_size_change_count, sum(status_change_count)::int AS status_change_count,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_delta)) AS stats_delta,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_month)) AS stats_ended_month,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_year)) AS stats_ended_year,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.statistical_history_facet_delta_staging
     WHERE generation <= v_up_to
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

    -- The dimensions are nullable, and IS NOT DISTINCT FROM cannot drive a hash join; their row as text
    -- (NULL renders empty, '' renders quoted) is an exact key that can, so the MERGE stays linear.
    MERGE INTO public.statistical_history_facet_delta AS t
    USING hd_sum AS s
       ON t.unit_type = s.unit_type AND t.on_month = s.on_month
      AND ROW(t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text = ROW(s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        exists_added_count = t.exists_added_count + s.exists_added_count,
        exists_removed_count = t.exists_removed_count + s.exists_removed_count,
        countable_added_count = t.countable_added_count + s.countable_added_count,
        countable_removed_count = t.countable_removed_count + s.countable_removed_count,
        exists_moved_in_count = t.exists_moved_in_count + s.exists_moved_in_count,
        exists_moved_out_count = t.exists_moved_out_count + s.exists_moved_out_count,
        countable_moved_in_count = t.countable_moved_in_count + s.countable_moved_in_count,
        countable_moved_out_count = t.countable_moved_out_count + s.countable_moved_out_count,
        births = t.births + s.births,
        deaths = t.deaths + s.deaths,
        name_change_count = t.name_change_count + s.name_change_count,
        primary_activity_category_change_count = t.primary_activity_category_change_count + s.primary_activity_category_change_count,
        secondary_activity_category_change_count = t.secondary_activity_category_change_count + s.secondary_activity_category_change_count,
        sector_change_count = t.sector_change_count + s.sector_change_count,
        legal_form_change_count = t.legal_form_change_count + s.legal_form_change_count,
        physical_region_change_count = t.physical_region_change_count + s.physical_region_change_count,
        physical_country_change_count = t.physical_country_change_count + s.physical_country_change_count,
        physical_address_change_count = t.physical_address_change_count + s.physical_address_change_count,
        unit_size_change_count = t.unit_size_change_count + s.unit_size_change_count,
        status_change_count = t.status_change_count + s.status_change_count,
        stats_delta = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_delta IS NULL THEN s.stats_delta
                           WHEN s.stats_delta IS NULL THEN t.stats_delta
                           ELSE public.jsonb_stats_delta_merge(t.stats_delta, s.stats_delta) END),
        stats_ended_month = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_month IS NULL THEN s.stats_ended_month
                           WHEN s.stats_ended_month IS NULL THEN t.stats_ended_month
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_month, s.stats_ended_month) END),
        stats_ended_year = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_year IS NULL THEN s.stats_ended_year
                           WHEN s.stats_ended_year IS NULL THEN t.stats_ended_year
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_year, s.stats_ended_year) END),
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT (unit_type, primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
        exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
        exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
        births, deaths, name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
        physical_region_change_count, physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year, unit_ids)
      VALUES (s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
        s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id, s.on_month,
        s.exists_added_count, s.exists_removed_count, s.countable_added_count, s.countable_removed_count,
        s.exists_moved_in_count, s.exists_moved_out_count, s.countable_moved_in_count, s.countable_moved_out_count,
        s.births, s.deaths, s.name_change_count, s.primary_activity_category_change_count,
        s.secondary_activity_category_change_count, s.sector_change_count, s.legal_form_change_count,
        s.physical_region_change_count, s.physical_country_change_count, s.physical_address_change_count,
        s.unit_size_change_count, s.status_change_count, s.stats_delta, s.stats_ended_month, s.stats_ended_year,
        worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.statistical_history_facet_delta WHERE cardinality(unit_ids) = 0;

    IF EXISTS (SELECT 1 FROM public.statistical_history_facet_delta_staging WHERE generation > v_up_to) THEN
        DELETE FROM public.statistical_history_facet_delta_staging WHERE generation <= v_up_to;
    ELSE
        TRUNCATE public.statistical_history_facet_delta_staging;
    END IF;
END;
$procedure$
;

END;
