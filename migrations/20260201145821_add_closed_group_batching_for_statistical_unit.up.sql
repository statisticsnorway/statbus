-- Migration: Add closed group batching for statistical_unit derivation
--
-- This implements batched processing of statistical_unit based on transitively
-- closed groups of EN/LU/ES. Units in different groups are completely independent
-- and can be processed separately.
--
-- Key insight: Two enterprises are in the same "closed group" if they ever shared
-- a legal unit at any point in time. This means changes to one cannot affect the other.
--
-- Benefits:
-- 1. Incremental updates: Only reprocess groups containing changed units
-- 2. Progress visibility: See batches completing
-- 3. Parallelization: Independent groups can run in parallel
-- 4. Smaller transactions: Each batch commits separately

BEGIN;

-- ============================================================================
-- PROCEDURE 0: Concurrent-safe timesegments_years refresh
-- ============================================================================
-- The original timesegments_years_refresh() is not safe for concurrent execution
-- because multiple DELETE/INSERT operations can race. This version uses
-- INSERT ... ON CONFLICT DO NOTHING to be safely called from parallel batches.

CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
LANGUAGE plpgsql
AS $timesegments_years_refresh_concurrent$
BEGIN
    -- Insert missing years (idempotent - safe for concurrent calls)
    -- Uses ON CONFLICT DO NOTHING so parallel batches don't fail on duplicates
    INSERT INTO public.timesegments_years (year)
    SELECT DISTINCT year FROM public.timesegments_years_def
    ON CONFLICT (year) DO NOTHING;

    -- Delete obsolete years (safe - multiple deletes have same effect)
    -- Only delete years that no longer exist in any timesegment
    DELETE FROM public.timesegments_years t
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years_def d WHERE d.year = t.year
    );
END;
$timesegments_years_refresh_concurrent$;

COMMENT ON PROCEDURE public.timesegments_years_refresh_concurrent() IS 
'Concurrent-safe version of timesegments_years_refresh. Safe to call from parallel batch tasks.';


-- ============================================================================
-- FUNCTION 1: Get all enterprise closed groups
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_enterprise_closed_groups()
RETURNS TABLE (
    group_id INT,
    enterprise_ids INT[],
    enterprise_count INT,
    legal_unit_ids INT[],
    legal_unit_count INT,
    establishment_ids INT[],
    establishment_count INT,
    total_unit_count INT
)
LANGUAGE sql
STABLE
AS $get_enterprise_closed_groups$
WITH RECURSIVE 
-- Build enterprise connectivity graph from LU temporal data
enterprise_edges AS (
    SELECT DISTINCT a.enterprise_id AS from_en, b.enterprise_id AS to_en
    FROM public.legal_unit a
    JOIN public.legal_unit b ON a.id = b.id
    WHERE a.enterprise_id IS NOT NULL AND b.enterprise_id IS NOT NULL
    UNION
    SELECT id, id FROM public.enterprise
),
-- Compute transitive closure
transitive_closure(from_en, to_en) AS (
    SELECT from_en, to_en FROM enterprise_edges
    UNION
    SELECT tc.from_en, e.to_en
    FROM transitive_closure tc
    JOIN enterprise_edges e ON tc.to_en = e.from_en
),
-- Assign group_id = minimum reachable enterprise_id
enterprise_to_group AS (
    SELECT from_en AS enterprise_id, MIN(to_en) AS group_id
    FROM transitive_closure
    GROUP BY from_en
),
-- Collect per group
group_enterprises AS (
    SELECT 
        group_id,
        array_agg(DISTINCT enterprise_id ORDER BY enterprise_id) AS enterprise_ids,
        COUNT(DISTINCT enterprise_id)::INT AS enterprise_count
    FROM enterprise_to_group
    GROUP BY group_id
),
group_legal_units AS (
    SELECT 
        eg.group_id,
        array_agg(DISTINCT lu.id ORDER BY lu.id) AS legal_unit_ids,
        COUNT(DISTINCT lu.id)::INT AS legal_unit_count
    FROM enterprise_to_group eg
    JOIN public.legal_unit lu ON lu.enterprise_id = eg.enterprise_id
    GROUP BY eg.group_id
),
group_establishments AS (
    SELECT 
        eg.group_id,
        array_agg(DISTINCT es.id ORDER BY es.id) AS establishment_ids,
        COUNT(DISTINCT es.id)::INT AS establishment_count
    FROM enterprise_to_group eg
    LEFT JOIN public.legal_unit lu ON lu.enterprise_id = eg.enterprise_id
    LEFT JOIN public.establishment es ON 
        es.enterprise_id = eg.enterprise_id OR es.legal_unit_id = lu.id
    WHERE es.id IS NOT NULL
    GROUP BY eg.group_id
)
SELECT 
    ge.group_id,
    ge.enterprise_ids,
    ge.enterprise_count,
    COALESCE(glu.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids,
    COALESCE(glu.legal_unit_count, 0) AS legal_unit_count,
    COALESCE(ges.establishment_ids, ARRAY[]::INT[]) AS establishment_ids,
    COALESCE(ges.establishment_count, 0) AS establishment_count,
    (ge.enterprise_count + COALESCE(glu.legal_unit_count, 0) + COALESCE(ges.establishment_count, 0))::INT AS total_unit_count
FROM group_enterprises ge
LEFT JOIN group_legal_units glu ON glu.group_id = ge.group_id
LEFT JOIN group_establishments ges ON ges.group_id = ge.group_id
ORDER BY ge.group_id;
$get_enterprise_closed_groups$;

COMMENT ON FUNCTION public.get_enterprise_closed_groups() IS 
'Returns transitively closed groups of enterprises, legal units, and establishments.
Two enterprises are in the same group if they ever shared a legal unit.';


-- ============================================================================
-- FUNCTION 2: Get closed groups batched by target size
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_closed_group_batches(
    p_target_batch_size INT DEFAULT 1000,
    p_establishment_ids INT[] DEFAULT NULL,
    p_legal_unit_ids INT[] DEFAULT NULL,
    p_enterprise_ids INT[] DEFAULT NULL
)
RETURNS TABLE (
    batch_seq INT,
    group_ids INT[],
    enterprise_ids INT[],
    legal_unit_ids INT[],
    establishment_ids INT[],
    total_unit_count INT
)
LANGUAGE plpgsql
STABLE
AS $get_closed_group_batches$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
BEGIN
    v_filter_active := (p_establishment_ids IS NOT NULL 
                       OR p_legal_unit_ids IS NOT NULL 
                       OR p_enterprise_ids IS NOT NULL);
    
    -- Use temp table to accumulate IDs (O(n) instead of O(n²) array concatenation)
    CREATE TEMP TABLE IF NOT EXISTS _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;
    TRUNCATE _batch_accumulator;
    
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
            -- Output current batch by aggregating from temp table
            SELECT 
                v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count
            FROM _batch_accumulator ba;
            RETURN NEXT;
            
            -- Reset for next batch
            v_current_batch_seq := v_current_batch_seq + 1;
            v_current_batch_size := 0;
            TRUNCATE _batch_accumulator;
        END IF;
        
        -- Insert unnested arrays into temp table (O(1) per insert, O(n) total)
        INSERT INTO _batch_accumulator (group_id)
        VALUES (v_group.group_id);
        
        INSERT INTO _batch_accumulator (enterprise_id)
        SELECT UNNEST(v_group.enterprise_ids);
        
        INSERT INTO _batch_accumulator (legal_unit_id)
        SELECT UNNEST(v_group.legal_unit_ids);
        
        INSERT INTO _batch_accumulator (establishment_id)
        SELECT UNNEST(v_group.establishment_ids);
        
        v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
    END LOOP;
    
    IF v_current_batch_size > 0 THEN
        -- Output final batch
        SELECT 
            v_current_batch_seq,
            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
            v_current_batch_size
        INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count
        FROM _batch_accumulator ba;
        RETURN NEXT;
    END IF;
END;
$get_closed_group_batches$;

COMMENT ON FUNCTION public.get_closed_group_batches(INT, INT[], INT[], INT[]) IS
'Returns closed groups combined into batches targeting a specific size.
Groups are processed largest-first to minimize the number of batches.';


-- ============================================================================
-- FUNCTION 3: Enqueue batch task
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_refresh_batch(
    p_batch_seq INT,
    p_enterprise_ids INT[],
    p_legal_unit_ids INT[],
    p_establishment_ids INT[],
    p_valid_from DATE DEFAULT NULL,
    p_valid_until DATE DEFAULT NULL,
    p_is_last_batch BOOLEAN DEFAULT FALSE
) RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_statistical_unit_refresh_batch$
DECLARE
    v_task_id BIGINT;
    v_payload JSONB;
BEGIN
    v_payload := jsonb_build_object(
        'command', 'statistical_unit_refresh_batch',
        'batch_seq', p_batch_seq,
        'enterprise_ids', p_enterprise_ids,
        'legal_unit_ids', p_legal_unit_ids,
        'establishment_ids', p_establishment_ids,
        'valid_from', p_valid_from,
        'valid_until', p_valid_until,
        'is_last_batch', p_is_last_batch
    );

    INSERT INTO worker.tasks (command, payload)
    VALUES ('statistical_unit_refresh_batch', v_payload)
    RETURNING id INTO v_task_id;
    
    RETURN v_task_id;
END;
$enqueue_statistical_unit_refresh_batch$;


-- ============================================================================
-- PROCEDURE 4: Handle a batch - the actual work
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $statistical_unit_refresh_batch$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_valid_from DATE := (payload->>'valid_from')::DATE;
    v_valid_until DATE := (payload->>'valid_until')::DATE;
    v_is_last_batch BOOLEAN := COALESCE((payload->>'is_last_batch')::BOOLEAN, FALSE);
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
BEGIN
    SELECT array_agg(value::INT) INTO v_enterprise_ids
    FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    
    SELECT array_agg(value::INT) INTO v_legal_unit_ids
    FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    
    SELECT array_agg(value::INT) INTO v_establishment_ids
    FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    
    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);
    
    RAISE DEBUG 'Processing batch % with % enterprises, % legal_units, % establishments (is_last=%)',
        v_batch_seq,
        COALESCE(array_length(v_enterprise_ids, 1), 0),
        COALESCE(array_length(v_legal_unit_ids, 1), 0),
        COALESCE(array_length(v_establishment_ids, 1), 0),
        v_is_last_batch;

    -- Call the timeline refresh procedures for this batch
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

    -- Refresh timesegments_years using concurrent-safe approach
    -- Multiple batches can safely call this in parallel
    CALL public.timesegments_years_refresh_concurrent();

    CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );
    
    RAISE DEBUG 'Completed batch %', v_batch_seq;

    -- Only the last batch enqueues derive_reports to ensure all batches complete first
    IF v_is_last_batch THEN
        RAISE DEBUG 'Last batch completed, enqueuing derive_reports';
        PERFORM worker.enqueue_derive_reports(
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        );
    END IF;
END;
$statistical_unit_refresh_batch$;


-- ============================================================================
-- FUNCTION 5: Modified derive_statistical_unit - uses batched groups
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
  p_establishment_id_ranges int4multirange DEFAULT NULL,
  p_legal_unit_id_ranges int4multirange DEFAULT NULL,
  p_enterprise_id_ranges int4multirange DEFAULT NULL,
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_total_batches INT;
    v_is_full_refresh BOOLEAN;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL 
                         AND p_legal_unit_id_ranges IS NULL 
                         AND p_enterprise_id_ranges IS NULL);
    
    IF v_is_full_refresh THEN
        -- Full refresh: get all groups batched
        -- First count total batches to know which is last
        SELECT COUNT(*) INTO v_total_batches
        FROM public.get_closed_group_batches(p_target_batch_size := 1000);
        
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000
            )
        LOOP
            v_batch_count := v_batch_count + 1;
            PERFORM worker.enqueue_statistical_unit_refresh_batch(
                v_batch.batch_seq,
                v_batch.enterprise_ids,
                v_batch.legal_unit_ids,
                v_batch.establishment_ids,
                p_valid_from,
                p_valid_until,
                p_is_last_batch := (v_batch_count = v_total_batches)
            );
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
        
        -- First count total batches to know which is last
        SELECT COUNT(*) INTO v_total_batches
        FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );
        
        -- Get affected groups batched
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            )
        LOOP
            v_batch_count := v_batch_count + 1;
            PERFORM worker.enqueue_statistical_unit_refresh_batch(
                v_batch.batch_seq,
                v_batch.enterprise_ids,
                v_batch.legal_unit_ids,
                v_batch.establishment_ids,
                p_valid_from,
                p_valid_until,
                p_is_last_batch := (v_batch_count = v_total_batches)
            );
        END LOOP;
    END IF;
    
    RAISE DEBUG 'Enqueued % statistical_unit_refresh_batch tasks', v_batch_count;

    -- Refresh derived data (used flags) - always full refreshes
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- NOTE: derive_reports is enqueued by the LAST batch task (via is_last_batch flag)
    -- This ensures reports only run after ALL batches complete successfully
END;
$derive_statistical_unit$;


-- ============================================================================
-- Add concurrency column to queue_registry
-- ============================================================================

-- Add default_concurrency column - how many parallel workers should process this queue
-- 1 = serial (default), >1 = parallel processing
-- Can be overridden by WORKER_QUEUE_CONCURRENCY environment variable
ALTER TABLE worker.queue_registry 
ADD COLUMN IF NOT EXISTS default_concurrency INT NOT NULL DEFAULT 1;

COMMENT ON COLUMN worker.queue_registry.default_concurrency IS 
'Number of parallel workers for this queue. 1=serial (default), >1=parallel. Can be overridden by WORKER_QUEUE_CONCURRENCY env var.';

-- ============================================================================
-- Register the new queue and command
-- ============================================================================

-- Add new queue for parallel batch processing
-- This queue is designed to be processed with multiple concurrent workers
-- Default concurrency of 4 for parallel batch processing
INSERT INTO worker.queue_registry (queue, description, default_concurrency)
VALUES ('analytics_batch', 'Parallel batch processing for analytics derivation', 4)
ON CONFLICT (queue) DO UPDATE SET
    description = EXCLUDED.description,
    default_concurrency = EXCLUDED.default_concurrency;

-- Register the batch command on the parallel queue
INSERT INTO worker.command_registry (queue, command, handler_procedure, description)
VALUES ('analytics_batch', 'statistical_unit_refresh_batch', 
        'worker.statistical_unit_refresh_batch',
        'Refresh statistical_unit for a batch of closed groups (parallel-safe)')
ON CONFLICT (command) DO UPDATE SET
    queue = EXCLUDED.queue,
    handler_procedure = EXCLUDED.handler_procedure,
    description = EXCLUDED.description;

END;
