-- Down Migration 20260203145248: optimize_affected_groups_unnest_join
--
-- Restore original "= ANY(array)" pattern (slower but original behavior)

BEGIN;

CREATE OR REPLACE FUNCTION public.get_closed_group_batches(
    p_target_batch_size integer DEFAULT 1000,
    p_establishment_ids integer[] DEFAULT NULL::integer[],
    p_legal_unit_ids integer[] DEFAULT NULL::integer[],
    p_enterprise_ids integer[] DEFAULT NULL::integer[],
    p_offset integer DEFAULT 0,
    p_limit integer DEFAULT NULL
)
RETURNS TABLE(
    batch_seq integer, 
    group_ids integer[], 
    enterprise_ids integer[], 
    legal_unit_ids integer[], 
    establishment_ids integer[], 
    total_unit_count integer,
    has_more boolean
)
LANGUAGE plpgsql
AS $get_closed_group_batches$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
    v_batches_returned INT := 0;
    v_skipped INT := 0;
    v_has_more BOOLEAN := FALSE;
BEGIN
    v_filter_active := (p_establishment_ids IS NOT NULL 
                       OR p_legal_unit_ids IS NOT NULL 
                       OR p_enterprise_ids IS NOT NULL);
    
    -- Use temp table to accumulate IDs (O(n) instead of O(n²) array concatenation)
    IF to_regclass('pg_temp._batch_accumulator') IS NOT NULL THEN DROP TABLE _batch_accumulator; END IF;
    CREATE TEMP TABLE _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;
    
    FOR v_group IN 
        WITH 
        all_groups AS (
            SELECT * FROM public.get_enterprise_closed_groups()
        ),
        affected_enterprise_ids AS (
            SELECT UNNEST(p_enterprise_ids) AS enterprise_id
            WHERE p_enterprise_ids IS NOT NULL
            UNION
            SELECT DISTINCT lu.enterprise_id
            FROM public.legal_unit lu
            WHERE lu.id = ANY(p_legal_unit_ids) AND p_legal_unit_ids IS NOT NULL
            UNION
            SELECT DISTINCT COALESCE(lu.enterprise_id, es.enterprise_id)
            FROM public.establishment es
            LEFT JOIN public.legal_unit lu ON es.legal_unit_id = lu.id
            WHERE es.id = ANY(p_establishment_ids) AND p_establishment_ids IS NOT NULL
        ),
        affected_groups AS (
            SELECT DISTINCT g.group_id
            FROM all_groups g
            CROSS JOIN affected_enterprise_ids ae
            WHERE ae.enterprise_id = ANY(g.enterprise_ids)
        )
        SELECT 
            g.group_id,
            g.enterprise_ids,
            g.legal_unit_ids,
            g.establishment_ids,
            g.total_unit_count
        FROM all_groups g
        WHERE NOT v_filter_active OR g.group_id IN (SELECT group_id FROM affected_groups)
        ORDER BY g.total_unit_count DESC, g.group_id
    LOOP
        IF v_current_batch_size > 0 
           AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size 
        THEN
            -- Check if we've hit the limit
            IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                v_has_more := TRUE;
                EXIT;  -- Stop processing, we have more batches available
            END IF;
            
            -- Check if we should skip this batch (offset)
            IF v_skipped < p_offset THEN
                v_skipped := v_skipped + 1;
                -- Reset for next batch without returning
                v_current_batch_seq := v_current_batch_seq + 1;
                v_current_batch_size := 0;
                TRUNCATE _batch_accumulator;
            ELSE
                -- Output current batch
                SELECT 
                    v_current_batch_seq,
                    array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
                    array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                    array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                    array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                    v_current_batch_size,
                    FALSE  -- has_more will be updated later if needed
                INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                FROM _batch_accumulator ba;
                RETURN NEXT;
                v_batches_returned := v_batches_returned + 1;
                
                -- Reset for next batch
                v_current_batch_seq := v_current_batch_seq + 1;
                v_current_batch_size := 0;
                TRUNCATE _batch_accumulator;
            END IF;
        END IF;
        
        -- Insert unnested arrays into temp table
        INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
        INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
        INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(v_group.legal_unit_ids);
        INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(v_group.establishment_ids);
        
        v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
    END LOOP;
    
    -- Handle final batch if not already exited due to limit
    IF v_current_batch_size > 0 AND NOT v_has_more THEN
        -- Check if we've hit the limit
        IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
            v_has_more := TRUE;
        ELSIF v_skipped < p_offset THEN
            -- This final batch should be skipped, but check if there's nothing after
            v_has_more := FALSE;
        ELSE
            -- Output final batch
            SELECT 
                v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size,
                FALSE
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
            FROM _batch_accumulator ba;
            RETURN NEXT;
        END IF;
    END IF;
    
    -- Update has_more flag on last returned row if we have more
    -- (This is a bit awkward but works for the caller to check)
END;
$get_closed_group_batches$;

END;
