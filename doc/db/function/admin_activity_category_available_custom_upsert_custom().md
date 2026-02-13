```sql
CREATE OR REPLACE FUNCTION admin.activity_category_available_custom_upsert_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    var_standard_id int;
    found_parent_id int := NULL;
    existing_category_id int;
    existing_category RECORD;
    row RECORD;
BEGIN
    -- Retrieve the activity_category_standard_id from public.settings
    SELECT activity_category_standard_id INTO var_standard_id FROM public.settings;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Missing public.settings.activity_category_standard_id';
    END IF;

    -- Find parent category based on NEW.path
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO found_parent_id
          FROM public.activity_category
         WHERE standard_id = var_standard_id
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled;
        RAISE DEBUG 'found_parent_id %', found_parent_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
    END IF;

    -- Query to see if there is an existing "enabled AND NOT custom" row
    SELECT id INTO existing_category_id
      FROM public.activity_category
     WHERE standard_id = var_standard_id
       AND path = NEW.path
       AND enabled
       AND NOT custom;

    -- If there is, then update that row to enabled = FALSE
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET enabled = FALSE
         WHERE id = existing_category_id
         RETURNING * INTO existing_category;
        RAISE DEBUG 'EXISTING %', to_json(existing_category);
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
        ( var_standard_id
        , NEW.path
        , found_parent_id
        , NEW.name
        , NEW.description
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (standard_id, path, enabled)
    DO UPDATE SET
            parent_id = found_parent_id
          , name = NEW.name
          , description = NEW.description
          , updated_at = statement_timestamp()
          , enabled = TRUE
          , custom = TRUE
       WHERE activity_category.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Connect any children of the existing row to thew newly inserted row.
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET parent_id = row.id
        WHERE parent_id = existing_category_id;
    END IF;

    RETURN NULL;
END;
$function$
```
