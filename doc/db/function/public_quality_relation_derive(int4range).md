```sql
CREATE OR REPLACE FUNCTION public.quality_relation_derive(p_hash_slots int4range)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Explicit half-open bounds, so the btree indexes on hash_slot are used (as in
    -- worker.derive_statistical_unit_facet_partition).
    v_from integer := lower(p_hash_slots);
    v_until integer := upper(p_hash_slots);
    v_findings jsonb;
BEGIN
    DELETE FROM public.quality_establishment_activity_differs
     WHERE hash_slot >= v_from AND hash_slot < v_until;
    DELETE FROM public.quality_legal_unit_establishment_stat
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    WITH activity_differs AS (
        INSERT INTO public.quality_establishment_activity_differs
            (check_id, unit_type, unit_id, valid_range, existence_from, existence_until,
             primary_establishment_id, legal_unit_activity_category_id, establishment_activity_category_id)
        SELECT d.check_id, d.unit_type, d.unit_id, d.valid_range, d.existence_from, d.existence_until,
               d.primary_establishment_id, d.legal_unit_activity_category_id, d.establishment_activity_category_id
        FROM public.quality_establishment_activity_differs_def AS d
        WHERE d.hash_slot >= v_from AND d.hash_slot < v_until
        RETURNING check_id
    ), establishment_stat AS (
        INSERT INTO public.quality_legal_unit_establishment_stat
            (check_id, unit_type, unit_id, valid_range, existence_from, existence_until,
             stat_definition_id, legal_unit_value, establishments_sum, establishment_count)
        SELECT s.check_id, s.unit_type, s.unit_id, s.valid_range, s.existence_from, s.existence_until,
               s.stat_definition_id, s.legal_unit_value, s.establishments_sum, s.establishment_count
        FROM public.quality_legal_unit_establishment_stat_def AS s
        WHERE s.hash_slot >= v_from AND s.hash_slot < v_until
        RETURNING check_id
    ), inserted AS (
        SELECT check_id FROM activity_differs
        UNION ALL
        SELECT check_id FROM establishment_stat
    )
    SELECT jsonb_object_agg(k.check_key, k.findings) INTO v_findings
    FROM (
        SELECT CASE WHEN sd.code IS NULL THEN qc.rule::text ELSE qc.rule::text || ':' || sd.code END AS check_key,
               count(*) AS findings
        FROM inserted AS i
        JOIN public.quality_check AS qc ON qc.id = i.check_id
        LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
        GROUP BY 1
    ) AS k;
    RETURN COALESCE(v_findings, '{}'::jsonb);
END;
$function$
```
