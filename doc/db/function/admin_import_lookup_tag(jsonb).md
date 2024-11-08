```sql
CREATE OR REPLACE FUNCTION admin.import_lookup_tag(new_jsonb jsonb, OUT tag_id integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    tag_path_str TEXT := new_jsonb ->> 'tag_path';
    tag_path public.LTREE;
BEGIN
    -- Check if tag_path_str is not null and not empty
    IF tag_path_str IS NOT NULL AND tag_path_str <> '' THEN
        BEGIN
            -- Try to cast tag_path_str to public.LTREE
            tag_path := tag_path_str::public.LTREE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid tag_path for row % with error "%"', new_jsonb, SQLERRM;
        END;

        SELECT tag.id INTO tag_id
        FROM public.tag
        WHERE active
          AND path = tag_path;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Could not find tag_path for row %', new_jsonb;
        END IF;
    END IF;
END;
$function$
```
