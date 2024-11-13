```sql
CREATE OR REPLACE FUNCTION admin.import_lookup_activity_category(new_jsonb jsonb, category_type text, OUT activity_category_id integer, INOUT updated_invalid_codes jsonb)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    category_code_field TEXT;
    category_code TEXT;
BEGIN
    IF category_type NOT IN ('primary', 'secondary') THEN
        RAISE EXCEPTION 'Invalid category_type: %', category_type;
    END IF;

    category_code_field := category_type || '_activity_category_code';

    -- Get the value of the category code field from the JSONB parameter
    category_code := new_jsonb ->> category_code_field;

    -- Check if category_code is not null and not empty
    IF category_code IS NOT NULL AND category_code <> '' THEN
        SELECT id INTO activity_category_id
        FROM public.activity_category_available
        WHERE code = category_code;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find % for row %', category_code_field, new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, ARRAY[category_code_field], to_jsonb(category_code), true);
        END IF;
    END IF;
END;
$function$
```
