```sql
CREATE OR REPLACE FUNCTION admin.upsert_enterprise_group_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.enterprise_group_type (code, name, active, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (active, code) DO UPDATE SET
        name = NEW.name, active = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE enterprise_group_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
```
