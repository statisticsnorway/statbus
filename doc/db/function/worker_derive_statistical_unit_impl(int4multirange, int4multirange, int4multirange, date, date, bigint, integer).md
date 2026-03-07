```sql
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit_impl(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_batch_offset integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_batches_per_wave INT;
    v_has_more BOOLEAN := FALSE;
BEGIN
    -- Get batches_per_wave setting from command_registry
    SELECT COALESCE(batches_per_wave, 10) INTO v_batches_per_wave
    FROM worker.command_registry
    WHERE command = 'derive_statistical_unit';
    
    v_is_full_refresh := (p_establishment_id_ranges IS NULL 
                         AND p_legal_unit_id_ranges IS NULL 
                         AND p_enterprise_id_ranges IS NULL);
    
    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');
    
    -- SYNC POINT: Run ANALYZE on derived tables if this is a continuation (offset > 0)
    IF p_batch_offset > 0 THEN
        RAISE DEBUG 'derive_statistical_unit_impl: Running ANALYZE sync point (offset=%)', p_batch_offset;
        CALL public.analyze_derived_tables();
    END IF;
    
    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children with offset/limit
        -- Request one extra batch to detect if there's more
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_offset := p_batch_offset,
                p_limit := v_batches_per_wave + 1  -- +1 to detect more
            )
        LOOP
            -- Check if we've processed enough for this wave
            IF v_batch_count >= v_batches_per_wave THEN
                v_has_more := TRUE;
                EXIT;  -- Stop, don't process extra batch
            END IF;
            
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
        
        -- Spawn batch children for affected groups with offset/limit
        -- Request one extra batch to detect if there's more
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}'),
                p_offset := p_batch_offset,
                p_limit := v_batches_per_wave + 1  -- +1 to detect more
            )
        LOOP
            -- Check if we've processed enough for this wave
            IF v_batch_count >= v_batches_per_wave THEN
                v_has_more := TRUE;
                EXIT;  -- Stop, don't process extra batch
            END IF;
            
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'explicit_enterprise_ids', v_enterprise_ids,
                    'explicit_legal_unit_ids', v_legal_unit_ids,
                    'explicit_establishment_ids', v_establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
        
        -- If no batches were created but we have explicit IDs, spawn a cleanup-only batch
        IF v_batch_count = 0 AND p_batch_offset = 0 AND (
            COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 OR
            COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 OR
            COALESCE(array_length(v_establishment_ids, 1), 0) > 0
        ) THEN
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', 1,
                    'enterprise_ids', ARRAY[]::INT[],
                    'legal_unit_ids', ARRAY[]::INT[],
                    'establishment_ids', ARRAY[]::INT[],
                    'explicit_enterprise_ids', v_enterprise_ids,
                    'explicit_legal_unit_ids', v_legal_unit_ids,
                    'explicit_establishment_ids', v_establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := 1;
            RAISE DEBUG 'derive_statistical_unit_impl: No groups matched, spawned cleanup-only batch';
        END IF;
    END IF;
    
    RAISE DEBUG 'derive_statistical_unit_impl: Spawned % batch children (offset=%, has_more=%)', v_batch_count, p_batch_offset, v_has_more;

    -- If there are more batches, enqueue continuation as uncle (NOT deduplicated)
    IF v_has_more THEN
        -- Enqueue continuation command with next offset (runs after current children complete)
        INSERT INTO worker.tasks (command, priority, payload)
        VALUES (
            'derive_statistical_unit_continue',  -- Different command, no deduplication conflict
            v_child_priority,  -- Same priority - runs after this task's children complete
            jsonb_build_object(
                'command', 'derive_statistical_unit_continue',
                'establishment_id_ranges', p_establishment_id_ranges::text,
                'legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                'enterprise_id_ranges', p_enterprise_id_ranges::text,
                'valid_from', p_valid_from,
                'valid_until', p_valid_until,
                'batch_offset', p_batch_offset + v_batches_per_wave
            )
        );
        RAISE DEBUG 'derive_statistical_unit_impl: Enqueued continuation with offset=%', p_batch_offset + v_batches_per_wave;
    ELSE
        -- Final wave: run final ANALYZE and enqueue derive_reports
        
        -- Refresh derived data (used flags) - always full refreshes, run synchronously
        PERFORM public.activity_category_used_derive();
        PERFORM public.region_used_derive();
        PERFORM public.sector_used_derive();
        PERFORM public.data_source_used_derive();
        PERFORM public.legal_form_used_derive();
        PERFORM public.country_used_derive();

        -- Enqueue derive_reports (runs after all statistical_unit work completes)
        PERFORM worker.enqueue_derive_reports(
            p_valid_from := p_valid_from,
            p_valid_until := p_valid_until
        );
        
        -- Run final ANALYZE before derive_reports
        CALL public.analyze_derived_tables();
        
        RAISE DEBUG 'derive_statistical_unit_impl: Final wave complete, enqueued derive_reports';
    END IF;
END;
$function$
```
