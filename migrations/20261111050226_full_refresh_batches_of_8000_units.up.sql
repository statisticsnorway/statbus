-- Migration 20261111050226: full refresh batches of 8000 units (STATBUS-614)
BEGIN;

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        -- Change sets of up to 8000 units: work paid once per refresh batch is cheaper with fewer batches, and
        -- 451 batches still keep four workers busy to the end. Full register (3,118,352 units, 4 workers), same
        -- rows at every size: 1000 units 3,162 batches 607/599 s; 2000 565/581 s; 4000 548/534 s; 8000 514/526/514 s;
        -- 16000 517 s with 15 s batches (STATBUS-614). The filtered path below keeps its own size.
        FOR v_batch IN SELECT * FROM public.get_temporally_closed_change_sets(p_target_change_set_size => 8000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.change_set_seq,
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
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
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
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                -- The history deltas lose the unit's contribution here; the flush never sees it again.
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'enterprise', p_unit_ids => v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('enterprise', id)
                FROM unnest(v_orphan_enterprise_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'legal_unit', p_unit_ids => v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('legal_unit', id)
                FROM unnest(v_orphan_legal_unit_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'establishment', p_unit_ids => v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('establishment', id)
                FROM unnest(v_orphan_establishment_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'power_group', p_unit_ids => v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('power_group', id)
                FROM unnest(v_orphan_power_group_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._change_sets') IS NOT NULL THEN DROP TABLE _change_sets; END IF;
            CREATE TEMP TABLE _change_sets ON COMMIT DROP AS
            SELECT * FROM public.get_temporally_closed_change_sets(
                p_target_change_set_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot(t.unit_type, t.unit_id)
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _change_sets AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _change_sets AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _change_sets AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _change_sets) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _change_sets) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _change_sets) AS t);

                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            FOR v_batch IN SELECT * FROM _change_sets LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.change_set_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until,
                        -- A child reads changed ranges only intersected with its own batch units
                        -- (worker.statistical_unit_refresh_batch), so each child carries just that
                        -- intersection. NULL stays NULL ("no filter"); a non-NULL range set stays
                        -- non-NULL, possibly '{}' ("nothing of this type changed").
                        'changed_establishment_id_ranges', (p_establishment_id_ranges
                            * COALESCE(public.array_to_int4multirange(v_batch.establishment_ids), '{}'::int4multirange))::text,
                        'changed_legal_unit_id_ranges', (p_legal_unit_id_ranges
                            * COALESCE(public.array_to_int4multirange(v_batch.legal_unit_ids), '{}'::int4multirange))::text,
                        'changed_enterprise_id_ranges', (p_enterprise_id_ranges
                            * COALESCE(public.array_to_int4multirange(v_batch.enterprise_ids), '{}'::int4multirange))::text
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot('power_group', pg_id)
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
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
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- BLOCK B: *_used_derive() calls removed. See worker.derive_used_tables
    -- (spawned as a serial child of derive_units_phase AFTER flush_staging).

    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$function$
;

CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: ANALYZE and use the generic view-based approach
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units
        FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)',
                v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size,
                round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    ELSE
        -- Partial refresh: Pre-materialize filtered tables to avoid O(n²) scan
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        -- Drop staging tables if exist from previous run (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        DROP TABLE IF EXISTS pg_temp.timesegments_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);

        -- The batch's enterprise segments, materialized and analyzed like the filtered timelines below: both
        -- joins read them once per enterprise, and statistics that undercount timesegments (a cloned database,
        -- an earlier rolled-back load) planned a scan of every enterprise segment per enterprise instead, growing
        -- with the square of the batch (3,000 enterprises 22 s, 500 enterprises 0.27 s; STATBUS-614).
        CREATE TEMP TABLE timesegments_filtered ON COMMIT DROP AS
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until
        FROM public.timesegments AS t
        WHERE t.unit_type = 'enterprise'::public.statistical_unit_type
          AND t.unit_id = ANY(v_unit_ids);
        CREATE INDEX ON pg_temp.timesegments_filtered (unit_id, valid_from);
        ANALYZE pg_temp.timesegments_filtered;

        -- Pre-filter timeline_legal_unit to only rows for these enterprises
        -- Use UNLOGGED for cross-session visibility (enables concurrency > 1)
        CREATE UNLOGGED TABLE public.timeline_legal_unit_filtered AS
        SELECT tlu.*
        FROM public.timeline_legal_unit tlu
        WHERE tlu.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_legal_unit_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_legal_unit_filtered;

        -- Pre-filter timeline_establishment to only rows for these enterprises
        CREATE UNLOGGED TABLE public.timeline_establishment_filtered AS
        SELECT tes.*
        FROM public.timeline_establishment tes
        WHERE tes.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_establishment_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_establishment_filtered;

        -- Delete existing rows for these units
        DELETE FROM public.timeline_enterprise
        WHERE unit_type = 'enterprise' AND unit_id = ANY(v_unit_ids);

        -- Insert using pre-filtered temp tables
        -- This is the timeline_enterprise_def query but using temp tables
        INSERT INTO public.timeline_enterprise
        WITH aggregation AS (
            SELECT ten.enterprise_id,
                ten.valid_from,
                ten.valid_until,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
                public.array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
                public.array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
                public.array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
                public.array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
                COALESCE(public.jsonb_stats_merge_agg(COALESCE(public.jsonb_stats_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.enabled,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                FROM pg_temp.timesegments_filtered t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) ten
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_legal_unit
            LEFT JOIN LATERAL (
                SELECT tlu_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tlu_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tlu_f.data_source_codes) AS data_source_codes,
                    public.array_distinct_concat(tlu_f.related_establishment_ids) AS related_establishment_ids,
                    public.array_distinct_concat(tlu_f.excluded_establishment_ids) AS excluded_establishment_ids,
                    public.array_distinct_concat(tlu_f.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE NOT tlu_f.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE tlu_f.used_for_counting) AS included_legal_unit_ids,
                    public.jsonb_stats_merge_agg(tlu_f.stats_summary) FILTER (WHERE tlu_f.used_for_counting) AS stats_summary
                FROM public.timeline_legal_unit_filtered tlu_f
                WHERE tlu_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                GROUP BY tlu_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tlu ON true
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_establishment
            LEFT JOIN LATERAL (
                SELECT tes_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tes_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tes_f.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT tes_f.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE NOT tes_f.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE tes_f.used_for_counting) AS included_establishment_ids,
                    public.jsonb_stats_merge_agg(tes_f.stats_summary) FILTER (WHERE tes_f.used_for_counting) AS stats_summary
                FROM public.timeline_establishment_filtered tes_f
                WHERE tes_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tes_f.valid_from, tes_f.valid_until)
                GROUP BY tes_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tes ON true
            GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
            SELECT
                (SELECT array_agg(DISTINCT ids.id) FROM (
                    SELECT unnest(basis.data_source_ids) AS id
                    UNION
                    SELECT unnest(aggregation.data_source_ids) AS id
                ) ids) AS data_source_ids,
                (SELECT array_agg(DISTINCT codes.code) FROM (
                    SELECT unnest(basis.data_source_codes) AS code
                    UNION ALL
                    SELECT unnest(aggregation.data_source_codes) AS code
                ) codes) AS data_source_codes,
                basis.unit_type,
                basis.unit_id,
                basis.valid_from,
                basis.valid_to,
                basis.valid_until,
                basis.name,
                basis.birth_date,
                basis.death_date,
                basis.search,
                basis.primary_activity_category_id,
                basis.primary_activity_category_path,
                basis.primary_activity_category_code,
                basis.secondary_activity_category_id,
                basis.secondary_activity_category_path,
                basis.secondary_activity_category_code,
                basis.activity_category_paths,
                basis.sector_id,
                basis.sector_path,
                basis.sector_code,
                basis.sector_name,
                basis.legal_form_id,
                basis.legal_form_code,
                basis.legal_form_name,
                basis.physical_address_part1,
                basis.physical_address_part2,
                basis.physical_address_part3,
                basis.physical_postcode,
                basis.physical_postplace,
                basis.physical_region_id,
                basis.physical_region_path,
                basis.physical_region_code,
                basis.physical_country_id,
                basis.physical_country_iso_2,
                basis.physical_latitude,
                basis.physical_longitude,
                basis.physical_altitude,
                basis.domestic,
                basis.postal_address_part1,
                basis.postal_address_part2,
                basis.postal_address_part3,
                basis.postal_postcode,
                basis.postal_postplace,
                basis.postal_region_id,
                basis.postal_region_path,
                basis.postal_region_code,
                basis.postal_country_id,
                basis.postal_country_iso_2,
                basis.postal_latitude,
                basis.postal_longitude,
                basis.postal_altitude,
                basis.web_address,
                basis.email_address,
                basis.phone_number,
                basis.landline,
                basis.mobile_number,
                basis.fax_number,
                basis.unit_size_id,
                basis.unit_size_code,
                basis.status_id,
                basis.status_code,
                basis.used_for_counting,
                basis.last_edit_comment,
                basis.last_edit_by_user_id,
                basis.last_edit_at,
                basis.has_legal_unit,
                aggregation.related_establishment_ids,
                aggregation.excluded_establishment_ids,
                aggregation.included_establishment_ids,
                aggregation.related_legal_unit_ids,
                aggregation.excluded_legal_unit_ids,
                aggregation.included_legal_unit_ids,
                basis.enterprise_id,
                basis.primary_establishment_id,
                basis.primary_legal_unit_id,
                CASE WHEN basis.used_for_counting THEN aggregation.stats_summary ELSE '{}'::jsonb END AS stats_summary
            FROM (
                SELECT
                    t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    (t.valid_until - '1 day'::interval)::date AS valid_to,
                    t.valid_until,
                    COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text) AS name,
                    COALESCE(plu.birth_date, pes.birth_date) AS birth_date,
                    COALESCE(plu.death_date, pes.death_date) AS death_date,
                    to_tsvector('simple'::regconfig, COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text)) AS search,
                    COALESCE(plu.primary_activity_category_id, pes.primary_activity_category_id) AS primary_activity_category_id,
                    COALESCE(plu.primary_activity_category_path, pes.primary_activity_category_path) AS primary_activity_category_path,
                    COALESCE(plu.primary_activity_category_code, pes.primary_activity_category_code) AS primary_activity_category_code,
                    COALESCE(plu.secondary_activity_category_id, pes.secondary_activity_category_id) AS secondary_activity_category_id,
                    COALESCE(plu.secondary_activity_category_path, pes.secondary_activity_category_path) AS secondary_activity_category_path,
                    COALESCE(plu.secondary_activity_category_code, pes.secondary_activity_category_code) AS secondary_activity_category_code,
                    COALESCE(plu.activity_category_paths, pes.activity_category_paths) AS activity_category_paths,
                    COALESCE(plu.sector_id, pes.sector_id) AS sector_id,
                    COALESCE(plu.sector_path, pes.sector_path) AS sector_path,
                    COALESCE(plu.sector_code, pes.sector_code) AS sector_code,
                    COALESCE(plu.sector_name, pes.sector_name) AS sector_name,
                    COALESCE(plu.data_source_ids, pes.data_source_ids) AS data_source_ids,
                    COALESCE(plu.data_source_codes, pes.data_source_codes) AS data_source_codes,
                    COALESCE(plu.legal_form_id, pes.legal_form_id) AS legal_form_id,
                    COALESCE(plu.legal_form_code, pes.legal_form_code) AS legal_form_code,
                    COALESCE(plu.legal_form_name, pes.legal_form_name) AS legal_form_name,
                    COALESCE(plu.physical_address_part1, pes.physical_address_part1) AS physical_address_part1,
                    COALESCE(plu.physical_address_part2, pes.physical_address_part2) AS physical_address_part2,
                    COALESCE(plu.physical_address_part3, pes.physical_address_part3) AS physical_address_part3,
                    COALESCE(plu.physical_postcode, pes.physical_postcode) AS physical_postcode,
                    COALESCE(plu.physical_postplace, pes.physical_postplace) AS physical_postplace,
                    COALESCE(plu.physical_region_id, pes.physical_region_id) AS physical_region_id,
                    COALESCE(plu.physical_region_path, pes.physical_region_path) AS physical_region_path,
                    COALESCE(plu.physical_region_code, pes.physical_region_code) AS physical_region_code,
                    COALESCE(plu.physical_country_id, pes.physical_country_id) AS physical_country_id,
                    COALESCE(plu.physical_country_iso_2, pes.physical_country_iso_2) AS physical_country_iso_2,
                    COALESCE(plu.physical_latitude, pes.physical_latitude) AS physical_latitude,
                    COALESCE(plu.physical_longitude, pes.physical_longitude) AS physical_longitude,
                    COALESCE(plu.physical_altitude, pes.physical_altitude) AS physical_altitude,
                    COALESCE(plu.domestic, pes.domestic) AS domestic,
                    COALESCE(plu.postal_address_part1, pes.postal_address_part1) AS postal_address_part1,
                    COALESCE(plu.postal_address_part2, pes.postal_address_part2) AS postal_address_part2,
                    COALESCE(plu.postal_address_part3, pes.postal_address_part3) AS postal_address_part3,
                    COALESCE(plu.postal_postcode, pes.postal_postcode) AS postal_postcode,
                    COALESCE(plu.postal_postplace, pes.postal_postplace) AS postal_postplace,
                    COALESCE(plu.postal_region_id, pes.postal_region_id) AS postal_region_id,
                    COALESCE(plu.postal_region_path, pes.postal_region_path) AS postal_region_path,
                    COALESCE(plu.postal_region_code, pes.postal_region_code) AS postal_region_code,
                    COALESCE(plu.postal_country_id, pes.postal_country_id) AS postal_country_id,
                    COALESCE(plu.postal_country_iso_2, pes.postal_country_iso_2) AS postal_country_iso_2,
                    COALESCE(plu.postal_latitude, pes.postal_latitude) AS postal_latitude,
                    COALESCE(plu.postal_longitude, pes.postal_longitude) AS postal_longitude,
                    COALESCE(plu.postal_altitude, pes.postal_altitude) AS postal_altitude,
                    COALESCE(plu.web_address, pes.web_address) AS web_address,
                    COALESCE(plu.email_address, pes.email_address) AS email_address,
                    COALESCE(plu.phone_number, pes.phone_number) AS phone_number,
                    COALESCE(plu.landline, pes.landline) AS landline,
                    COALESCE(plu.mobile_number, pes.mobile_number) AS mobile_number,
                    COALESCE(plu.fax_number, pes.fax_number) AS fax_number,
                    COALESCE(plu.unit_size_id, pes.unit_size_id) AS unit_size_id,
                    COALESCE(plu.unit_size_code, pes.unit_size_code) AS unit_size_code,
                    COALESCE(plu.status_id, pes.status_id) AS status_id,
                    COALESCE(plu.status_code, pes.status_code) AS status_code,
                    COALESCE(plu.used_for_counting, pes.used_for_counting, false) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    plu.legal_unit_id IS NOT NULL AS has_legal_unit,
                    en.id AS enterprise_id,
                    pes.establishment_id AS primary_establishment_id,
                    plu.legal_unit_id AS primary_legal_unit_id
                FROM pg_temp.timesegments_filtered t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                -- Use temp table for primary legal unit lookup
                LEFT JOIN LATERAL (
                    SELECT tlu_f.*
                    FROM public.timeline_legal_unit_filtered tlu_f
                    WHERE tlu_f.enterprise_id = en.id
                      AND tlu_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                    ORDER BY tlu_f.valid_from DESC, tlu_f.legal_unit_id DESC
                    LIMIT 1
                ) plu ON true
                -- Use temp table for primary establishment lookup
                LEFT JOIN LATERAL (
                    SELECT tes_f.*
                    FROM public.timeline_establishment_filtered tes_f
                    WHERE tes_f.enterprise_id = en.id
                      AND tes_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tes_f.valid_from, tes_f.valid_until)
                    ORDER BY tes_f.valid_from DESC, tes_f.establishment_id DESC
                    LIMIT 1
                ) pes ON true
                -- Pick the most recent edit from enterprise, primary legal unit, or primary establishment
                LEFT JOIN LATERAL (
                    SELECT all_edits.edit_comment,
                           all_edits.edit_by_user_id,
                           all_edits.edit_at
                    FROM ( VALUES
                        (en.edit_comment, en.edit_by_user_id, en.edit_at),
                        (plu.last_edit_comment, plu.last_edit_by_user_id, plu.last_edit_at),
                        (pes.last_edit_comment, pes.last_edit_by_user_id, pes.last_edit_at)
                    ) all_edits(edit_comment, edit_by_user_id, edit_at)
                    WHERE all_edits.edit_at IS NOT NULL
                    ORDER BY all_edits.edit_at DESC
                    LIMIT 1
                ) last_edit ON true
                WHERE t.unit_id = ANY(v_unit_ids)
            ) basis
            JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id
                AND basis.valid_from = aggregation.valid_from
                AND basis.valid_until = aggregation.valid_until
        )
        SELECT
            unit_type,
            unit_id,
            valid_from,
            valid_to,
            valid_until,
            name,
            birth_date,
            death_date,
            search,
            primary_activity_category_id,
            primary_activity_category_path,
            primary_activity_category_code,
            secondary_activity_category_id,
            secondary_activity_category_path,
            secondary_activity_category_code,
            activity_category_paths,
            sector_id,
            sector_path,
            sector_code,
            sector_name,
            data_source_ids,
            data_source_codes,
            legal_form_id,
            legal_form_code,
            legal_form_name,
            physical_address_part1,
            physical_address_part2,
            physical_address_part3,
            physical_postcode,
            physical_postplace,
            physical_region_id,
            physical_region_path,
            physical_region_code,
            physical_country_id,
            physical_country_iso_2,
            physical_latitude,
            physical_longitude,
            physical_altitude,
            domestic,
            postal_address_part1,
            postal_address_part2,
            postal_address_part3,
            postal_postcode,
            postal_postplace,
            postal_region_id,
            postal_region_path,
            postal_region_code,
            postal_country_id,
            postal_country_iso_2,
            postal_latitude,
            postal_longitude,
            postal_altitude,
            web_address,
            email_address,
            phone_number,
            landline,
            mobile_number,
            fax_number,
            unit_size_id,
            unit_size_code,
            status_id,
            status_code,
            used_for_counting,
            last_edit_comment,
            last_edit_by_user_id,
            last_edit_at,
            has_legal_unit,
            related_establishment_ids,
            excluded_establishment_ids,
            included_establishment_ids,
            related_legal_unit_ids,
            excluded_legal_unit_ids,
            included_legal_unit_ids,
            ARRAY[enterprise_id] AS related_enterprise_ids,
            ARRAY[]::integer[] AS excluded_enterprise_ids,
            CASE WHEN used_for_counting THEN ARRAY[enterprise_id] ELSE ARRAY[]::integer[] END AS included_enterprise_ids,
            enterprise_id,
            primary_establishment_id,
            primary_legal_unit_id,
            stats_summary
        FROM enterprise_with_primary_and_aggregation
        ORDER BY unit_type, unit_id, valid_from;

        -- Clean up staging tables (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        DROP TABLE IF EXISTS pg_temp.timesegments_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);
    END IF;
END;
$procedure$
;

END;
