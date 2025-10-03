BEGIN;

-- Helper function to convert an array of integers into a multirange.
CREATE OR REPLACE FUNCTION public.array_to_int4multirange(p_array int[])
RETURNS int4multirange LANGUAGE sql IMMUTABLE AS $function$
    SELECT range_agg(int4range(id, id, '[]')) FROM unnest(p_array) as t(id);
$function$;
COMMENT ON FUNCTION public.array_to_int4multirange IS 'Converts an integer array into a multirange of single-integer ranges. Useful for passing sets of IDs to procedures expecting a multirange.';

-- This migration creates the physical `timepoints` TABLE and its refresh procedures.
-- This is the foundation of the "materialize and batch" architecture, a scalable
-- approach for handling temporal data aggregation on large datasets.

-- Timepoints: Temporal Analysis Strategy
--
-- This system identifies every significant date that marks a change in state for any
-- statistical unit. These dates are the endpoints of validity intervals [valid_from, valid_until)
-- from the units themselves and all their related temporal tables.
--
-- Strategy:
--
-- 1. Gather Periods: For each core unit type (establishment, legal_unit), all related
--    temporal records (activities, locations, etc.) are gathered into a single set of
--    validity periods.
--
-- 2. Propagate & Trim Up Hierarchy: The gathered periods are propagated up the statistical
--    unit hierarchy. At each step, the period is trimmed to the valid intersection of
--    the child's period and the parent link's validity period. This is crucial for
--    correctness when links are temporal (e.g., an establishment moving between legal units).
--
-- 3. Unpivot & Deduplicate: The `valid_from` and `valid_until` columns from all these
--    final, trimmed periods are unpivoted into a single `timepoint` column, and a final
--    `DISTINCT` produces the unique set of change dates for each unit.
--
-- This is implemented as a function (`timepoints_calculate`) that can operate on subsets
-- of units, and a procedure (`timepoints_refresh`) that orchestrates the population of
-- the physical `timepoints` table in memory-efficient batches.

CREATE TABLE public.timepoints (
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    timepoint date NOT NULL,
    PRIMARY KEY (unit_type, unit_id, timepoint)
);
CREATE INDEX ix_timepoints_unit ON public.timepoints (unit_type, unit_id);


CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange)
RETURNS TABLE(unit_type public.statistical_unit_type, unit_id int, timepoint date) LANGUAGE sql STABLE AS $function$
-- This function calculates all significant timepoints for a given set of statistical units.
-- It is the core of the "gather and propagate" strategy. It accepts int4multirange for
-- efficient filtering. A NULL range for a given unit type means all units of that type are included.
WITH es_periods AS (
    -- 1. Gather all raw temporal periods related to the given establishments.
    SELECT id AS unit_id, valid_from, valid_until FROM public.establishment WHERE p_establishment_id_ranges IS NULL OR id <@ p_establishment_id_ranges
    UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.activity WHERE p_establishment_id_ranges IS NULL OR establishment_id <@ p_establishment_id_ranges
    UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.location WHERE p_establishment_id_ranges IS NULL OR establishment_id <@ p_establishment_id_ranges
    UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.contact WHERE p_establishment_id_ranges IS NULL OR establishment_id <@ p_establishment_id_ranges
    UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.stat_for_unit WHERE p_establishment_id_ranges IS NULL OR establishment_id <@ p_establishment_id_ranges
    UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.person_for_unit WHERE p_establishment_id_ranges IS NULL OR establishment_id <@ p_establishment_id_ranges
),
lu_periods_base AS (
    -- 2. Gather periods directly related to the given legal units (NOT from their children yet).
    SELECT id AS unit_id, valid_from, valid_until FROM public.legal_unit WHERE p_legal_unit_id_ranges IS NULL OR id <@ p_legal_unit_id_ranges
    UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.activity WHERE p_legal_unit_id_ranges IS NULL OR legal_unit_id <@ p_legal_unit_id_ranges
    UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.location WHERE p_legal_unit_id_ranges IS NULL OR legal_unit_id <@ p_legal_unit_id_ranges
    UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.contact WHERE p_legal_unit_id_ranges IS NULL OR legal_unit_id <@ p_legal_unit_id_ranges
    UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.stat_for_unit WHERE p_legal_unit_id_ranges IS NULL OR legal_unit_id <@ p_legal_unit_id_ranges
    UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.person_for_unit WHERE p_legal_unit_id_ranges IS NULL OR legal_unit_id <@ p_legal_unit_id_ranges
),
-- This CTE represents all periods relevant to a legal unit, including those propagated up from its child establishments.
lu_periods_with_children AS (
    SELECT unit_id, valid_from, valid_until FROM lu_periods_base
    UNION ALL
    -- Propagate from establishments to legal units, WITH TRIMMING to the lifespan of the link.
    SELECT es.legal_unit_id, GREATEST(p.valid_from, es.valid_from) AS valid_from, LEAST(p.valid_until, es.valid_until) AS valid_until
    FROM es_periods AS p JOIN public.establishment AS es ON p.unit_id = es.id
    WHERE (p_legal_unit_id_ranges IS NULL OR es.legal_unit_id <@ p_legal_unit_id_ranges) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
),
all_periods (unit_type, unit_id, valid_from, valid_until) AS (
    -- 3. Combine and trim all periods for all unit types.
    -- Establishment periods are trimmed to their own lifespan slices.
    SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_from, e.valid_from), LEAST(p.valid_until, e.valid_until)
    FROM es_periods p JOIN public.establishment e ON p.unit_id = e.id
    WHERE (p_establishment_id_ranges IS NULL OR e.id <@ p_establishment_id_ranges) AND from_until_overlaps(p.valid_from, p.valid_until, e.valid_from, e.valid_until)
    UNION ALL
    -- Legal Unit periods are from the comprehensive CTE, trimmed to their own lifespan slices.
    SELECT 'legal_unit', l.id, GREATEST(p.valid_from, l.valid_from), LEAST(p.valid_until, l.valid_until)
    FROM lu_periods_with_children p JOIN public.legal_unit l ON p.unit_id = l.id
    WHERE (p_legal_unit_id_ranges IS NULL OR l.id <@ p_legal_unit_id_ranges) AND from_until_overlaps(p.valid_from, p.valid_until, l.valid_from, l.valid_until)
    UNION ALL
    -- Enterprise periods are propagated from Legal Units (and their children), trimmed to the LU-EN link lifespan.
    SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_from, lu.valid_from), LEAST(p.valid_until, lu.valid_until)
    FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.unit_id = lu.id
    WHERE (p_enterprise_id_ranges IS NULL OR lu.enterprise_id <@ p_enterprise_id_ranges) AND from_until_overlaps(p.valid_from, p.valid_until, lu.valid_from, lu.valid_until)
    UNION ALL
    -- Enterprise periods are also propagated from directly-linked Establishments, trimmed to the EST-EN link lifespan.
    SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
    FROM es_periods p JOIN public.establishment es ON p.unit_id = es.id
    WHERE es.enterprise_id IS NOT NULL AND (p_enterprise_id_ranges IS NULL OR es.enterprise_id <@ p_enterprise_id_ranges) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
),
unpivoted AS (
    -- 4. Unpivot valid periods into a single `timepoint` column, ensuring we don't create zero-duration segments.
    SELECT p.unit_type, p.unit_id, p.valid_from AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
    UNION
    SELECT p.unit_type, p.unit_id, p.valid_until AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
)
-- 5. Deduplicate to get the final, unique set of change dates for each unit.
SELECT DISTINCT up.unit_type, up.unit_id, up.timepoint
FROM unpivoted up
WHERE up.timepoint IS NOT NULL;
$function$;

CREATE OR REPLACE PROCEDURE public.timepoints_refresh(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql AS $procedure$
DECLARE
    rec RECORD;
    v_en_batch INT[];
    v_lu_batch INT[];
    v_es_batch INT[];
    v_batch_size INT := 32768; -- Number of enterprises to process per batch
    v_total_enterprises INT;
    v_processed_count INT := 0;
    v_batch_num INT := 0;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
BEGIN
    ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh: Use a staging table for performance and to minimize lock duration.
        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;

        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;

        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);

            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                -- For this batch of enterprises, find all descendant LUs and ESTs
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
                RAISE DEBUG 'Timepoints batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

                v_en_batch := '{}'; -- Reset for next batch
            END IF;
        END LOOP;

        -- Process the final, smaller batch
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
            RAISE DEBUG 'Timepoints final batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        -- Atomically swap the data
        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';
    ELSE
        -- Partial refresh
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

    ANALYZE public.timepoints;
END;
$procedure$;

-- Initial population of the new table after its creation.
CALL public.timepoints_refresh();

END;
