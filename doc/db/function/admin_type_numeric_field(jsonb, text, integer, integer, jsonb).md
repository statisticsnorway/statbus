```sql
CREATE OR REPLACE FUNCTION admin.type_numeric_field(new_jsonb jsonb, field_name text, p_precision integer, p_scale integer, OUT numeric_value numeric, INOUT updated_fields_with_error jsonb)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    field_str TEXT;
    field_with_error JSONB;
BEGIN
    field_str := new_jsonb ->> field_name;

    -- Default unless specified.
    numeric_value := NULL;
    IF field_str IS NOT NULL AND field_str <> '' THEN
        BEGIN
            EXECUTE format('SELECT %L::numeric(%s,%s)', field_str, p_precision, p_scale) INTO numeric_value;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            field_with_error := jsonb_build_object(field_name, field_str);
            updated_fields_with_error := updated_fields_with_error || field_with_error;
        END;
    END IF;
END;
$function$
```
