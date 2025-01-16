```sql
CREATE OR REPLACE FUNCTION public.get_jsonb_stats(p_establishment_id integer, p_legal_unit_id integer, p_valid_after date, p_valid_to date)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    SELECT public.jsonb_concat_agg(
        CASE sd.type
            WHEN 'int' THEN jsonb_build_object(sd.code, sfu.value_int)
            WHEN 'float' THEN jsonb_build_object(sd.code, sfu.value_float)
            WHEN 'string' THEN jsonb_build_object(sd.code, sfu.value_string)
            WHEN 'bool' THEN jsonb_build_object(sd.code, sfu.value_bool)
        END
    )
    FROM public.stat_for_unit AS sfu
    LEFT JOIN public.stat_definition AS sd
        ON sfu.stat_definition_id = sd.id
    WHERE (p_establishment_id IS NULL OR sfu.establishment_id = p_establishment_id)
      AND (p_legal_unit_id IS NULL OR sfu.legal_unit_id = p_legal_unit_id)
      AND daterange(p_valid_after, p_valid_to, '(]')
      && daterange(sfu.valid_after, sfu.valid_to, '(]')
$function$
```
