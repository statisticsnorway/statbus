```sql
CREATE OR REPLACE FUNCTION admin.upsert_reorg_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.reorg_type (code, name, description, active, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (active, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, active = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE reorg_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
```
