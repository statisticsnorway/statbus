```sql
CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange)
 RETURNS TABLE(unit_type statistical_unit_type, unit_id integer, timepoint date)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
