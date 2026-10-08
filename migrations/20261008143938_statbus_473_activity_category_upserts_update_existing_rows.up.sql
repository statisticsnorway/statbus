-- Migration 20261008143938: statbus_473 activity category upserts update existing rows
--
-- The upsert triggers behind the activity_category_* views ended in
--   ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id
-- and activity_category.id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is
-- the freshly drawn id and never equals the stored row's id: the update never
-- fired. A custom re-upload with corrected labels was a silent no-op, and the
-- statement-level stale delete behind the standard views then removed every
-- code of a reloaded standard (activity.category_id cascades).
--
-- 1. The real key of a category is (standard_id, path, custom): at most one
--    system row and one custom override per code. It becomes a constraint and
--    every upsert conflicts on it, with no id predicate.
-- 2. The stale delete removes the system codes of the standard that the
--    statement did NOT address (recorded per row by the upsert), never by
--    wall-clock comparison, and never touches custom overrides.
-- 3. admin.activity_category_enabled_upsert_custom reads the real settings
--    column (activity_category_standard_id), the view's real parent column
--    (parent_path, there is no parent_code) and conflicts on the real key.
-- 4. Found while here: public.lookup_parent_and_derive_code looked the parent
--    up by path across ALL standards, so NACE rows pointed at ISIC parents.
--    It is scoped to the row's own standard and the existing links repaired.
-- The INSTEAD OF triggers return the row they wrote, so the statement's row
-- count (and RETURNING) reports what was stored rather than 0.
BEGIN;

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
        WHERE standard_id = NEW.standard_id
          AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
        -- (standard_id, path, enabled) is unique, so this is the enabled
        -- parent, or the disabled one mid-swap (public.reset re-parents
        -- children before it re-enables the system row).
        ORDER BY enabled DESC
        LIMIT 1
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

    -- Record that this statement addresses the code, so the statement-level
    -- admin.delete_stale_activity_category removes exactly the complement.
    -- (Triggers on views cannot have transition tables.)
    IF to_regclass('pg_temp.activity_category_addressed') IS NULL THEN
        CREATE TEMP TABLE activity_category_addressed
            ( standard_id int NOT NULL
            , path public.ltree NOT NULL
            , PRIMARY KEY (standard_id, path)
            ) ON COMMIT DROP;
    END IF;
    INSERT INTO pg_temp.activity_category_addressed(standard_id, path)
    VALUES (standardId, NEW.path)
    ON CONFLICT DO NOTHING;

    WITH parent AS (
        SELECT activity_category.id
          FROM public.activity_category
         WHERE standard_id = standardId
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled
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
         -- A new system code is shadowed by an existing custom override.
         , NOT EXISTS (
             SELECT 1 FROM public.activity_category AS override
              WHERE override.standard_id = standardId
                AND override.path OPERATOR(public.=) NEW.path
                AND override.custom
                AND override.enabled)
         , false
    ON CONFLICT (standard_id, path, custom)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                ;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.delete_stale_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- A load through a standard view is the complete standard: the system
    -- codes of that standard the statement did NOT address are stale.
    -- admin.upsert_activity_category recorded every addressed code; a
    -- statement that addressed none (empty load) deletes nothing. Custom
    -- overrides are never stale here, they are not part of the standard.
    IF to_regclass('pg_temp.activity_category_addressed') IS NULL THEN
        RETURN NULL;
    END IF;

    DELETE FROM public.activity_category AS ac
    WHERE ac.standard_id IN (SELECT DISTINCT standard_id FROM pg_temp.activity_category_addressed)
      AND NOT ac.custom
      AND NOT EXISTS (
          SELECT 1 FROM pg_temp.activity_category_addressed AS addressed
           WHERE addressed.standard_id = ac.standard_id
             AND addressed.path OPERATOR(public.=) ac.path);

    DROP TABLE pg_temp.activity_category_addressed;
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

    -- Perform an upsert operation on public.activity_category, keyed on the
    -- real key (standard_id, path, custom): a re-upload updates the override.
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
    ON CONFLICT (standard_id, path, custom)
    DO UPDATE SET
            parent_id = found_parent_id
          , name = NEW.name
          , description = NEW.description
          , updated_at = statement_timestamp()
          , enabled = TRUE
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Connect any children of the existing row to thew newly inserted row.
    IF existing_category_id IS NOT NULL THEN
        UPDATE public.activity_category
           SET parent_id = row.id
        WHERE parent_id = existing_category_id;
    END IF;

    -- Report the written row, so the statement's row count (INSERT 0 n,
    -- COPY n) is what was stored, never a silent 0.
    RETURN NEW;
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
;

-- Make (standard_id, path, custom) a real key. Existing boxes ran the broken
-- upserts for years, so a key may already hold two rows (the existing
-- (standard_id, path, enabled) key bounds it at two: one enabled, one not).
-- Dedupe before constraining, deterministically and from the rows alone:
-- the CANONICAL row of a key is the enabled one (the row every view shows),
-- then the lowest id. Every reference to a redundant row (activities, access
-- grants, child parent links) is moved to the canonical row first, so the
-- delete cascades to nothing; the redundant rows are then removed.
CREATE TEMP TABLE activity_category_redundant ON COMMIT DROP AS
SELECT ranked.id AS redundant_id
     , ranked.canonical_id
  FROM (
    SELECT ac.id
         , first_value(ac.id) OVER (
             PARTITION BY ac.standard_id, ac.path, ac.custom
             ORDER BY ac.enabled DESC, ac.id
           ) AS canonical_id
      FROM public.activity_category AS ac
  ) AS ranked
 WHERE ranked.id <> ranked.canonical_id;

UPDATE public.activity AS a
   SET category_id = r.canonical_id
  FROM pg_temp.activity_category_redundant AS r
 WHERE a.category_id = r.redundant_id;

DELETE FROM public.activity_category_access AS aca
 USING pg_temp.activity_category_redundant AS r
 WHERE aca.activity_category_id = r.redundant_id
   AND EXISTS (
       SELECT 1 FROM public.activity_category_access AS kept
        WHERE kept.user_id = aca.user_id
          AND kept.activity_category_id = r.canonical_id);

UPDATE public.activity_category_access AS aca
   SET activity_category_id = r.canonical_id
  FROM pg_temp.activity_category_redundant AS r
 WHERE aca.activity_category_id = r.redundant_id;

UPDATE public.activity_category AS child
   SET parent_id = r.canonical_id
  FROM pg_temp.activity_category_redundant AS r
 WHERE child.parent_id = r.redundant_id;

DO $report_activity_category_dedupe$
DECLARE
    _deleted_count bigint;
BEGIN
    WITH deleted AS (
        DELETE FROM public.activity_category AS ac
         USING pg_temp.activity_category_redundant AS r
         WHERE ac.id = r.redundant_id
        RETURNING ac.id
    )
    SELECT count(*) INTO _deleted_count FROM deleted;
    RAISE NOTICE 'STATBUS-473: removed % redundant activity_category row(s) duplicating (standard_id, path, custom)', _deleted_count;
END;
$report_activity_category_dedupe$;

ALTER TABLE public.activity_category
  ADD CONSTRAINT activity_category_standard_id_path_custom_key
  UNIQUE (standard_id, path, custom);

-- Repair the parent links the unscoped lookup wrote across standards (and any
-- orphan it left): re-derive every non-root parent through the corrected
-- trigger. Deterministic per row (own standard, parent path, enabled), so a
-- full replay and an incrementally migrated box end in the same state.
UPDATE public.activity_category
   SET path = path
 WHERE level > 1;

END;
