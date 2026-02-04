-- Migration 20260203165920: optimize_multirange_to_array_filtering
--
-- PERF: Replace <@ multirange filtering with = ANY(array) for 12x speedup
--
-- Problem: The <@ (contained-by) operator on int4multirange forces full index
-- scans with post-filtering, even with GiST indexes. With 24K rows:
--   WHERE unit_id <@ multirange  → 8ms (scans all, filters 20K)
--   WHERE unit_id = ANY(array)   → 0.6ms (efficient index seeks)
--
-- Solution: Create helper function to expand multirange to array, then use
-- = ANY(array) in all partial refresh DELETE/SELECT statements.
--
-- Affected procedures:
--   - timepoints_refresh (DELETE + INSERT)
--   - timesegments_refresh (DELETE + INSERT)
--   - statistical_unit_refresh (DELETE)

BEGIN;

-- ============================================================================
-- 1. Create helper function to expand multirange to integer array
-- ============================================================================
-- This efficiently handles both:
--   - Sparse ranges like {[10,11),[20,21),[30,31)} → {10,20,30}
--   - Merged ranges like {[1,1001)} → {1,2,3,...,1000}

CREATE OR REPLACE FUNCTION public.int4multirange_to_array(p_ranges int4multirange)
RETURNS INT[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $int4multirange_to_array$
    SELECT array_agg(id ORDER BY id)
    FROM (
        SELECT generate_series(lower(r), upper(r) - 1) AS id
        FROM unnest(p_ranges) AS r
    ) expanded;
$int4multirange_to_array$;

COMMENT ON FUNCTION public.int4multirange_to_array(int4multirange) IS 
'Expands an int4multirange into an integer array for efficient = ANY() filtering.
Uses generate_series to handle both sparse and merged ranges correctly.';

-- ============================================================================
-- 2. Update timepoints_refresh: Replace <@ with = ANY()
-- ============================================================================

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
    -- PERF: Arrays for efficient = ANY() filtering
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
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
        -- Partial refresh with SORTED INSERTS to prevent B-tree page lock deadlocks
        -- ORDER BY ensures all concurrent batches acquire page locks in the same direction
        -- No advisory locks needed - sorted inserts eliminate deadlock cycles
        RAISE DEBUG 'Starting partial timepoints refresh with sorted inserts...';
        
        -- PERF: Convert multiranges to arrays once for efficient = ANY() filtering
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
        
        IF v_es_ids IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_es_ids);
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(p_establishment_id_ranges, NULL, NULL)
            ORDER BY unit_type, unit_id, timepoint  -- CRITICAL: Deterministic order prevents deadlocks
            ON CONFLICT DO NOTHING;
        END IF;
        
        IF v_lu_ids IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_lu_ids);
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(NULL, p_legal_unit_id_ranges, NULL)
            ORDER BY unit_type, unit_id, timepoint  -- CRITICAL: Deterministic order prevents deadlocks
            ON CONFLICT DO NOTHING;
        END IF;
        
        IF v_en_ids IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_en_ids);
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(NULL, NULL, p_enterprise_id_ranges)
            ORDER BY unit_type, unit_id, timepoint  -- CRITICAL: Deterministic order prevents deadlocks
            ON CONFLICT DO NOTHING;
        END IF;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;
END;
$timepoints_refresh$;

-- ============================================================================
-- 3. Update timesegments_refresh: Replace <@ with = ANY()
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.timesegments_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $timesegments_refresh$
DECLARE
    v_is_partial_refresh BOOLEAN;
    -- PERF: Arrays for efficient = ANY() filtering
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
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
        -- Partial refresh with SORTED INSERTS to prevent B-tree page lock deadlocks
        -- ORDER BY ensures all concurrent batches acquire page locks in the same direction
        
        -- PERF: Convert multiranges to arrays once for efficient = ANY() filtering
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
        
        IF v_es_ids IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_es_ids);
            INSERT INTO public.timesegments 
            SELECT * FROM public.timesegments_def 
            WHERE unit_type = 'establishment' AND unit_id = ANY(v_es_ids)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_lu_ids IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_lu_ids);
            INSERT INTO public.timesegments 
            SELECT * FROM public.timesegments_def 
            WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_lu_ids)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_en_ids IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_en_ids);
            INSERT INTO public.timesegments 
            SELECT * FROM public.timesegments_def 
            WHERE unit_type = 'enterprise' AND unit_id = ANY(v_en_ids)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
    END IF;
END;
$timesegments_refresh$;

-- ============================================================================
-- 4. Update statistical_unit_refresh: Replace <@ with = ANY()
-- ============================================================================

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
    -- PERF: Arrays for efficient = ANY() filtering
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
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
        -- Partial refresh with SORTED INSERTS to prevent B-tree page lock deadlocks
        -- ORDER BY ensures all concurrent batches acquire page locks in the same direction
        
        -- PERF: Convert multiranges to arrays once for efficient = ANY() filtering
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
        
        IF v_es_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_es_ids);
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_lu_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_lu_ids);
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_en_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_en_ids);
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
    END IF;
END;
$statistical_unit_refresh$;

END;
