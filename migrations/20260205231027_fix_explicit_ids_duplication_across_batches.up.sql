-- Fix: explicit_*_ids were duplicated across ALL batches, destroying partitioning.
-- When concurrency > 1, multiple batches tried to DELETE+INSERT the same rows,
-- causing unique constraint violations on timesegments_pkey.
--
-- Root cause: derive_statistical_unit passed the FULL list of explicit_*_ids
-- to every batch child task. In statistical_unit_refresh_batch, these were
-- merged with the batch's own partitioned IDs, giving every batch the full set.
--
-- Fix: Handle deleted entity cleanup BEFORE batching. Compute orphan IDs
-- (requested but no longer existing) and delete their stale rows directly.
-- Batches then only contain existing entities with no overlap.

BEGIN;

-- ============================================================================
-- Part 1: Fix worker.derive_statistical_unit
-- - Clean up deleted entities BEFORE batching
-- - Remove explicit_*_ids from batch payloads
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_uncle_priority BIGINT;
    -- Orphan IDs: requested but no longer exist in base tables
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');
    -- Priority for uncle (derive_reports): lower priority (higher number), runs after parent completes
    v_uncle_priority := nextval('public.worker_task_priority_seq');

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
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
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- Find IDs that were requested but no longer exist in base tables.
        -- Delete their stale rows from derived tables directly.
        -- This keeps batches clean - only existing entities, no overlap.
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- =====================================================================
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            )
        LOOP
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

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging();
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

-- ============================================================================
-- Part 2: Simplify statistical_unit_refresh_batch
-- Remove explicit_*_ids merge - batches are now self-contained
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_refresh_batch$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
BEGIN
    -- Extract batch IDs from payload (no more explicit_*_ids merging)
    IF jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_enterprise_ids
        FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    END IF;

    IF jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_legal_unit_ids
        FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    END IF;

    IF jsonb_typeof(payload->'establishment_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_establishment_ids
        FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    END IF;

    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);

    RAISE DEBUG 'Processing batch % with % enterprises, % legal_units, % establishments',
        v_batch_seq,
        COALESCE(array_length(v_enterprise_ids, 1), 0),
        COALESCE(array_length(v_legal_unit_ids, 1), 0),
        COALESCE(array_length(v_establishment_ids, 1), 0);

    -- Call the refresh procedures for this batch
    CALL public.timepoints_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );

    CALL public.timesegments_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );

    -- Use concurrent-safe version for years
    CALL public.timesegments_years_refresh_concurrent();

    CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );
END;
$statistical_unit_refresh_batch$;

COMMIT;
