BEGIN;

-- ============================================================================
-- Chunked Fan-out with ANALYZE Sync Points
-- ============================================================================
-- 
-- Problem: When multiple batch tasks run ANALYZE concurrently, they acquire
-- ShareUpdateExclusiveLock which conflicts with itself, serializing execution.
--
-- Solution: Chunked fan-out pattern:
-- 1. derive_statistical_unit spawns M batches (configurable)
-- 2. derive_statistical_unit spawns uncle (self) with offset for next wave
-- 3. Batches complete → parent completes → uncle runs
-- 4. Uncle runs ANALYZE (sync point), then spawns next M batches
-- 5. Repeat until all batches processed
-- 6. Final wave enqueues derive_reports
--
-- This gives us: parallel batch execution + ANALYZE sync points between waves

-- ============================================================================
-- 0. Register derive_statistical_unit_continue command
-- ============================================================================
-- This command handles continuation of wave processing. It is NOT deduplicated
-- because each continuation represents a specific wave offset that must run.
-- The original derive_statistical_unit keeps its pending-only deduplication.

INSERT INTO worker.command_registry (command, handler_procedure, queue, description)
VALUES (
    'derive_statistical_unit_continue',
    'worker.derive_statistical_unit_continue',
    'analytics',
    'Continue derive_statistical_unit processing from a specific batch offset (ANALYZE sync point)'
)
ON CONFLICT (command) DO NOTHING;

-- ============================================================================
-- 1. Add batches_per_wave setting to command_registry
-- ============================================================================
ALTER TABLE worker.command_registry 
ADD COLUMN IF NOT EXISTS batches_per_wave INT DEFAULT NULL;

COMMENT ON COLUMN worker.command_registry.batches_per_wave IS 
'Number of child batch tasks to spawn per wave before an ANALYZE sync point. NULL means spawn all at once.';

-- Set default for derive_statistical_unit (can be tuned based on observation)
UPDATE worker.command_registry 
SET batches_per_wave = 10 
WHERE command = 'derive_statistical_unit';

-- ============================================================================
-- 2. Modify get_closed_group_batches to support offset/limit
-- ============================================================================
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

-- ============================================================================
-- 3. Create helper to run ANALYZE on derived tables only
-- ============================================================================
CREATE OR REPLACE PROCEDURE public.analyze_derived_tables()
LANGUAGE plpgsql
AS $analyze_derived_tables$
BEGIN
    RAISE DEBUG 'Running ANALYZE on derived tables...';
    ANALYZE public.timepoints;
    ANALYZE public.timesegments;
    ANALYZE public.timesegments_years;
    ANALYZE public.timeline_establishment;
    ANALYZE public.timeline_legal_unit;
    ANALYZE public.timeline_enterprise;
    ANALYZE public.statistical_unit;
    RAISE DEBUG 'ANALYZE on derived tables complete.';
END;
$analyze_derived_tables$;

-- ============================================================================
-- 4. Skip ANALYZE in batch refresh procedures (partial refresh only)
-- ============================================================================

-- timepoints_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timepoints_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timepoints_refresh$
DECLARE
    rec RECORD;
    v_en_batch INT[];
    v_lu_batch INT[];
    v_es_batch INT[];
    v_batch_size INT := 32768;
    v_total_enterprises INT;
    v_processed_count INT := 0;
    v_batch_num INT := 0;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;

        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;

        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);

            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                v_processed_count := v_processed_count + array_length(v_en_batch, 1);
                v_batch_num := v_batch_num + 1;

                v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
                v_es_batch := ARRAY(
                    SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                    UNION
                    SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
                );

                INSERT INTO timepoints_new
                SELECT * FROM public.timepoints_calculate(
                    public.array_to_int4multirange(v_es_batch),
                    public.array_to_int4multirange(v_lu_batch),
                    public.array_to_int4multirange(v_en_batch)
                ) ON CONFLICT DO NOTHING;

                v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
                v_batch_speed := v_batch_size / (v_batch_duration_ms / 1000.0);
                RAISE DEBUG 'Timepoints batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

                v_en_batch := '{}';
            END IF;
        END LOOP;

        IF array_length(v_en_batch, 1) > 0 THEN
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
            v_es_batch := ARRAY(
                SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                UNION
                SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
            );
            INSERT INTO timepoints_new
            SELECT * FROM public.timepoints_calculate(
                public.array_to_int4multirange(v_es_batch),
                public.array_to_int4multirange(v_lu_batch),
                public.array_to_int4multirange(v_en_batch)
            ) ON CONFLICT DO NOTHING;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_batch_speed := array_length(v_en_batch, 1) / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Timepoints final batch done. (% units, % ms, % units/s)', array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';

        ANALYZE public.timepoints;
    ELSE
        -- Partial refresh: NO ANALYZE (sync points handle it)
        RAISE DEBUG 'Starting partial timepoints refresh...';
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;

        INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(
            p_establishment_id_ranges,
            p_legal_unit_id_ranges,
            p_enterprise_id_ranges
        ) ON CONFLICT DO NOTHING;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;
END;
$timepoints_refresh$;

-- timesegments_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timesegments_refresh$
DECLARE
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
    ELSE
        -- Partial refresh: NO ANALYZE (sync points handle it)
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;
END;
$timesegments_refresh$;

-- timeline_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timeline_refresh(
    IN p_target_table text,
    IN p_unit_type public.statistical_unit_type,
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timeline_refresh$
DECLARE
    v_batch_size INT := 65536;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        -- Partial refresh: NO ANALYZE (sync points handle it)
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        -- Full refresh with ANALYZE
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing % for % units in batches of %...', p_target_table, v_total_units, v_batch_size;
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
            RAISE DEBUG '% batch %/% done. (% units, % ms, % units/s)', p_target_table, v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    END IF;
END;
$timeline_refresh$;

-- timeline_establishment_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timeline_establishment_refresh$
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    END IF;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$timeline_establishment_refresh$;

-- timeline_legal_unit_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timeline_legal_unit_refresh$
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
    END IF;
    CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
END;
$timeline_legal_unit_refresh$;

-- timeline_enterprise_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timeline_enterprise_refresh$
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
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;
    END IF;

    IF p_unit_id_ranges IS NOT NULL THEN
        -- Partial refresh: NO ANALYZE
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        -- Full refresh
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
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
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    END IF;
END;
$timeline_enterprise_refresh$;

-- statistical_unit_refresh: Skip ANALYZE for partial refresh
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $statistical_unit_refresh$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        INSERT INTO public.statistical_unit SELECT * FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: NO ANALYZE (sync points handle it)
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;
END;
$statistical_unit_refresh$;

-- ============================================================================
-- 5. Modify derive_statistical_unit for chunked fan-out with continuation command
-- ============================================================================
-- 
-- Pattern:
--   derive_statistical_unit (offset=0, deduplicated on pending)
--     ├── statistical_unit_refresh_batch (1)
--     ├── statistical_unit_refresh_batch (2)
--     ├── ...batch N...
--     └── derive_statistical_unit_continue (offset=N, NOT deduplicated)
--           ├── statistical_unit_refresh_batch (N+1)
--           ├── ...
--           └── derive_statistical_unit_continue (offset=2N)
--                 ├── ...final wave...
--                 └── derive_reports (uncle)

-- Drop the 6-param function first to avoid accumulation
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);

-- Core function that handles both initial and continuation processing
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit_impl(
    p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_task_id bigint DEFAULT NULL::bigint,
    p_batch_offset int DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit_impl$
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
$derive_statistical_unit_impl$;

-- Wrapper function for derive_statistical_unit (initial task, offset=0)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_task_id bigint DEFAULT NULL::bigint
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
BEGIN
    -- Initial task always starts at offset 0
    PERFORM worker.derive_statistical_unit_impl(
        p_establishment_id_ranges := p_establishment_id_ranges,
        p_legal_unit_id_ranges := p_legal_unit_id_ranges,
        p_enterprise_id_ranges := p_enterprise_id_ranges,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_task_id := p_task_id,
        p_batch_offset := 0
    );
END;
$derive_statistical_unit$;

-- Procedure wrapper for derive_statistical_unit (called by worker)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_task_id BIGINT;
BEGIN
    -- Get current task ID from the tasks table (the one being processed)
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;
    
    -- Call the function with task_id for spawning children (offset=0 for initial task)
    PERFORM worker.derive_statistical_unit(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id
    );
END;
$procedure$;

-- Procedure for derive_statistical_unit_continue (called by worker for continuation tasks)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_continue(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_continue$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_batch_offset int = COALESCE((payload->>'batch_offset')::int, 0);
    v_task_id BIGINT;
BEGIN
    -- Get current task ID from the tasks table (the one being processed)
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;
    
    -- Call the impl function with the batch_offset from payload
    PERFORM worker.derive_statistical_unit_impl(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_batch_offset := v_batch_offset
    );
END;
$derive_statistical_unit_continue$;

END;
