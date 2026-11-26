```sql
CREATE OR REPLACE FUNCTION public.set_primary_legal_unit_for_enterprise(legal_unit_id integer, valid_from_param date DEFAULT CURRENT_DATE, valid_to_param date DEFAULT 'infinity'::date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    legal_unit_row public.legal_unit;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT lu.* INTO legal_unit_row
    FROM public.legal_unit AS lu
    WHERE lu.id = legal_unit_id
      AND from_to_overlaps(lu.valid_from, lu.valid_to, valid_from_param, valid_to_param)
    ORDER BY lu.valid_from
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal unit does not exist.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.legal_unit AS lu
         WHERE lu.id = legal_unit_row.id
           AND from_to_overlaps(lu.valid_from, lu.valid_to, valid_from_param, valid_to_param)
           AND NOT lu.primary_for_enterprise
    ) THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the legal unit is already primary.',
          'enterprise_id', legal_unit_row.enterprise_id,
          'legal_unit_id', legal_unit_row.id
      );
    END IF;

    -- The enterprise's other primary legal units stop being primary over the period only
    -- (legal_unit__for_portion_of_valid splits their rows at its edges).
    SELECT COALESCE(jsonb_agg(jsonb_build_object('table', 'legal_unit', 'id', other.id)), '[]')
      INTO v_unset_ids
      FROM (SELECT DISTINCT lu.id
              FROM public.legal_unit AS lu
             WHERE lu.primary_for_enterprise
               AND lu.enterprise_id = legal_unit_row.enterprise_id
               AND lu.id <> legal_unit_row.id
               AND from_to_overlaps(lu.valid_from, lu.valid_to, valid_from_param, valid_to_param)) AS other;

    UPDATE public.legal_unit__for_portion_of_valid AS v
       SET primary_for_enterprise = false, valid_from = valid_from_param, valid_to = valid_to_param
     WHERE v.id IN (SELECT (u ->> 'id')::integer FROM jsonb_array_elements(v_unset_ids) AS u);

    -- The legal unit is primary over the period.
    UPDATE public.legal_unit__for_portion_of_valid AS v
       SET primary_for_enterprise = true, valid_from = valid_from_param, valid_to = valid_to_param
     WHERE v.id = legal_unit_row.id;
    v_set_id := jsonb_build_object('table', 'legal_unit', 'id', legal_unit_row.id);

    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$function$
```
