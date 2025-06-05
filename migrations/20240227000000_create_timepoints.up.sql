BEGIN;

-- Timepoints View: Temporal Analysis Strategy
--
-- This view identifies all significant points in time when statistical units or their
-- relationships change across the business register. It uses the following strategy:
--
-- 1. For each statistical unit type (establishment, legal_unit, enterprise), collect:
--    - The unit's own validity period timepoints
--    - Timepoints from related entities (activities, locations, statistics)
--    - Timepoints from hierarchical relationships between units
--
-- 2. Temporal Integrity Approach:
--    - Uses the after_to_overlaps function to find relationships with any temporal overlap
--    - Applies GREATEST/LEAST to trim dateranges to only the overlapping portions
--    - This ensures we only include timepoints that are valid within the context of both entities
--
-- 3. Examples:
--    a) An establishment exists from 2020-01-01 to 2025-01-01
--       An activity for this establishment exists from 2021-06-01 to 2023-06-01
--       → We include both 2021-06-01 and 2023-06-01 as timepoints for the establishment
--
--       Timeline:
--       2020          2021          2022          2023          2024          2025
--       |             |             |             |             |             |
--       |----- Establishment validity period ------------------------------|
--                     |------ Activity validity period ------|
--                     ↑                                      ↑
--                Timepoint                               Timepoint
--
--    b) A legal unit exists from 2019-01-01 to 2024-01-01
--       An establishment linked to this legal unit exists from 2018-01-01 to 2026-01-01
--       → We trim the relationship to 2019-01-01 to 2024-01-01 (the overlapping period)
--       → Only timepoints within this range are included
--
--       Timeline:
--       2018    2019    2020    2021    2022    2023    2024    2025    2026
--       |       |       |       |       |       |       |       |       |
--               |------ Legal Unit validity period ------|
--       |-------------- Establishment validity period ------------------|
--               |                                        |
--               ↑                                        ↑
--          Trimmed to                               Trimmed to
--          2019-01-01                               2024-01-01
--
-- This approach ensures that all temporal analysis of the business register
-- correctly accounts for the valid time periods of relationships between entities.

CREATE OR REPLACE VIEW public.timepoints AS
WITH es_base AS (
    SELECT 'establishment'::public.statistical_unit_type AS unit_type
         , id AS unit_id
         , valid_after
         , valid_to
    FROM public.establishment
),
es_activity AS (
    SELECT 'establishment'::public.statistical_unit_type AS unit_type
         , a.establishment_id AS unit_id
         , GREATEST(a.valid_after, es.valid_after) AS valid_after
         , LEAST(a.valid_to, es.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.establishment AS es
       ON a.establishment_id = es.id
    WHERE a.establishment_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
),
es_location AS (
    SELECT 'establishment'::public.statistical_unit_type AS unit_type
         , l.establishment_id AS unit_id
         , GREATEST(l.valid_after, es.valid_after) AS valid_after
         , LEAST(l.valid_to, es.valid_to) AS valid_to
    FROM public.location AS l
    JOIN public.establishment AS es
       ON l.establishment_id = es.id
    WHERE l.establishment_id IS NOT NULL
      AND after_to_overlaps(l.valid_after, l.valid_to, es.valid_after, es.valid_to)
),
es_stat AS (
    SELECT 'establishment'::public.statistical_unit_type AS unit_type
         , sfu.establishment_id AS unit_id
         , GREATEST(sfu.valid_after, es.valid_after) AS valid_after
         , LEAST(sfu.valid_to, es.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.establishment AS es
       ON sfu.establishment_id = es.id
    WHERE sfu.establishment_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
),
es_combined AS (
    SELECT * FROM es_base
    UNION ALL
    SELECT * FROM es_activity
    UNION ALL
    SELECT * FROM es_location
    UNION ALL
    SELECT * FROM es_stat
),
lu_base AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , id AS unit_id
         , valid_after
         , valid_to
    FROM public.legal_unit
),
lu_activity AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , a.legal_unit_id AS unit_id
         , GREATEST(a.valid_after, lu.valid_after) AS valid_after
         , LEAST(a.valid_to, lu.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.legal_unit AS lu
       ON a.legal_unit_id = lu.id
    WHERE a.legal_unit_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
),
lu_location AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , l.legal_unit_id AS unit_id
         , GREATEST(l.valid_after, lu.valid_after) AS valid_after
         , LEAST(l.valid_to, lu.valid_to) AS valid_to
    FROM public.location AS l
    JOIN public.legal_unit AS lu
       ON l.legal_unit_id = lu.id
    WHERE l.legal_unit_id IS NOT NULL
      AND after_to_overlaps(l.valid_after, l.valid_to, lu.valid_after, lu.valid_to)
),
lu_stat AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , sfu.legal_unit_id AS unit_id
         , GREATEST(sfu.valid_after, lu.valid_after) AS valid_after
         , LEAST(sfu.valid_to, lu.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.legal_unit AS lu
       ON sfu.legal_unit_id = lu.id
    WHERE sfu.legal_unit_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
),
lu_establishment AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , es.legal_unit_id AS unit_id
         , GREATEST(es.valid_after, lu.valid_after) AS valid_after
         , LEAST(es.valid_to, lu.valid_to) AS valid_to
    FROM public.establishment AS es
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE es.legal_unit_id IS NOT NULL
      AND after_to_overlaps(es.valid_after, es.valid_to, lu.valid_after, lu.valid_to)
),
lu_activity_establishment AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , es.legal_unit_id AS unit_id
         , GREATEST(a.valid_after, es.valid_after, lu.valid_after) AS valid_after
         , LEAST(a.valid_to, es.valid_to, lu.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.establishment AS es
       ON a.establishment_id = es.id
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE es.legal_unit_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
      AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
),
lu_stat_establishment AS (
    SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
         , es.legal_unit_id AS unit_id
         , GREATEST(sfu.valid_after, es.valid_after, lu.valid_after) AS valid_after
         , LEAST(sfu.valid_to, es.valid_to, lu.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.establishment AS es
       ON sfu.establishment_id = es.id
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE es.legal_unit_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
),
lu_combined AS (
    SELECT * FROM lu_base
    UNION ALL
    SELECT * FROM lu_activity
    UNION ALL
    SELECT * FROM lu_location
    UNION ALL
    SELECT * FROM lu_stat
    UNION ALL
    SELECT * FROM lu_establishment
    UNION ALL
    SELECT * FROM lu_activity_establishment
    UNION ALL
    SELECT * FROM lu_stat_establishment
),
en_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , enterprise_id AS unit_id
         , valid_after
         , valid_to
    FROM public.legal_unit
    WHERE enterprise_id IS NOT NULL
),
en_establishment AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , es.enterprise_id AS unit_id
         , es.valid_after
         , es.valid_to
    FROM public.establishment AS es
    WHERE es.enterprise_id IS NOT NULL
),
en_establishment_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(es.valid_after, lu.valid_after) AS valid_after
         , LEAST(es.valid_to, lu.valid_to) AS valid_to
    FROM public.establishment AS es
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND after_to_overlaps(es.valid_after, es.valid_to, lu.valid_after, lu.valid_to)
),
en_activity_establishment AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , es.enterprise_id AS unit_id
         , GREATEST(a.valid_after, es.valid_after) AS valid_after
         , LEAST(a.valid_to, es.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.establishment AS es
       ON a.establishment_id = es.id
    WHERE es.enterprise_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
),
en_activity_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(a.valid_after, lu.valid_after) AS valid_after
         , LEAST(a.valid_to, lu.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.legal_unit AS lu
       ON a.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
),
en_activity_establishment_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(a.valid_after, es.valid_after, lu.valid_after) AS valid_after
         , LEAST(a.valid_to, es.valid_to, lu.valid_to) AS valid_to
    FROM public.activity AS a
    JOIN public.establishment AS es
       ON a.establishment_id = es.id
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
      AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
),
en_location_establishment AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , es.enterprise_id AS unit_id
         , GREATEST(l.valid_after, es.valid_after) AS valid_after
         , LEAST(l.valid_to, es.valid_to) AS valid_to
    FROM public.location AS l
    JOIN public.establishment AS es
       ON l.establishment_id = es.id
    WHERE es.enterprise_id IS NOT NULL
      AND after_to_overlaps(l.valid_after, l.valid_to, es.valid_after, es.valid_to)
),
en_location_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(l.valid_after, lu.valid_after) AS valid_after
         , LEAST(l.valid_to, lu.valid_to) AS valid_to
    FROM public.location AS l
    JOIN public.legal_unit AS lu
       ON l.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND lu.primary_for_enterprise
      AND after_to_overlaps(l.valid_after, l.valid_to, lu.valid_after, lu.valid_to)
),
en_stat_establishment AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , es.enterprise_id AS unit_id
         , GREATEST(sfu.valid_after, es.valid_after) AS valid_after
         , LEAST(sfu.valid_to, es.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.establishment AS es
       ON sfu.establishment_id = es.id
    WHERE es.enterprise_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
),
en_stat_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(sfu.valid_after, lu.valid_after) AS valid_after
         , LEAST(sfu.valid_to, lu.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.legal_unit AS lu
       ON sfu.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
),
en_stat_establishment_legal_unit AS (
    SELECT 'enterprise'::public.statistical_unit_type AS unit_type
         , lu.enterprise_id AS unit_id
         , GREATEST(sfu.valid_after, es.valid_after, lu.valid_after) AS valid_after
         , LEAST(sfu.valid_to, es.valid_to, lu.valid_to) AS valid_to
    FROM public.stat_for_unit AS sfu
    JOIN public.establishment AS es
       ON sfu.establishment_id = es.id
    JOIN public.legal_unit AS lu
       ON es.legal_unit_id = lu.id
    WHERE lu.enterprise_id IS NOT NULL
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
      AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
),
en_combined AS (
    SELECT * FROM en_legal_unit
    UNION ALL
    SELECT * FROM en_establishment
    UNION ALL
    SELECT * FROM en_establishment_legal_unit
    UNION ALL
    SELECT * FROM en_activity_establishment
    UNION ALL
    SELECT * FROM en_activity_legal_unit
    UNION ALL
    SELECT * FROM en_activity_establishment_legal_unit
    UNION ALL
    SELECT * FROM en_location_establishment
    UNION ALL
    SELECT * FROM en_location_legal_unit
    UNION ALL
    SELECT * FROM en_stat_establishment
    UNION ALL
    SELECT * FROM en_stat_legal_unit
    UNION ALL
    SELECT * FROM en_stat_establishment_legal_unit
),
all_combined AS (
    SELECT * FROM es_combined
    UNION ALL
    SELECT * FROM lu_combined
    UNION ALL
    SELECT * FROM en_combined
),
timepoint AS (
    SELECT unit_type, unit_id, valid_after AS timepoint FROM all_combined
    UNION
    SELECT unit_type, unit_id, valid_to AS timepoint FROM all_combined
)
SELECT DISTINCT unit_type, unit_id, timepoint
FROM timepoint
ORDER BY unit_type, unit_id, timepoint;

END;
