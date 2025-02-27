```sql
CREATE OR REPLACE FUNCTION admin.type_ltree_field(new_jsonb jsonb, field_name text, OUT ltree_value ltree, INOUT updated_fields_with_error jsonb)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    field_str TEXT;
    field_with_error JSONB;
BEGIN
    field_str := new_jsonb ->> field_name;

    -- Default unless specified.
    ltree_value := NULL;
    IF field_str IS NOT NULL AND field_str <> '' THEN
        BEGIN
            ltree_value := field_str::ltree;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            field_with_error := jsonb_build_object(field_name, field_str);
            updated_fields_with_error := updated_fields_with_error || field_with_error;
        END;
    END IF;
END;
$function$
```
