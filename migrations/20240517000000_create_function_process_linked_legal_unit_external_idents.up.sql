BEGIN;

-- Find a connected legal_unit - i.e. a field with a `legal_unit`
-- prefix that points to an external identifier.
CREATE FUNCTION admin.process_linked_legal_unit_external_idents(
    new_jsonb JSONB,
    OUT legal_unit_id INTEGER,
    OUT linked_ident_specified BOOL
) RETURNS RECORD AS $process_linked_legal_unit_external_ident$
DECLARE
    unit_type TEXT := 'legal_unit';
    unit_fk_field TEXT;
    unit_fk_value INTEGER;
    ident_code TEXT;
    ident_value TEXT;
    ident_row public.external_ident;
    ident_type_row public.external_ident_type;
    ident_codes TEXT[] := '{}';
    -- Helpers to provide error messages to the user, with the ident_type_code
    -- that would otherwise be lost.
    ident_jsonb JSONB;
    prev_ident_jsonb JSONB;
BEGIN
    linked_ident_specified := false;
    unit_fk_value := NULL;
    legal_unit_id := NULL;

    unit_fk_field := unit_type || '_id';

    FOR ident_type_row IN
        (SELECT * FROM public.external_ident_type)
    LOOP
        ident_code := unit_type || '_' || ident_type_row.code;
        ident_codes := array_append(ident_codes, ident_code);

        IF new_jsonb ? ident_code THEN
            ident_value := new_jsonb ->> ident_code;

            IF ident_value IS NOT NULL AND ident_value <> '' THEN
                linked_ident_specified := true;

                SELECT to_jsonb(ei.*)
                     || jsonb_build_object(
                    'ident_code', ident_code -- For user feedback
                    ) INTO ident_jsonb
                FROM public.external_ident AS ei
                WHERE ei.type_id = ident_type_row.id
                  AND ei.ident = ident_value;

                IF NOT FOUND THEN
                  RAISE EXCEPTION 'Could not find % for row %', ident_code, new_jsonb;
                ELSE -- FOUND
                    unit_fk_value := (ident_jsonb -> unit_fk_field)::INTEGER;
                    IF unit_fk_value IS NULL THEN
                        RAISE EXCEPTION 'The external identifier % is not for a % but % for row %'
                                        , ident_code, unit_type, ident_jsonb, new_jsonb;
                    END IF;
                    IF legal_unit_id IS NULL THEN
                        legal_unit_id := unit_fk_value;
                    ELSEIF legal_unit_id IS DISTINCT FROM unit_fk_value THEN
                        -- All matching identifiers must be consistent.
                        RAISE EXCEPTION 'Inconsistent external identifiers % and % for row %'
                                        , prev_ident_jsonb, ident_jsonb, new_jsonb;
                    END IF;
                END IF; -- FOUND / NOT FOUND
                prev_ident_jsonb := ident_jsonb;
            END IF; -- ident_value provided
        END IF; -- ident_type.code in import
    END LOOP; -- public.external_ident_type
END; -- Process external identifiers
$process_linked_legal_unit_external_ident$ LANGUAGE plpgsql;

END;
