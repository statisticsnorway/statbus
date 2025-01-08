BEGIN;

\echo admin.import_lookup_sector
CREATE FUNCTION admin.import_lookup_sector(
    new_jsonb JSONB,
    OUT sector_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    sector_code TEXT;
BEGIN
    -- Get the value of the sector_code field from the JSONB parameter
    sector_code := new_jsonb ->> 'sector_code';

    -- Check if sector_code is not null and not empty
    IF sector_code IS NOT NULL AND sector_code <> '' THEN
        SELECT id INTO sector_id
        FROM public.sector
        WHERE code = sector_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find sector_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{sector_code}', to_jsonb(sector_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

END;
