BEGIN;

CREATE VIEW public.activity_category_available
WITH (security_invoker=on) AS
SELECT acs.code AS standard_code
     , ac.id
     , ac.path
     , acp.path AS parent_path
     , ac.code
     , ac.label
     , ac.name
     , ac.description
     , ac.custom
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
LEFT JOIN public.activity_category AS acp ON ac.parent_id = acp.id
WHERE acs.id = (SELECT activity_category_standard_id FROM public.settings)
  AND ac.active
ORDER BY path;


CREATE FUNCTION admin.activity_category_available_upsert_custom()
RETURNS TRIGGER AS $$
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

    -- Query to see if there is an existing "active AND NOT custom" row
    SELECT id INTO existing_category_id
      FROM public.activity_category
     WHERE standard_id = setting_standard_id
       AND path = NEW.path
       AND active
       AND NOT custom;

    -- If there is, then update that row to active = FALSE
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET active = FALSE
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
        , active
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
          , active = TRUE
          , custom = TRUE
       WHERE activity_category.id = EXCLUDED.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER activity_category_available_upsert_custom
INSTEAD OF INSERT ON public.activity_category_available
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_available_upsert_custom();


CREATE VIEW public.activity_category_available_custom(path, name, description)
WITH (security_invoker=on) AS
SELECT ac.path
     , ac.name
     , ac.description
FROM public.activity_category AS ac
WHERE ac.standard_id = (SELECT activity_category_standard_id FROM public.settings)
  AND ac.active
  AND ac.custom
ORDER BY path;

CREATE FUNCTION admin.activity_category_available_custom_upsert_custom()
RETURNS TRIGGER AS $$
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
           AND active;
        RAISE DEBUG 'found_parent_id %', found_parent_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
    END IF;

    -- Query to see if there is an existing "active AND NOT custom" row
    SELECT id INTO existing_category_id
      FROM public.activity_category
     WHERE standard_id = var_standard_id
       AND path = NEW.path
       AND active
       AND NOT custom;

    -- If there is, then update that row to active = FALSE
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET active = FALSE
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
        , active
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
    ON CONFLICT (standard_id, path, active)
    DO UPDATE SET
            parent_id = found_parent_id
          , name = NEW.name
          , description = NEW.description
          , updated_at = statement_timestamp()
          , active = TRUE
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
$$ LANGUAGE plpgsql;


CREATE TRIGGER activity_category_available_custom_upsert_custom
INSTEAD OF INSERT ON public.activity_category_available_custom
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_available_custom_upsert_custom();

END;
