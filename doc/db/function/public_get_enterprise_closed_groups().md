```sql
CREATE OR REPLACE FUNCTION public.get_enterprise_closed_groups()
 RETURNS TABLE(group_id integer, enterprise_ids integer[], enterprise_count integer, legal_unit_ids integer[], legal_unit_count integer, establishment_ids integer[], establishment_count integer, total_unit_count integer)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
