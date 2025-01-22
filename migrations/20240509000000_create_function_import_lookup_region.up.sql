BEGIN;

CREATE FUNCTION admin.import_lookup_region(
    IN new_jsonb JSONB,
    IN region_type TEXT,
    OUT region_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    region_code_field TEXT;
    region_path_field TEXT;
    region_code TEXT;
    region_path_str TEXT;
    region_path public.LTREE;
BEGIN
    -- Check that region_type is valid and determine the fields
    IF region_type NOT IN ('physical', 'postal') THEN
        RAISE EXCEPTION 'Invalid region_type: %', region_type;
    END IF;

    region_code_field := region_type || '_region_code';
    region_path_field := region_type || '_region_path';

    -- Get the values of the region code and path fields from the JSONB parameter
    region_code := new_jsonb ->> region_code_field;
    region_path_str := new_jsonb ->> region_path_field;

    -- Check if both region_code and region_path are specified
    IF region_code IS NOT NULL AND region_code <> '' AND
       region_path_str IS NOT NULL AND region_path_str <> '' THEN
        RAISE EXCEPTION 'Only one of % or % can be specified for row %', region_code_field, region_path_field, new_jsonb;
    ELSE
        IF region_code IS NOT NULL AND region_code <> '' THEN
            SELECT id INTO region_id
            FROM public.region
            WHERE code = region_code;

            IF NOT FOUND THEN
                RAISE WARNING 'Could not find % for row %', region_code_field, new_jsonb;
                updated_invalid_codes := updated_invalid_codes || jsonb_build_object(region_code_field, region_code);
            END IF;
        ELSIF region_path_str IS NOT NULL AND region_path_str <> '' THEN
            BEGIN
                region_path := region_path_str::public.LTREE;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Invalid % for row % with error "%"', region_path_field, new_jsonb, SQLERRM;
            END;

            SELECT id INTO region_id
            FROM public.region
            WHERE path = region_path;

            IF NOT FOUND THEN
                RAISE WARNING 'Could not find % for row %', region_path_field, new_jsonb;
                updated_invalid_codes := updated_invalid_codes || jsonb_build_object(region_path_field, region_path);
            END IF;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

END;
