```sql
CREATE OR REPLACE FUNCTION admin.upsert_data_source_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.data_source (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
