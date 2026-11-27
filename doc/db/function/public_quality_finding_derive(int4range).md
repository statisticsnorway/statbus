```sql
CREATE OR REPLACE FUNCTION public.quality_finding_derive(p_hash_slots int4range)
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
    DELETE FROM public.quality_finding
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    WITH inserted AS (
        INSERT INTO public.quality_finding
            (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until,
               public.unit_existence_from(su.valid_from, su.birth_date),
               public.unit_existence_until(su.valid_until, su.death_date),
               d.detail
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id
         AND su.valid_range = daterange(d.valid_from, d.valid_until)
         AND su.hash_slot >= v_from AND su.hash_slot < v_until
        WHERE d.hash_slot >= v_from AND d.hash_slot < v_until
        RETURNING rule, stat_definition_id
    )
    SELECT jsonb_object_agg(k.check_key, k.findings) INTO v_findings
    FROM (
        SELECT CASE WHEN sd.code IS NULL THEN i.rule::text ELSE i.rule::text || ':' || sd.code END AS check_key,
               count(*) AS findings
        FROM inserted AS i
        LEFT JOIN public.stat_definition AS sd ON sd.id = i.stat_definition_id
        GROUP BY 1
    ) AS k;
    RETURN COALESCE(v_findings, '{}'::jsonb);
END;
$function$
```
