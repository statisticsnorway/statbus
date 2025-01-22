BEGIN;

CREATE FUNCTION admin.import_lookup_legal_form(
    new_jsonb JSONB,
    OUT legal_form_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    legal_form_code TEXT;
BEGIN
    -- Get the value of the legal_form_code field from the JSONB parameter
    legal_form_code := new_jsonb ->> 'legal_form_code';

    -- Check if legal_form_code is not null and not empty
    IF legal_form_code IS NOT NULL AND legal_form_code <> '' THEN
        SELECT id INTO legal_form_id
        FROM public.legal_form
        WHERE code = legal_form_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find legal_form_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{legal_form_code}', to_jsonb(legal_form_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

END;
