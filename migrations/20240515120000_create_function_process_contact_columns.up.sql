-- Migration 20250127211049: create_function_process_contact_columns
BEGIN;

CREATE FUNCTION admin.process_contact_columns(
    new_jsonb JSONB,
    p_establishment_id INTEGER,
    p_legal_unit_id INTEGER,
    p_valid_from DATE,
    p_valid_to DATE,
    p_data_source_id INTEGER,
    p_edit_by_user_id INTEGER
) RETURNS void
LANGUAGE plpgsql AS $process_contact_columns$
DECLARE
    has_contact_info BOOLEAN;
BEGIN
    -- Check if any contact fields are non-empty
    has_contact_info := (
        NULLIF(new_jsonb->>'web_address', '') IS NOT NULL OR
        NULLIF(new_jsonb->>'email_address', '') IS NOT NULL OR
        NULLIF(new_jsonb->>'phone_number', '') IS NOT NULL OR
        NULLIF(new_jsonb->>'landline', '') IS NOT NULL OR
        NULLIF(new_jsonb->>'mobile_number', '') IS NOT NULL OR
        NULLIF(new_jsonb->>'fax_number', '') IS NOT NULL
    );

    -- Only insert if we have some contact information
    IF has_contact_info THEN
        INSERT INTO public.contact_era (
            valid_from,
            valid_to,
            web_address,
            email_address,
            phone_number,
            landline,
            mobile_number,
            fax_number,
            establishment_id,
            legal_unit_id,
            data_source_id,
            edit_by_user_id,
            edit_at
        ) VALUES (
            p_valid_from,
            p_valid_to,
            NULLIF(new_jsonb->>'web_address', ''),
            NULLIF(new_jsonb->>'email_address', ''),
            NULLIF(new_jsonb->>'phone_number', ''),
            NULLIF(new_jsonb->>'landline', ''),
            NULLIF(new_jsonb->>'mobile_number', ''),
            NULLIF(new_jsonb->>'fax_number', ''),
            p_establishment_id,
            p_legal_unit_id,
            p_data_source_id,
            p_edit_by_user_id,
            statement_timestamp()
        );
    END IF;
END;
$process_contact_columns$;

END;
