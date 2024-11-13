```sql
CREATE OR REPLACE FUNCTION admin.import_lookup_data_source(new_jsonb jsonb, OUT data_source_id integer, INOUT updated_invalid_codes jsonb)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    data_source_code TEXT;
BEGIN
    -- Get the value of the data_source_code field from the JSONB parameter
    data_source_code := new_jsonb ->> 'data_source_code';

    -- Check if data_source_code is not null and not empty
    IF data_source_code IS NOT NULL AND data_source_code <> '' THEN
        SELECT id INTO data_source_id
        FROM public.data_source
        WHERE code = data_source_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find data_source_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{data_source_code}', to_jsonb(data_source_code), true);
        END IF;
    END IF;
END;
$function$
```
