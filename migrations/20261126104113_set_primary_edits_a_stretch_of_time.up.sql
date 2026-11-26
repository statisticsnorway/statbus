-- Migration 20261126104113: set primary edits a stretch of time
--
-- 2f4c0z: setting an establishment primary for its legal unit (or a legal unit for its enterprise) is
-- an edit over [valid_from_param, valid_to_param]. Both functions now write the primary flags through
-- the units' __for_portion_of_valid views, which split each unit's rows at the period's edges, so
-- before the period the old primary stays primary and after it nothing changes. Before, a plain UPDATE
-- of every row overlapping the period flipped the flags over each row's whole span.
BEGIN;

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
$function$;

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
$function$;

END;
