BEGIN;

CREATE FUNCTION admin.import_lookup_unit_size(
    new_jsonb JSONB,
    invalid_codes JSONB DEFAULT '{}'::jsonb
) RETURNS TABLE (
    unit_size_id INTEGER,
    updated_invalid_codes JSONB
) LANGUAGE plpgsql AS $import_lookup_unit_size$
DECLARE
    unit_size_code TEXT;
    unit_size_id INTEGER;
BEGIN
    unit_size_code := NULLIF(TRIM(new_jsonb->>'unit_size_code'), '');
    
    IF unit_size_code IS NULL THEN
        RETURN QUERY SELECT NULL::INTEGER, invalid_codes;
        RETURN;
    END IF;
    
    SELECT id INTO unit_size_id
    FROM public.unit_size
    WHERE code = unit_size_code
    LIMIT 1;
    
    IF unit_size_id IS NULL THEN
        -- Unit size code not found, add to invalid codes
        RETURN QUERY SELECT 
            NULL::INTEGER, 
            jsonb_set(
                invalid_codes, 
                '{unit_size_code}', 
                to_jsonb(unit_size_code)
            );
    ELSE
        -- Unit size code found
        RETURN QUERY SELECT unit_size_id, invalid_codes;
    END IF;
END;
$import_lookup_unit_size$;

COMMENT ON FUNCTION admin.import_lookup_unit_size IS 
'Looks up a unit size by code and returns its ID. If not found, adds to invalid codes.';

END;
