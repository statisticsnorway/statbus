```sql
CREATE OR REPLACE FUNCTION admin.type_date_field(new_jsonb jsonb, field_name text, OUT date_value date, INOUT updated_invalid_codes jsonb)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
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
$function$
```
