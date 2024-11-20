\echo admin.type_date_field
CREATE FUNCTION admin.type_date_field(
    IN new_jsonb JSONB,
    IN field_name TEXT,
    OUT date_value DATE,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    date_str TEXT;
    invalid_code JSONB;
BEGIN
    date_str := new_jsonb ->> field_name;

    IF date_str IS NOT NULL AND date_str <> '' THEN
        BEGIN
            date_value := date_str::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            invalid_code := jsonb_build_object(field_name, date_str);
            updated_invalid_codes := updated_invalid_codes || invalid_code;
        END;
    END IF;
END;
$$ LANGUAGE plpgsql;