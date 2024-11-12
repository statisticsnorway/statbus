\echo admin.process_external_idents
CREATE FUNCTION admin.process_external_idents(
    new_jsonb JSONB,
    unit_type TEXT,
    OUT external_idents public.external_ident[],
    OUT prior_id INTEGER
) RETURNS RECORD AS $process_external_idents$
DECLARE
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
    unique_ident_specified BOOLEAN := false;
BEGIN
    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    unit_fk_field := unit_type || '_id';

    FOR ident_type_row IN
        (SELECT * FROM public.external_ident_type)
    LOOP
        ident_code := ident_type_row.code;
        ident_codes := array_append(ident_codes, ident_code);

        IF new_jsonb ? ident_code THEN
            ident_value := new_jsonb ->> ident_code;

            IF ident_value IS NOT NULL AND ident_value <> '' THEN
                unique_ident_specified := true;

                SELECT to_jsonb(ei.*)
                     || jsonb_build_object(
                    'ident_code', eit.code -- For user feedback
                    ) INTO ident_jsonb
                FROM public.external_ident AS ei
                JOIN public.external_ident_type AS eit
                  ON ei.type_id = eit.id
                WHERE eit.id = ident_type_row.id
                  AND ei.ident = ident_value;

                IF NOT FOUND THEN
                    -- Prepare a row to be added later after the legal_unit is created
                    -- and the legal_unit_id is known.
                    ident_jsonb := jsonb_build_object(
                                'ident_code', ident_type_row.code, -- For user feedback - ignored by jsonb_populate_record
                                'type_id', ident_type_row.id, -- For jsonb_populate_record
                                'ident', ident_value
                        );
                    -- Initialise the ROW using mandatory positions, however,
                    -- populate with jsonb_populate_record for avoiding possible mismatch.
                    ident_row := ROW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
                    ident_row := jsonb_populate_record(NULL::public.external_ident,ident_jsonb);
                    external_idents := array_append(external_idents, ident_row);
                ELSE -- FOUND
                    unit_fk_value := (ident_jsonb ->> unit_fk_field)::INTEGER;
                    IF unit_fk_value IS NULL THEN
                        DECLARE
                          conflicting_unit_type TEXT;
                        BEGIN
                          CASE
                            WHEN (ident_jsonb ->> 'establishment_id') IS NOT NULL THEN
                              conflicting_unit_type := 'establishment';
                            WHEN (ident_jsonb ->> 'legal_unit_id') IS NOT NULL THEN
                              conflicting_unit_type := 'legal_unit';
                            WHEN (ident_jsonb ->> 'enterprise_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise';
                            WHEN (ident_jsonb ->> 'enterprise_group_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise_group';
                            ELSE
                              RAISE EXCEPTION 'Missing logic for external_ident %', ident_jsonb;
                          END CASE;
                          RAISE EXCEPTION 'The external identifier % for % already taken by a % for row %'
                                          , ident_code, unit_type, conflicting_unit_type, new_jsonb;
                        END;
                    END IF;
                    IF prior_id IS NULL THEN
                        prior_id := unit_fk_value;
                    ELSEIF prior_id IS DISTINCT FROM unit_fk_value THEN
                        -- All matching identifiers must be consistent.
                        RAISE EXCEPTION 'Inconsistent external identifiers % and % for row %'
                                        , prev_ident_jsonb, ident_jsonb, new_jsonb;
                    END IF;
                END IF; -- FOUND / NOT FOUND
                prev_ident_jsonb := ident_jsonb;
            END IF; -- ident_value provided
        END IF; -- ident_type.code in import
    END LOOP; -- public.external_ident_type

    IF NOT unique_ident_specified THEN
        RAISE EXCEPTION 'No external identifier (%) is specified for row %', array_to_string(ident_codes, ','), new_jsonb;
    END IF;
END; -- Process external identifiers
$process_external_idents$ LANGUAGE plpgsql;