BEGIN;

CREATE FUNCTION public.connect_legal_unit_to_enterprise(
    legal_unit_id integer, -- $1
    enterprise_id integer, -- $2
    valid_from date DEFAULT current_date, -- $3
    valid_to date DEFAULT 'infinity' -- $4
)
RETURNS jsonb LANGUAGE plpgsql AS $$
#variable_conflict use_variable
DECLARE
    old_enterprise_id integer;
    updated_legal_unit_ids integer[];
    deleted_enterprise_id integer := NULL;
    is_primary BOOLEAN;
    other_legal_units_count INTEGER;
    new_primary_legal_unit_id INTEGER;
    valid_after_p DATE := $3 - '1 DAY'::INTERVAL;
    valid_to_p DATE := $4;
BEGIN
    -- Check if the enterprise exists
    IF NOT EXISTS(SELECT 1 FROM public.enterprise WHERE id = enterprise_id) THEN
        RAISE EXCEPTION 'Enterprise does not exist.';
    END IF;

    -- Retrieve current enterprise_id and if it's primary
    SELECT lu.enterprise_id, lu.primary_for_enterprise INTO old_enterprise_id, is_primary
    FROM public.legal_unit AS lu
    WHERE lu.id = legal_unit_id
    AND after_to_overlaps(valid_after_p, valid_to_p, lu.valid_after, lu.valid_to)
    ;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal Unit does not exist.';
    END IF;

    -- Idempotency check: If the legal unit is already connected to the given enterprise with the same parameters, do nothing.
    IF old_enterprise_id = enterprise_id THEN
        RETURN jsonb_build_object(
            'message', 'No changes made as the legal unit is already connected to the specified enterprise.',
            'legal_unit_id', legal_unit_id,
            'enterprise_id', enterprise_id
        );
    END IF;

    -- Check if there are other legal units and if none of them are primary
    IF is_primary THEN
        SELECT COUNT(lu.*) INTO other_legal_units_count
        FROM public.legal_unit AS lu
        WHERE enterprise_id = old_enterprise_id
          AND lu.id <> legal_unit_id
          AND after_to_overlaps(valid_after_p, valid_to_p, lu.valid_after, lu.valid_to);

        -- If there is only one other legal unit, set it to primary.
        IF other_legal_units_count = 1 THEN
            SELECT lu.id INTO new_primary_legal_unit_id
            FROM public.legal_unit AS lu
            WHERE lu.enterprise_id = old_enterprise_id
              AND lu.id <> legal_unit_id
              AND after_to_overlaps(valid_after_p, valid_to_p, lu.valid_after, lu.valid_to);

            -- TODO: Use update for portion instead.
            UPDATE public.legal_unit
            SET primary_for_enterprise = true
            WHERE id = new_primary_legal_unit_id
              AND after_to_overlaps(valid_after_p, valid_to_p, valid_after, valid_to);
        ELSIF other_legal_units_count > 1 THEN
            RAISE EXCEPTION 'Assign another primary legal_unit to existing enterprise first';
        END IF;
    END IF;

    -- Check if any other legal units are connected to this enterprise,
    -- and determine if this is_primary or not.
    SELECT NOT EXISTS (
        SELECT 1 
        FROM public.legal_unit AS lu
        WHERE lu.enterprise_id = enterprise_id
          AND lu.id != legal_unit_id
          AND after_to_overlaps(valid_after_p, valid_to_p, lu.valid_after, lu.valid_to)
    ) INTO is_primary;


    -- Connect the legal unit to the enterprise and track the updated id
    WITH updated AS (
        UPDATE public.legal_unit AS lu
        SET enterprise_id = enterprise_id
          , primary_for_enterprise = is_primary
        WHERE lu.id = legal_unit_id
          AND after_to_overlaps(valid_after_p, valid_to_p, lu.valid_after, lu.valid_to)
        RETURNING lu.id
    )
    SELECT array_agg(id) INTO updated_legal_unit_ids FROM updated;

    -- Remove possibly stale enterprise and capture its id if deleted
    WITH deleted AS (
        DELETE FROM public.enterprise AS en
        WHERE en.id = old_enterprise_id
        AND NOT EXISTS(
            SELECT 1
            FROM public.legal_unit AS lu
            WHERE lu.enterprise_id = old_enterprise_id
        )
        AND NOT EXISTS(
            SELECT 1
            FROM public.establishment AS es
            WHERE es.enterprise_id = old_enterprise_id
        )
        RETURNING id
    )
    SELECT id INTO deleted_enterprise_id FROM deleted;

    -- Return a jsonb summary of changes including the updated legal unit ids, old and new enterprise_ids, and deleted enterprise id if applicable
    RETURN jsonb_build_object(
        'updated_legal_unit_ids', updated_legal_unit_ids,
        'old_enterprise_id', old_enterprise_id,
        'new_enterprise_id', enterprise_id,
        'deleted_enterprise_id', deleted_enterprise_id
    );
END;
$$;

END;
