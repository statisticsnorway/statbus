BEGIN;

-- Timepoints View: Temporal Analysis Strategy
--
-- This view identifies every significant date that marks a change in state for any
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
-- This staged "gather and propagate" approach is highly performant and resilient,
-- avoiding the complex hierarchical joins of the previous implementation which were prone
-- to catastrophic performance degradation and memory exhaustion at scale.

CREATE OR REPLACE VIEW public.timepoints AS
WITH es_periods AS (
    -- Gather all raw temporal periods related to establishments
    SELECT id AS unit_id, valid_after, valid_to FROM public.establishment
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.activity WHERE establishment_id IS NOT NULL
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.location WHERE establishment_id IS NOT NULL
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.contact WHERE establishment_id IS NOT NULL
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.stat_for_unit WHERE establishment_id IS NOT NULL
    UNION ALL SELECT establishment_id, valid_after, valid_to FROM public.person_for_unit WHERE establishment_id IS NOT NULL
),
lu_periods_base AS (
    -- Gather periods directly related to legal units (NOT from their children yet)
    SELECT id AS unit_id, valid_after, valid_to FROM public.legal_unit
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.activity WHERE legal_unit_id IS NOT NULL
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.location WHERE legal_unit_id IS NOT NULL
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.contact WHERE legal_unit_id IS NOT NULL
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.stat_for_unit WHERE legal_unit_id IS NOT NULL
    UNION ALL SELECT legal_unit_id, valid_after, valid_to FROM public.person_for_unit WHERE legal_unit_id IS NOT NULL
),
-- This CTE represents all periods relevant to a legal unit, including those propagated from its child establishments.
lu_periods_with_children AS (
    SELECT unit_id, valid_after, valid_to FROM lu_periods_base
    UNION ALL
    -- Propagate from establishments to legal units, WITH TRIMMING
    SELECT
        es.legal_unit_id,
        GREATEST(p.valid_after, es.valid_after) as valid_after,
        LEAST(p.valid_to, es.valid_to) as valid_to
    FROM es_periods AS p
    JOIN public.establishment AS es ON p.unit_id = es.id
    WHERE es.legal_unit_id IS NOT NULL
      AND after_to_overlaps(p.valid_after, p.valid_to, es.valid_after, es.valid_to)
),
all_periods AS (
    -- 1. Establishment periods are themselves, trimmed to their own lifespan slices.
    SELECT 'establishment'::public.statistical_unit_type AS unit_type, es.id AS unit_id,
           GREATEST(p.valid_after, es.valid_after) AS valid_after,
           LEAST(p.valid_to, es.valid_to) AS valid_to
    FROM es_periods AS p
    JOIN public.establishment AS es ON p.unit_id = es.id AND after_to_overlaps(p.valid_after, p.valid_to, es.valid_after, es.valid_to)
    UNION ALL
    -- 2. Legal Unit periods are from the comprehensive CTE, trimmed to their own lifespan slices.
    SELECT 'legal_unit', lu.id,
           GREATEST(p.valid_after, lu.valid_after) AS valid_after,
           LEAST(p.valid_to, lu.valid_to) AS valid_to
    FROM lu_periods_with_children AS p
    JOIN public.legal_unit AS lu ON p.unit_id = lu.id AND after_to_overlaps(p.valid_after, p.valid_to, lu.valid_after, lu.valid_to)
    UNION ALL
    -- 3. Enterprise periods are propagated from Legal Units (and their children via lu_periods_with_children), trimmed to the LU-EN link lifespan.
    SELECT 'enterprise', lu.enterprise_id,
           GREATEST(p.valid_after, lu.valid_after) AS valid_after,
           LEAST(p.valid_to, lu.valid_to) AS valid_to
    FROM lu_periods_with_children AS p
    JOIN public.legal_unit AS lu ON p.unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(p.valid_after, p.valid_to, lu.valid_after, lu.valid_to)
    UNION ALL
    -- 4. Enterprise periods are also propagated from directly-linked Establishments, trimmed to the EST-EN link lifespan.
    SELECT 'enterprise', es.enterprise_id,
           GREATEST(p.valid_after, es.valid_after) AS valid_after,
           LEAST(p.valid_to, es.valid_to) AS valid_to
    FROM es_periods AS p
    JOIN public.establishment AS es ON p.unit_id = es.id
    WHERE es.enterprise_id IS NOT NULL AND after_to_overlaps(p.valid_after, p.valid_to, es.valid_after, es.valid_to)
),
unpivoted AS (
    -- Unpivot valid periods, ensuring we don't create zero-duration segments
    SELECT unit_type, unit_id, valid_after AS timepoint FROM all_periods WHERE valid_after < valid_to
    UNION
    SELECT unit_type, unit_id, valid_to AS timepoint FROM all_periods WHERE valid_after < valid_to
)
SELECT DISTINCT unit_type, unit_id, timepoint
FROM unpivoted
WHERE timepoint IS NOT NULL
ORDER BY unit_type, unit_id, timepoint;


END;
