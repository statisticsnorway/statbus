```sql
CREATE OR REPLACE FUNCTION admin.upsert_foreign_participation_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.foreign_participation (code, name, active, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 'f', statement_timestamp())
    ON CONFLICT (active, code) DO UPDATE SET
        name = NEW.name, active = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE foreign_participation.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
```
