-- Down Migration 20260305191438: directional_change_propagation
BEGIN;

-- Restore original derive_statistical_unit function (without changed_* keys in payload)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
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
    v_child_priority BIGINT;
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

    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
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
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
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
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs', array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs', array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs', array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan power_group IDs', array_length(v_orphan_power_group_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0
           OR COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0
           OR COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            );
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            FOR v_batch IN SELECT * FROM _batches LOOP
                v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
                v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
                v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);

            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    PERFORM worker.notify_pipeline_progress();

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );
END;
$function$;

-- Restore original statistical_unit_refresh_batch (without directional propagation)
CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_power_group_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
    v_power_group_id_ranges int4multirange;
BEGIN
    IF jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_enterprise_ids FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_legal_unit_ids FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'establishment_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_establishment_ids FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'power_group_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_power_group_ids FROM jsonb_array_elements_text(payload->'power_group_ids') AS value;
    END IF;

    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);
    v_power_group_id_ranges := public.array_to_int4multirange(v_power_group_ids);

    RAISE DEBUG 'Processing batch % with % enterprises, % legal_units, % establishments, % power_groups',
        v_batch_seq,
        COALESCE(array_length(v_enterprise_ids, 1), 0),
        COALESCE(array_length(v_legal_unit_ids, 1), 0),
        COALESCE(array_length(v_establishment_ids, 1), 0),
        COALESCE(array_length(v_power_group_ids, 1), 0);

    CALL public.timepoints_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_years_refresh_concurrent();

    IF v_establishment_id_ranges IS NOT NULL THEN
        CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    END IF;
    IF v_legal_unit_id_ranges IS NOT NULL THEN
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    END IF;
    IF v_enterprise_id_ranges IS NOT NULL THEN
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);
    END IF;
    IF v_power_group_id_ranges IS NOT NULL THEN
        CALL public.timeline_power_group_refresh(p_unit_id_ranges => v_power_group_id_ranges);
    END IF;

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
END;
$procedure$;

END;
