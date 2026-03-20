```sql
CREATE OR REPLACE FUNCTION admin.upsert_tag_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, 'f', 't', statement_timestamp())
    ON CONFLICT (enabled, path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE tag.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
```
