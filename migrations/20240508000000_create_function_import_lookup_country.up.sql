BEGIN;

CREATE FUNCTION admin.import_lookup_country(
    new_jsonb JSONB,
    country_type TEXT,
    OUT country_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    country_iso_2_field TEXT;
    country_iso_2 TEXT;
BEGIN
    -- Check that country_type is valid and determine the fields
    IF country_type NOT IN ('physical', 'postal') THEN
        RAISE EXCEPTION 'Invalid country_type: %', country_type;
    END IF;

    country_iso_2_field := country_type || '_country_iso_2';

    -- Get the value of the country ISO 2 field from the JSONB parameter
    country_iso_2 := new_jsonb ->> country_iso_2_field;

    -- Check if country_iso_2 is not null and not empty
    IF country_iso_2 IS NOT NULL AND country_iso_2 <> '' THEN
        SELECT country.id INTO country_id
        FROM public.country
        WHERE iso_2 = country_iso_2;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find % for row %', country_iso_2_field, new_jsonb;
            updated_invalid_codes := updated_invalid_codes || jsonb_build_object(country_iso_2_field, country_iso_2);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

END;
