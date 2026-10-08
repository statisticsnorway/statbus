```sql
CREATE OR REPLACE FUNCTION admin.upsert_tag_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.tag AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 'f' THEN
        RAISE EXCEPTION 'tag path "%" already exists as a custom entry, so this system (standard) upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
