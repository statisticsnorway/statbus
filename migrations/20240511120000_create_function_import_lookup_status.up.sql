-- Migration 20250127145918: create function import lookup status
BEGIN;

CREATE FUNCTION admin.import_lookup_status(
    new_jsonb JSONB,
    OUT status_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    status_code TEXT;
BEGIN
    -- Get the value of the status_code field from the JSONB parameter
    status_code := new_jsonb ->> 'status_code';

    -- Check if status_code is not null and not empty
    IF status_code IS NOT NULL AND status_code <> '' THEN
        SELECT id INTO status_id
        FROM public.status
        WHERE code = status_code
          AND active;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid status_code for row %', new_jsonb;
        END IF;
    ELSE
        -- If no status code specified, use the default assigned status
        SELECT id INTO status_id
        FROM public.status
        WHERE assigned_by_default
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'No default status found (assigned_by_default=true and active=true)';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

END;
