BEGIN;

CREATE OR REPLACE FUNCTION public.set_primary_establishment_for_legal_unit(
    establishment_id integer,
    valid_from_param date DEFAULT current_date,
    valid_to_param date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    establishment_row public.establishment;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT * INTO establishment_row
      FROM public.establishment
     WHERE id = establishment_id
       AND daterange(valid_from, valid_to, '[]')
        && daterange(valid_from_param, valid_to_param, '[]');
     IF NOT FOUND THEN
        RAISE EXCEPTION 'Establishment does not exist or is not linked to a legal unit.';
    END IF;

    IF establishment_row.primary_for_legal_unit THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the establishment is already primary.',
          'legal_unit_id', establishment_row.legal_unit_id,
          'establishment_id', establishment_row.id
      );
    END IF;

    -- Unset all establishments of the legal unit from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = false
        WHERE primary_for_legal_unit
          AND legal_unit_id = establishment_row.legal_unit_id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'establishment', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified establishment as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = true
        WHERE id = establishment_row.id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_build_object('table', 'establishment', 'id', id) INTO v_set_id FROM updated_row;

    -- Return a jsonb summary of changes including table and ids of changed establishments
    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$$;

END;
