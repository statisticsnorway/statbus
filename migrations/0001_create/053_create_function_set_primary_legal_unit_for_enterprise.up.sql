BEGIN;

\echo public.set_primary_legal_unit_for_enterprise
-- Functions to manage connections between enterprise <-> legal_unit <-> establishment
CREATE OR REPLACE FUNCTION public.set_primary_legal_unit_for_enterprise(
    legal_unit_id integer,
    valid_from_param date DEFAULT current_date,
    valid_to_param date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    legal_unit_row public.legal_unit;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT lu.* INTO legal_unit_row
    FROM public.legal_unit AS lu
    WHERE lu.id = legal_unit_id
      AND daterange(lu.valid_from, lu.valid_to, '[]')
       && daterange(valid_from_param, valid_to_param, '[]');
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal unit does not exist.';
    END IF;

    IF legal_unit_row.primary_for_enterprise THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the legal unit is already primary.',
          'enterprise_id', legal_unit_row.enterprise_id,
          'legal_unit_id', legal_unit_row.id
      );
    END IF;

    -- Unset all legal units of the enterprise from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = false
        WHERE primary_for_enterprise
          AND enterprise_id = legal_unit_row.enterprise_id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'legal_unit', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified legal unit as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = true
        WHERE id = legal_unit_row.id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_build_object('table', 'legal_unit', 'id', id) INTO v_set_id FROM updated_row;

    -- Return a jsonb summary of changes including table and ids of changed legal units
    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$$;

END;
