-- Migration 20260204234245: optimize_timeline_refresh_with_btree_index
BEGIN;

-- ============================================================================
-- Optimize Timeline Refresh to Use Btree Index
-- ============================================================================
--
-- Problem: DELETE/INSERT using `unit_id <@ multirange` cannot use the btree
-- primary key index (unit_type, unit_id, valid_from). Instead PostgreSQL:
-- 1. Scans by unit_type only (partial index use)
-- 2. Filters ALL rows against multirange
--
-- This is ~40x slower than using `= ANY(array)` which fully uses btree.
--
-- EXPLAIN comparison for 100 rows out of 10,000:
--   <@ multirange: 124 buffers, 1.258 ms, Filter: 9900 rows
--   = ANY(array):  3 buffers, 0.071 ms, no filtering
--   >= AND <:      3 buffers, 0.031 ms, no filtering
--
-- Solution: Convert multiranges to arrays using int4multirange_to_array()
-- before DELETE/INSERT operations.
-- ============================================================================

-- ============================================================================
-- 0. Optimize timepoints_calculate to use = ANY(array)
-- ============================================================================
-- This function had severe performance issues:
-- - `<@ int4multirange` patterns cause Seq Scan + Filter
-- - CTEs with wrong cardinality estimates cause Nested Loop (580M rows filtered!)
-- - 149 seconds per batch reduced to ~1-2 seconds with this optimization
-- ============================================================================
CREATE OR REPLACE FUNCTION public.timepoints_calculate(
    p_establishment_id_ranges int4multirange,
    p_legal_unit_id_ranges int4multirange,
    p_enterprise_id_ranges int4multirange
)
RETURNS TABLE(unit_type public.statistical_unit_type, unit_id integer, timepoint date)
LANGUAGE plpgsql
STABLE
AS $timepoints_calculate$
DECLARE
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
BEGIN
    -- Convert multiranges to arrays for btree-friendly queries
    IF p_establishment_id_ranges IS NOT NULL THEN
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
    END IF;
    IF p_legal_unit_id_ranges IS NOT NULL THEN
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
    END IF;
    IF p_enterprise_id_ranges IS NOT NULL THEN
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
    END IF;

    RETURN QUERY
    -- This function calculates all significant timepoints for a given set of statistical units.
    -- It is the core of the "gather and propagate" strategy. Uses = ANY(array) for btree index usage.
    -- Note: CTEs use src_unit_id to avoid ambiguity with return column unit_id in PL/pgSQL.
    WITH es_periods AS (
        -- 1. Gather all raw temporal periods related to the given establishments.
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.establishment WHERE v_es_ids IS NULL OR id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.activity WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.location WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.contact WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.person_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
    ),
    lu_periods_base AS (
        -- 2. Gather periods directly related to the given legal units (NOT from their children yet).
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.legal_unit WHERE v_lu_ids IS NULL OR id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.activity WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.location WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.contact WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.person_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
    ),
    -- This CTE represents all periods relevant to a legal unit, including those propagated up from its child establishments.
    lu_periods_with_children AS (
        SELECT src_unit_id, valid_from, valid_until FROM lu_periods_base
        UNION ALL
        -- Propagate from establishments to legal units, WITH TRIMMING to the lifespan of the link.
        SELECT es.legal_unit_id, GREATEST(p.valid_from, es.valid_from) AS valid_from, LEAST(p.valid_until, es.valid_until) AS valid_until
        FROM es_periods AS p JOIN public.establishment AS es ON p.src_unit_id = es.id
        WHERE (v_lu_ids IS NULL OR es.legal_unit_id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    all_periods (src_unit_type, src_unit_id, valid_from, valid_until) AS (
        -- 3. Combine and trim all periods for all unit types.
        -- Establishment periods are trimmed to their own lifespan slices.
        SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_from, e.valid_from), LEAST(p.valid_until, e.valid_until)
        FROM es_periods p JOIN public.establishment e ON p.src_unit_id = e.id
        WHERE (v_es_ids IS NULL OR e.id = ANY(v_es_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, e.valid_from, e.valid_until)
        UNION ALL
        -- Legal Unit periods are from the comprehensive CTE, trimmed to their own lifespan slices.
        SELECT 'legal_unit', l.id, GREATEST(p.valid_from, l.valid_from), LEAST(p.valid_until, l.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit l ON p.src_unit_id = l.id
        WHERE (v_lu_ids IS NULL OR l.id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, l.valid_from, l.valid_until)
        UNION ALL
        -- Enterprise periods are propagated from Legal Units (and their children), trimmed to the LU-EN link lifespan.
        SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_from, lu.valid_from), LEAST(p.valid_until, lu.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.src_unit_id = lu.id
        WHERE (v_en_ids IS NULL OR lu.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, lu.valid_from, lu.valid_until)
        UNION ALL
        -- Enterprise periods are also propagated from directly-linked Establishments, trimmed to the EST-EN link lifespan.
        SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods p JOIN public.establishment es ON p.src_unit_id = es.id
        WHERE es.enterprise_id IS NOT NULL AND (v_en_ids IS NULL OR es.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    unpivoted AS (
        -- 4. Unpivot valid periods into a single `timepoint` column, ensuring we don't create zero-duration segments.
        SELECT p.src_unit_type, p.src_unit_id, p.valid_from AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
        UNION
        SELECT p.src_unit_type, p.src_unit_id, p.valid_until AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
    )
    -- 5. Deduplicate to get the final, unique set of change dates for each unit.
    SELECT DISTINCT up.src_unit_type, up.src_unit_id, up.timepoint
    FROM unpivoted up
    WHERE up.timepoint IS NOT NULL;
END;
$timepoints_calculate$;

-- ============================================================================
-- 1. Modify timepoints_refresh to use = ANY(array)
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
    -- Arrays for btree-optimized queries
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
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
        -- Partial refresh: Use = ANY(array) for btree index optimization
        RAISE DEBUG 'Starting partial timepoints refresh...';

        -- Convert multiranges to arrays for btree-friendly queries
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
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

-- ============================================================================
-- 2. Modify timesegments_refresh to use = ANY(array)
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
    -- Arrays for btree-optimized queries
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
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
        -- Partial refresh: Use = ANY(array) for btree index optimization
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
    END IF;
END;
$timesegments_refresh$;

-- ============================================================================
-- 3. Modify timeline_refresh to use = ANY(array)
-- ============================================================================
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
    -- Array for btree-optimized queries
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        -- Partial refresh: Use = ANY(array) for btree index optimization
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, p_unit_type, v_unit_ids);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, v_def_view_name, p_unit_type, v_unit_ids);
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

-- ============================================================================
-- 4. Modify timeline_enterprise_refresh to use = ANY(array)
-- ============================================================================
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
    -- Array for btree-optimized queries
    v_unit_ids INT[];
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;
    END IF;

    IF p_unit_id_ranges IS NOT NULL THEN
        -- Partial refresh: Use = ANY(array) for btree index optimization
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, p_unit_type, v_unit_ids);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, v_def_view_name, p_unit_type, v_unit_ids);
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

END;
