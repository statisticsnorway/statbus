```sql
CREATE OR REPLACE FUNCTION admin.activity_category_enabled_upsert_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    setting_standard_id int;
    found_parent_id int;
    existing_category_id int;
    row RECORD;
BEGIN
    -- Retrieve the setting_standard_id from public.settings
    SELECT activity_category_standard_id INTO setting_standard_id FROM public.settings;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Missing public.settings.activity_category_standard_id';
    END IF;

    -- Find parent category based on NEW.parent_path or NEW.path
    IF NEW.parent_path IS NOT NULL THEN
        -- If NEW.parent_path is provided, use it to find the parent category
        SELECT id INTO found_parent_id
          FROM public.activity_category
         WHERE path OPERATOR(public.=) NEW.parent_path
           AND standard_id = setting_standard_id
           AND enabled;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent_path %', NEW.parent_path;
        END IF;
    ELSIF public.nlevel(NEW.path) > 1 THEN
        -- If NEW.parent_path is not provided, use NEW.path to find the parent category
        SELECT id INTO found_parent_id
          FROM public.activity_category
         WHERE standard_id = setting_standard_id
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
    END IF;

    -- Query to see if there is an existing "enabled AND NOT custom" row
    SELECT id INTO existing_category_id
      FROM public.activity_category
     WHERE standard_id = setting_standard_id
       AND path = NEW.path
       AND enabled
       AND NOT custom;

    -- If there is, then update that row to enabled = FALSE
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET enabled = FALSE
         WHERE id = existing_category_id;
    END IF;

    -- Perform an upsert operation on public.activity_category
    INSERT INTO public.activity_category
        ( standard_id
        , path
        , parent_id
        , name
        , description
        , updated_at
        , enabled
        , custom
        )
    VALUES
        ( setting_standard_id
        , NEW.path
        , found_parent_id
        , NEW.name
        , NEW.description
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (standard_id, path, custom)
    DO UPDATE SET
            parent_id = found_parent_id
          , name = NEW.name
          , description = NEW.description
          , updated_at = statement_timestamp()
          , enabled = TRUE
       RETURNING * INTO row;

    -- Connect any children of the existing row to the newly inserted row.
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET parent_id = row.id
        WHERE parent_id = existing_category_id;
    END IF;

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
