BEGIN;

-- This migration creates the physical `timepoints` TABLE and its refresh procedures.
-- This is the foundation of the "materialize and batch" architecture, a scalable
-- approach for handling temporal data aggregation on large datasets.

-- Timepoints: Temporal Analysis Strategy
--
-- This system identifies every significant date that marks a change in state for any
-- statistical unit. These dates are the endpoints of validity intervals (valid_after, valid_to)
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
-- 3. Unpivot & Deduplicate: The `valid_after` and `valid_to` columns from all these
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


CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_ids int[], p_legal_unit_ids int[], p_enterprise_ids int[])
RETURNS TABLE(unit_type public.statistical_unit_type, unit_id int, timepoint date) LANGUAGE sql STABLE AS $function$
-- This function calculates all significant timepoints for a given set of statistical units.
-- It is the core of the "gather and propagate" strategy.
WITH es_periods AS (
    -- 1. Gather all raw temporal periods related to the given establishments.
    SELECT id AS unit_id, valid_after, valid_to FROM public.establishment WHERE id = ANY(p_establishment_ids)
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.activity WHERE establishment_id = ANY(p_establishment_ids)
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.location WHERE establishment_id = ANY(p_establishment_ids)
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.contact WHERE establishment_id = ANY(p_establishment_ids)
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.stat_for_unit WHERE establishment_id = ANY(p_establishment_ids)
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.person_for_unit WHERE establishment_id = ANY(p_establishment_ids)
),
lu_periods_base AS (
    -- 2. Gather periods directly related to the given legal units (NOT from their children yet).
    SELECT id AS unit_id, valid_after, valid_to FROM public.legal_unit WHERE id = ANY(p_legal_unit_ids)
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.activity WHERE legal_unit_id = ANY(p_legal_unit_ids)
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.location WHERE legal_unit_id = ANY(p_legal_unit_ids)
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.contact WHERE legal_unit_id = ANY(p_legal_unit_ids)
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.stat_for_unit WHERE legal_unit_id = ANY(p_legal_unit_ids)
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.person_for_unit WHERE legal_unit_id = ANY(p_legal_unit_ids)
),
-- This CTE represents all periods relevant to a legal unit, including those propagated up from its child establishments.
lu_periods_with_children AS (
    SELECT unit_id, valid_after, valid_to FROM lu_periods_base
    UNION ALL
    -- Propagate from establishments to legal units, WITH TRIMMING to the lifespan of the link.
    SELECT es.legal_unit_id, GREATEST(p.valid_after, es.valid_after) AS valid_after, LEAST(p.valid_to, es.valid_to) AS valid_to
    FROM es_periods AS p JOIN public.establishment AS es ON p.unit_id = es.id
    WHERE es.legal_unit_id = ANY(p_legal_unit_ids) AND after_to_overlaps(p.valid_after, p.valid_to, es.valid_after, es.valid_to)
),
all_periods (unit_type, unit_id, valid_after, valid_to) AS (
    -- 3. Combine and trim all periods for all unit types.
    -- Establishment periods are trimmed to their own lifespan slices.
    SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_after, e.valid_after), LEAST(p.valid_to, e.valid_to)
    FROM es_periods p JOIN public.establishment e ON p.unit_id = e.id
    WHERE e.id = ANY(p_establishment_ids) AND after_to_overlaps(p.valid_after, p.valid_to, e.valid_after, e.valid_to)
    UNION ALL
    -- Legal Unit periods are from the comprehensive CTE, trimmed to their own lifespan slices.
    SELECT 'legal_unit', l.id, GREATEST(p.valid_after, l.valid_after), LEAST(p.valid_to, l.valid_to)
    FROM lu_periods_with_children p JOIN public.legal_unit l ON p.unit_id = l.id
    WHERE l.id = ANY(p_legal_unit_ids) AND after_to_overlaps(p.valid_after, p.valid_to, l.valid_after, l.valid_to)
    UNION ALL
    -- Enterprise periods are propagated from Legal Units (and their children), trimmed to the LU-EN link lifespan.
    SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_after, lu.valid_after), LEAST(p.valid_to, lu.valid_to)
    FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.unit_id = lu.id
    WHERE lu.enterprise_id = ANY(p_enterprise_ids) AND after_to_overlaps(p.valid_after, p.valid_to, lu.valid_after, lu.valid_to)
    UNION ALL
    -- Enterprise periods are also propagated from directly-linked Establishments, trimmed to the EST-EN link lifespan.
    SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_after, es.valid_after), LEAST(p.valid_to, es.valid_to)
    FROM es_periods p JOIN public.establishment es ON p.unit_id = es.id
    WHERE es.enterprise_id = ANY(p_enterprise_ids) AND after_to_overlaps(p.valid_after, p.valid_to, es.valid_after, es.valid_to)
),
unpivoted AS (
    -- 4. Unpivot valid periods into a single `timepoint` column, ensuring we don't create zero-duration segments.
    SELECT p.unit_type, p.unit_id, p.valid_after AS timepoint FROM all_periods p WHERE p.valid_after < p.valid_to
    UNION
    SELECT p.unit_type, p.unit_id, p.valid_to AS timepoint FROM all_periods p WHERE p.valid_after < p.valid_to
)
-- 5. Deduplicate to get the final, unique set of change dates for each unit.
SELECT DISTINCT up.unit_type, up.unit_id, up.timepoint
FROM unpivoted up
WHERE up.timepoint IS NOT NULL;
$function$;

CREATE OR REPLACE PROCEDURE public.timepoints_refresh(p_unit_ids int[] DEFAULT NULL, p_unit_type public.statistical_unit_type DEFAULT NULL)
LANGUAGE plpgsql AS $procedure$
-- This procedure populates the physical `public.timepoints` table.
-- It processes units in batches to keep memory usage low, making it suitable for very large datasets.
--
-- The process is ordered from the bottom of the hierarchy upwards (Establishment -> Legal Unit -> Enterprise)
-- because the calculation for a parent unit depends on having the data for its children.
--
-- Parameters:
--   p_unit_ids: (Not yet implemented) An array of specific unit IDs to refresh.
--   p_unit_type: If specified, only units of this type will be refreshed. If NULL, all types are refreshed.
DECLARE
    v_batch_size int := 50000;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_ids int[]; v_all_lu_ids int[]; v_all_en_ids int[];
    v_target_type public.statistical_unit_type;
    v_table_name text;
BEGIN
    -- For a full refresh (both parameters NULL), start by clearing the table.
    IF p_unit_ids IS NULL AND p_unit_type IS NULL THEN
        TRUNCATE public.timepoints;
    END IF;

    -- Refresh Establishments
    -- This is the base of the hierarchy. The calculation is self-contained.
    v_target_type := 'establishment';
    v_table_name := 'establishment';
    IF p_unit_type IS NULL OR p_unit_type = v_target_type THEN
        EXECUTE format('SELECT MIN(id), MAX(id) FROM public.%I', v_table_name) INTO v_min_id, v_max_id;
        IF v_min_id IS NOT NULL THEN
            FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
                v_start_id := i; v_end_id := i + v_batch_size - 1;
                EXECUTE format('SELECT array_agg(id) FROM public.%I WHERE id BETWEEN %L AND %L', v_table_name, v_start_id, v_end_id) INTO v_batch_ids;
                IF v_batch_ids IS NULL OR cardinality(v_batch_ids) = 0 THEN CONTINUE; END IF;
                -- Delete existing timepoints for this batch before re-inserting.
                DELETE FROM public.timepoints WHERE unit_type = v_target_type AND unit_id = ANY(v_batch_ids);
                -- Calculate and insert the new timepoints for this batch.
                -- Note: We filter the results of `timepoints_calculate` to ensure we only insert
                -- the type we are currently processing.
                INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(v_batch_ids, '{}', '{}') WHERE unit_type = v_target_type;
            END LOOP;
        END IF;
    END IF;

    -- Refresh Legal Units
    -- This depends on establishment data, so we must gather all child establishment IDs for the current batch of legal units.
    v_target_type := 'legal_unit';
    v_table_name := 'legal_unit';
    IF p_unit_type IS NULL OR p_unit_type = v_target_type THEN
        EXECUTE format('SELECT MIN(id), MAX(id) FROM public.%I', v_table_name) INTO v_min_id, v_max_id;
        IF v_min_id IS NOT NULL THEN
            FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
                v_start_id := i; v_end_id := i + v_batch_size - 1;
                EXECUTE format('SELECT array_agg(id) FROM public.%I WHERE id BETWEEN %L AND %L', v_table_name, v_start_id, v_end_id) INTO v_batch_ids;
                IF v_batch_ids IS NULL OR cardinality(v_batch_ids) = 0 THEN CONTINUE; END IF;
                -- Find all child establishments for this batch of legal units.
                SELECT array_agg(DISTINCT id) INTO v_all_en_ids FROM public.establishment WHERE legal_unit_id = ANY(v_batch_ids);
                DELETE FROM public.timepoints WHERE unit_type = v_target_type AND unit_id = ANY(v_batch_ids);
                -- Calculate timepoints, passing both the legal units and their children.
                INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(COALESCE(v_all_en_ids, '{}'), v_batch_ids, '{}') WHERE unit_type = v_target_type;
            END LOOP;
        END IF;
    END IF;

    -- Refresh Enterprises
    -- This is the top of the hierarchy. It depends on both legal units and directly-linked establishments.
    v_target_type := 'enterprise';
    v_table_name := 'enterprise';
    IF p_unit_type IS NULL OR p_unit_type = v_target_type THEN
        EXECUTE format('SELECT MIN(id), MAX(id) FROM public.%I', v_table_name) INTO v_min_id, v_max_id;
        IF v_min_id IS NOT NULL THEN
            FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
                v_start_id := i; v_end_id := i + v_batch_size - 1;
                EXECUTE format('SELECT array_agg(id) FROM public.%I WHERE id BETWEEN %L AND %L', v_table_name, v_start_id, v_end_id) INTO v_batch_ids;
                IF v_batch_ids IS NULL OR cardinality(v_batch_ids) = 0 THEN CONTINUE; END IF;
                -- Find all child legal units and establishments for this batch of enterprises.
                SELECT array_agg(DISTINCT id) INTO v_all_lu_ids FROM public.legal_unit WHERE enterprise_id = ANY(v_batch_ids);
                SELECT array_agg(DISTINCT id) INTO v_all_en_ids FROM public.establishment WHERE enterprise_id = ANY(v_batch_ids);
                -- Also include "grandchildren" establishments (via the legal units).
                IF v_all_lu_ids IS NOT NULL THEN
                    v_all_en_ids := array_cat(COALESCE(v_all_en_ids, '{}'), (SELECT array_agg(DISTINCT id) FROM public.establishment WHERE legal_unit_id = ANY(v_all_lu_ids)));
                END IF;
                DELETE FROM public.timepoints WHERE unit_type = v_target_type AND unit_id = ANY(v_batch_ids);
                -- Calculate timepoints, passing enterprises and all their descendants.
                INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(COALESCE(v_all_en_ids, '{}'), COALESCE(v_all_lu_ids, '{}'), v_batch_ids) WHERE unit_type = v_target_type;
            END LOOP;
        END IF;
    END IF;
END;
$procedure$;

-- Initial population of the new table after its creation.
CALL public.timepoints_refresh();

END;
