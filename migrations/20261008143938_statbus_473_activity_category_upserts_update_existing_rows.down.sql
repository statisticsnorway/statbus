-- Down Migration 20261008143938: statbus_473 activity category upserts update existing rows
--
-- Restores the five function definitions exactly as dumped (\sf) before the up
-- migration and drops the (standard_id, path, custom) key. The parent_id repair
-- of the up migration is a data correction and is deliberately not reverted.
BEGIN;

ALTER TABLE public.activity_category DROP CONSTRAINT activity_category_standard_id_path_custom_key;

CREATE OR REPLACE FUNCTION public.lookup_parent_and_derive_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    code_pattern_var public.activity_category_code_behaviour;
    derived_code varchar;
    parent_path public.ltree;
BEGIN
    -- Look up the code pattern
    SELECT code_pattern INTO code_pattern_var
    FROM public.activity_category_standard
    WHERE id = NEW.standard_id;

    -- Derive the code based on the code pattern using CASE expression
    CASE code_pattern_var
        WHEN 'digits' THEN
            derived_code := regexp_replace(NEW.path::text, '[^0-9]', '', 'g');
        WHEN 'dot_after_two_digits' THEN
            derived_code := regexp_replace(regexp_replace(NEW.path::text, '[^0-9]', '', 'g'), '^([0-9]{2})(.+)$', '\1.\2');
        ELSE
            RAISE EXCEPTION 'Unknown code pattern: %', code_pattern_var;
    END CASE;

    -- Set the derived code
    NEW.code := derived_code;

    -- Ensure parent_id is consistent with the path
    -- Only update parent_id if path has parent segments
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO NEW.parent_id
        FROM public.activity_category
        WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
          AND enabled
        ;
    ELSE
        NEW.parent_id := NULL; -- No parent, set parent_id to NULL
    END IF;

    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    standardCode text;
    standardId int;
BEGIN
    -- Access the standard code passed as an argument
    standardCode := TG_ARGV[0];
    SELECT id INTO standardId FROM public.activity_category_standard WHERE code = standardCode;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Unknown activity_category_standard.code %', standardCode;
    END IF;

    WITH parent AS (
        SELECT activity_category.id
          FROM public.activity_category
         WHERE standard_id = standardId
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
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
    SELECT standardId
         , NEW.path
         , (SELECT id FROM parent)
         , NEW.name
         , NEW.description
         , statement_timestamp()
         , true
         , false
    ON CONFLICT (standard_id, path, enabled)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                , custom = false
        WHERE activity_category.id = EXCLUDED.id
                ;
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.delete_stale_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- All the `standard_id` with a recent update must be complete.
    WITH changed_activity_category AS (
      SELECT DISTINCT standard_id
      FROM public.activity_category
      WHERE updated_at = statement_timestamp()
    )
    -- Delete activities that have a stale updated_at
    DELETE FROM public.activity_category
    WHERE standard_id IN (SELECT standard_id FROM changed_activity_category)
    AND updated_at < statement_timestamp();
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.activity_category_enabled_custom_upsert_custom()
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
;

CREATE OR REPLACE FUNCTION admin.activity_category_enabled_upsert_custom()
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
;

END;
