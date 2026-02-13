```sql
CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange)
 RETURNS TABLE(unit_type statistical_unit_type, unit_id integer, timepoint date)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$
```
