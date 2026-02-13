```sql
CREATE OR REPLACE FUNCTION admin.activity_category_available_upsert_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    setting_standard_id int;
    found_parent_id int;
    existing_category_id int;
BEGIN
    -- Retrieve the setting_standard_id from public.settings
    SELECT standard_id INTO setting_standard_id FROM public.settings;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Missing public.settings.standard_id';
    END IF;

    -- Find parent category based on NEW.parent_code or NEW.path
    IF NEW.parent_code IS NOT NULL THEN
        -- If NEW.parent_code is provided, use it to find the parent category
        SELECT id INTO found_parent_id
          FROM public.activity_category
         WHERE code = NEW.parent_code
           AND standard_id = setting_standard_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent_code %', NEW.parent_code;
        END IF;
    ELSIF public.nlevel(NEW.path) > 1 THEN
        -- If NEW.parent_code is not provided, use NEW.path to find the parent category
        SELECT id INTO found_parent_id
          FROM public.activity_category
         WHERE standard_id = setting_standard_id
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1);
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
    ON CONFLICT (standard_id, path)
    DO UPDATE SET
            parent_id = found_parent_id
          , name = NEW.name
          , description = NEW.description
          , updated_at = statement_timestamp()
          , enabled = TRUE
          , custom = TRUE
       WHERE activity_category.id = EXCLUDED.id;

    RETURN NULL;
END;
$function$
```
