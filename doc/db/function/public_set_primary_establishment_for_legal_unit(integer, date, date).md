```sql
CREATE OR REPLACE FUNCTION public.set_primary_establishment_for_legal_unit(establishment_id integer, valid_from_param date DEFAULT CURRENT_DATE, valid_to_param date DEFAULT 'infinity'::date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    establishment_row public.establishment;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT * INTO establishment_row
      FROM public.establishment
     WHERE id = establishment_id
       AND from_to_overlaps(valid_from, valid_to, valid_from_param, valid_to_param)
     ORDER BY valid_from
     LIMIT 1;
     IF NOT FOUND OR establishment_row.legal_unit_id IS NULL THEN
        RAISE EXCEPTION 'Establishment does not exist or is not linked to a legal unit.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.establishment AS es
         WHERE es.id = establishment_row.id
           AND from_to_overlaps(es.valid_from, es.valid_to, valid_from_param, valid_to_param)
           AND NOT es.primary_for_legal_unit
    ) THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the establishment is already primary.',
          'legal_unit_id', establishment_row.legal_unit_id,
          'establishment_id', establishment_row.id
      );
    END IF;

    -- The legal unit's other primary establishments stop being primary over the period only
    -- (establishment__for_portion_of_valid splits their rows at its edges).
    SELECT COALESCE(jsonb_agg(jsonb_build_object('table', 'establishment', 'id', other.id)), '[]')
      INTO v_unset_ids
      FROM (SELECT DISTINCT es.id
              FROM public.establishment AS es
             WHERE es.primary_for_legal_unit
               AND es.legal_unit_id = establishment_row.legal_unit_id
               AND es.id <> establishment_row.id
               AND from_to_overlaps(es.valid_from, es.valid_to, valid_from_param, valid_to_param)) AS other;

    UPDATE public.establishment__for_portion_of_valid AS v
       SET primary_for_legal_unit = false, valid_from = valid_from_param, valid_to = valid_to_param
     WHERE v.id IN (SELECT (u ->> 'id')::integer FROM jsonb_array_elements(v_unset_ids) AS u);

    -- The establishment is primary over the period.
    UPDATE public.establishment__for_portion_of_valid AS v
       SET primary_for_legal_unit = true, valid_from = valid_from_param, valid_to = valid_to_param
     WHERE v.id = establishment_row.id;
    v_set_id := jsonb_build_object('table', 'establishment', 'id', establishment_row.id);

    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$function$
```
