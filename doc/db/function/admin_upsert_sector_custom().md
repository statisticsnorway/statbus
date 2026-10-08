```sql
CREATE OR REPLACE FUNCTION admin.upsert_sector_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.sector AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 't' THEN
        RAISE EXCEPTION 'sector path "%" already exists as a system (standard) entry, so this custom upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'A custom entry cannot replace a standard one with the same path. Use a path that is not in the standard list.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.sector
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.sector (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        enabled = TRUE,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
