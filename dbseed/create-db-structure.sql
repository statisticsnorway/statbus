BEGIN;
--
-- Hand edited PostgreSQL database dump.
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = true;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


SET default_tablespace = '';

SET default_table_access_method = heap;

-- Use international date time parsing, to avoid
-- confusion with local syntax, where day and month may be reversed.
ALTER DATABASE "postgres" SET datestyle TO 'ISO, DMY';
SET datestyle TO 'ISO, DMY';

-- We need longer timeout for larger loads.
-- Ref. https://supabase.com/docs/guides/database/postgres/configuration
-- For API users
ALTER ROLE authenticated SET statement_timeout = '120s';

-- Use a separate schema, that is not exposed by PostgREST, for administrative functions.
CREATE SCHEMA admin;

CREATE TYPE public.statbus_role_type AS ENUM('super_user','regular_user', 'restricted_user', 'external_user');

\echo public.statbus_role
CREATE TABLE public.statbus_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type public.statbus_role_type NOT NULL,
    name character varying(256) NOT NULL UNIQUE,
    description text
);
-- There can only ever be one role for most role types.
-- while there can be many different restricted_user roles, depending on the actual restrictions.
CREATE UNIQUE INDEX statbus_role_role_type ON public.statbus_role(type) WHERE type = 'super_user' OR type = 'regular_user' OR type = 'external_user';

\echo public.statbus_user
CREATE TABLE public.statbus_user (
  id SERIAL PRIMARY KEY,
  uuid uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
  UNIQUE (uuid)
);


-- inserts a row into public.profiles
\echo admin.create_new_statbus_user
CREATE FUNCTION admin.create_new_statbus_user()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  role_id INTEGER;
BEGIN
  -- Start with a minimal set of rights upon auto creation by trigger.
  SELECT id INTO role_id FROM public.statbus_role WHERE type = 'external_user';
  INSERT INTO public.statbus_user (uuid, role_id) VALUES (new.id, role_id);
  RETURN new;
END;
$$;

-- trigger the function every time a user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE admin.create_new_statbus_user();

INSERT INTO public.statbus_role(type, name, description) VALUES ('super_user', 'Super User', 'Can manage all metadata and do everything in the Web interface and manage role rights.');
INSERT INTO public.statbus_role(type, name, description) VALUES ('regular_user', 'Regular User', 'Can do everything in the Web interface.');
INSERT INTO public.statbus_role(type, name, description) VALUES ('restricted_user', 'Restricted User', 'Can see everything and edit according to assigned region and/or activity');
INSERT INTO public.statbus_role(type, name, description) VALUES ('external_user', 'External User', 'Can see selected information');


-- Helper auth functions are found at the end, after relevant tables are defined.

-- Example statbus_role checking
--CREATE POLICY "public view access" ON public_records AS PERMISSIVE FOR SELECT TO public USING (true);
--CREATE POLICY "premium view access" ON premium_records AS PERMISSIVE FOR SELECT TO authenticated USING (
--  has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type)
--);
--CREATE POLICY "premium and admin view access" ON premium_records AS PERMISSIVE FOR SELECT TO authenticated USING (
--  has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[])
--);


-- Piggyback on auth.users for scalability
-- Ref. https://github.com/supabase-community/supabase-custom-claims
-- and https://github.com/supabase-community/supabase-custom-claims/blob/main/install.sql


-- Use a separate user table, and add a custom permission
-- Ref. https://medium.com/@jimmyruann/row-level-security-custom-permission-base-authorization-with-supabase-91389e6fc48c

-- Use the built in postgres role system to have different roles
-- Ref. https://github.com/orgs/supabase/discussions/11948
-- Create a new role
-- CREATE ROLE new_role_1;
-- -- Allow the login logic to assign this new role
-- GRANT new_role_1 TO authenticator;
-- -- Mark the new role as having the same rights as
-- -- any authenticted person.
-- GRANT authenticated TO new_role_1
-- -- Change the user to use the new role
-- UPDATE auth.users SET role = 'new_role_1' WHERE id = <some-user-uuid>;


-- TODO: Formulate RLS for the roles.
--CREATE POLICY "Public users are viewable by everyone." ON "user" FOR SELECT USING ( true );
--CREATE POLICY "Users can insert their own data." ON "user" FOR INSERT WITH check ( auth.uid() = id );
--CREATE POLICY "Users can update own data." ON "user" FOR UPDATE USING ( auth.uid() = id );


-- =================================================================
-- BEGIN: Callbacks for code generation based on naming conventions.
-- =================================================================
CREATE SCHEMA lifecycle_callbacks;

-- Documentation for lifecycle_callbacks.run_table_lifecycle_callbacks
--
-- This trigger function is designed to manage lifecycle callbacks for tables.
-- It dynamically finds and executes procedures based on registered callbacks,
-- using the generate and cleanup helper procedures for shared code.
--
-- Table Structure:
--
-- 1. supported_table:
--    - Holds the list of tables that are supported by the lifecycle management.
--    - Columns:
--      - table_name: The table's name as regclass.
--      - after_insert_trigger_name: Name of the after insert trigger.
--      - after_update_trigger_name: Name of the after delete trigger.
--      - after_delete_trigger_name: Name of the after insert trigger.
--
-- 2. registered_callback:
--    - Holds the list of lifecycle callbacks registered for tables.
--    - Columns:
--      - label: A unique label for the callback.
--      - priority: An integer representing the priority of the callback.
--      - table_name: Array of tables (regclass) this callback applies to.
--      - generate_procedure: The procedure that generates data for the table.
--      - cleanup_procedure: The procedure that cleans up data for the table.
--
-- Usage:
-- 1. Register a table using `lifecycle_callbacks.add_table(...)`.
-- 2. Register callbacks using `lifecycle_callbacks.add(...)`.
-- 3. Associate this function as a trigger for table lifecycle events.
-- 4. Call `lifecycle_callbacks.generate(table_name)` or `lifecycle_callbacks.cleanup(table_name)` manually if needed.
--
-- Example:
--
-- CALL lifecycle_callbacks.add_table('external_ident_type');
-- CALL lifecycle_callbacks.add(
--     'label_for_concept',
--     ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
--     'lifecycle_callbacks.generate_label_for_concept',
--     'lifecycle_callbacks.cleanup_label_for_concept'
-- );

CREATE TABLE lifecycle_callbacks.supported_table (
    table_name regclass PRIMARY KEY,
    after_insert_trigger_name TEXT,
    after_update_trigger_name TEXT,
    after_delete_trigger_name TEXT
);

CREATE TABLE lifecycle_callbacks.registered_callback (
    label TEXT PRIMARY KEY,
    priority SERIAL NOT NULL,
    table_names regclass[],
    generate_procedure regproc NOT NULL,
    cleanup_procedure regproc NOT NULL
);

CREATE PROCEDURE lifecycle_callbacks.add_table(
    table_name regclass
)
LANGUAGE plpgsql AS $$
DECLARE
    schema_name TEXT;
    table_name_text TEXT;
    after_insert_trigger_name TEXT;
    after_update_trigger_name TEXT;
    after_delete_trigger_name TEXT;
BEGIN
    -- Ensure that the table exists
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = table_name) THEN
        RAISE EXCEPTION 'Table % does not exist.', table_name;
    END IF;

    -- Extract schema and table name from the table_identifier
    SELECT nspname, relname INTO schema_name, table_name_text
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Define trigger names based on the provided table name
    after_insert_trigger_name := format('%I_lifecycle_callbacks_after_insert', table_name_text);
    after_update_trigger_name := format('%I_lifecycle_callbacks_after_update', table_name_text);
    after_delete_trigger_name := format('%I_lifecycle_callbacks_after_delete', table_name_text);

    -- Insert the table into supported_table with trigger names
    INSERT INTO lifecycle_callbacks.supported_table (
        table_name,
        after_insert_trigger_name,
        after_update_trigger_name,
        after_delete_trigger_name
    )
    VALUES (
        table_name,
        after_insert_trigger_name,
        after_update_trigger_name,
        after_delete_trigger_name
    )
    ON CONFLICT DO NOTHING;

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER INSERT ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_insert_trigger_name, schema_name, table_name_text
    );

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER UPDATE ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_update_trigger_name, schema_name, table_name_text
    );

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER DELETE ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_delete_trigger_name, schema_name, table_name_text
    );

    RAISE NOTICE 'Triggers created for table: %', table_name_text;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.del_table(
    table_name_param regclass
)
LANGUAGE plpgsql AS $$
DECLARE
    trigger_info lifecycle_callbacks.supported_table;
    table_in_use BOOLEAN;
BEGIN
    -- Check if the table is still referenced in registered_callback
    SELECT EXISTS (
        SELECT 1 FROM lifecycle_callbacks.registered_callback
        WHERE table_names @> ARRAY[table_name_param]
    ) INTO table_in_use;

    IF table_in_use THEN
        RAISE EXCEPTION 'Cannot delete triggers for table % because it is still referenced in registered_callback.', table_name_param;
    END IF;

    -- Fetch trigger names from supported_table
    SELECT * INTO trigger_info
    FROM lifecycle_callbacks.supported_table
    WHERE table_name = table_name_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot triggers for table % because it is not registered.', table_name_param;
    END IF;

    -- Drop the triggers
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_insert_trigger_name, table_name_param);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_update_trigger_name, table_name_param);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_delete_trigger_name, table_name_param);

    -- Delete the table from supported_table
    DELETE FROM lifecycle_callbacks.supported_table
    WHERE table_name = table_name_param;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.add(
    label TEXT,
    table_names regclass[],
    generate_procedure regproc,
    cleanup_procedure regproc
)
LANGUAGE plpgsql AS $$
DECLARE
    missing_tables regclass[];
BEGIN
    IF array_length(table_names, 1) IS NULL THEN
        RAISE EXCEPTION 'table_names must have one entry';
    END IF;

    -- Find any tables in table_names that are not in supported_table
    SELECT ARRAY_AGG(t_name)
    INTO missing_tables
    FROM UNNEST(table_names) AS t_name
    WHERE t_name NOT IN (SELECT table_name FROM lifecycle_callbacks.supported_table);

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'One or more tables in % are not supported: %', table_names, missing_tables;
    END IF;

    -- Ensure that the procedures exist
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = generate_procedure) THEN
        RAISE EXCEPTION 'Generate procedure % does not exist.', generate_procedure;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = cleanup_procedure) THEN
        RAISE EXCEPTION 'Cleanup procedure % does not exist.', cleanup_procedure;
    END IF;

    -- Insert or update the registered_callback entry
    INSERT INTO lifecycle_callbacks.registered_callback
           (label, table_names, generate_procedure, cleanup_procedure)
    VALUES (label, table_names, generate_procedure, cleanup_procedure)
    ON CONFLICT DO NOTHING;

    -- Check if the record was inserted; if not, raise an exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Callback with label % already exists. Cannot overwrite.', label;
    END IF;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.del(
    label_param TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    higher_priority_label TEXT;
    rows_deleted INT;
BEGIN
    -- CTE to get the priority of the callback to be deleted
    WITH target_callback AS (
        SELECT priority
        FROM lifecycle_callbacks.registered_callback
        WHERE label = label_param
    )
    -- Check for a higher priority callback
    SELECT label
    INTO higher_priority_label
    FROM lifecycle_callbacks.registered_callback
    WHERE priority > (SELECT priority FROM target_callback)
    ORDER BY priority ASC
    LIMIT 1;

    -- If a higher priority callback exists, raise an error
    IF higher_priority_label IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot delete % because a higher priority callback % still exists.', label_param, higher_priority_label;
    END IF;

    -- Proceed with deletion if no higher priority callback exists
    DELETE FROM lifecycle_callbacks.registered_callback
    WHERE label = label_param;

    -- Get the number of rows affected by the DELETE operation
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;

    -- Provide feedback on the deletion
    IF rows_deleted > 0 THEN
        RAISE NOTICE 'Callback % has been successfully deleted.', label_param;
    ELSE
        RAISE NOTICE 'Callback % was not found and thus not deleted.', label_param;
    END IF;
END;
$$;


CREATE FUNCTION lifecycle_callbacks.cleanup_and_generate()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    proc_names TEXT[] := ARRAY['cleanup', 'generate'];
    proc_name TEXT;
    sql TEXT;
BEGIN
    -- Loop over the array of procedure names
    FOREACH proc_name IN ARRAY proc_names LOOP
        -- Generate the SQL for the current procedure
        sql := format('CALL lifecycle_callbacks.%I(%L)', proc_name, format('%I.%I', TG_TABLE_SCHEMA, TG_TABLE_NAME));

        -- Execute the SQL and handle exceptions
        BEGIN
            EXECUTE sql;
        EXCEPTION
            WHEN OTHERS THEN
                -- Handle any exception by capturing the SQL and error message
                RAISE EXCEPTION 'Error executing % procedure: %, Error details: %', proc_name, sql, SQLERRM;
        END;
    END LOOP;

    -- Return NULL for a statement-level trigger
    RETURN NULL;
END;
$$;


-- Helper procedures for generating and cleaning up specific tables.
CREATE PROCEDURE lifecycle_callbacks.generate(table_name regclass)
LANGUAGE plpgsql AS $$
DECLARE
    callback_procedure regproc;
    sql TEXT;
BEGIN
    -- Loop through each callback procedure directly from the SELECT query
    FOR callback_procedure IN
        SELECT generate_procedure
        FROM lifecycle_callbacks.registered_callback
        WHERE table_names @> ARRAY[table_name]
        ORDER BY priority ASC
    LOOP
        -- Generate the SQL statement for the current procedure
        sql := format('CALL %s();', callback_procedure);

        -- Execute the SQL statement with error handling
        BEGIN
            EXECUTE sql;
        EXCEPTION
            WHEN OTHERS THEN
                -- Handle any exception by capturing the SQL and error message
                RAISE EXCEPTION 'Error executing callback procedure: %, SQL: %, Error details: %',
                                callback_procedure, sql, SQLERRM;
        END;
    END LOOP;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.cleanup(table_name regclass DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    callback_procedure regproc;
    callback_sql TEXT;
BEGIN
    -- Loop through each callback procedure directly from the SELECT query
    FOR callback_procedure IN
        SELECT cleanup_procedure
        FROM lifecycle_callbacks.registered_callback
        WHERE table_name IS NULL OR table_names @> ARRAY[table_name]
        ORDER BY priority DESC
    LOOP
        callback_sql := format('CALL %s();', callback_procedure);
        BEGIN
            -- Attempt to execute the callback procedure
            EXECUTE callback_sql;
        EXCEPTION
            -- Capture any exception that occurs during the call
            WHEN OTHERS THEN
                -- Log the error along with the original call
                RAISE EXCEPTION 'Error executing callback procedure % for %: %', callback_sql, table_name, SQLERRM;
        END;
    END LOOP;
END;
$$;

GRANT USAGE ON SCHEMA lifecycle_callbacks TO authenticated;
GRANT EXECUTE ON FUNCTION lifecycle_callbacks.cleanup_and_generate() TO authenticated;

-- =================================================================
-- END: Callbacks for code generation based on naming conventions.
-- =================================================================



-- =================================================================
-- BEGIN: Render template with consistency checking.
-- =================================================================
CREATE FUNCTION admin.render_template(template TEXT, vars JSONB)
RETURNS TEXT AS $$
DECLARE
    required_variables TEXT[];
    provided_variables TEXT[];
    missing_variables TEXT[];
    excess_variables TEXT[];
    key TEXT;
BEGIN
    -- Extract all placeholders from the template using a capture group
    SELECT array_agg(DISTINCT match[1])
    INTO required_variables
    FROM regexp_matches(template, '\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}', 'g') AS match;

    -- Extract all keys from the provided JSONB object
    SELECT array_agg(var)
    INTO provided_variables
    FROM jsonb_object_keys(vars) AS var;

    -- Check variables.
    WITH
    required AS (SELECT unnest(required_variables) AS variable),
    provided AS (SELECT unnest(provided_variables) AS variable),
    missing AS (
        SELECT array_agg(variable) AS variables
        FROM required
        WHERE variable NOT IN (SELECT variable FROM provided)
    ),
    excess AS (
        SELECT array_agg(variable) AS variables
        FROM provided
        WHERE variable NOT IN (SELECT variable FROM required)
    )
    SELECT missing.variables, excess.variables
    INTO missing_variables, excess_variables
    FROM missing, excess;

    -- Raise exception if there are missing variables
    IF array_length(missing_variables, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'Missing variables: %', array_to_string(missing_variables, ', ');
    END IF;

    -- Raise exception if there are excess variables
    IF array_length(excess_variables, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'Unsupported variables: %', array_to_string(excess_variables, ', ');
    END IF;

    -- Perform the replacement
    FOREACH key IN ARRAY provided_variables LOOP
        template := REPLACE(template, '{{' || key || '}}', COALESCE(vars->>key,''));
    END LOOP;

    RETURN template;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- END: Render template with consistency checking.
-- =================================================================




\echo public.activity_category_code_behaviour
CREATE TYPE public.activity_category_code_behaviour AS ENUM ('digits', 'dot_after_two_digits');

\echo public.activity_category_standard
CREATE TABLE public.activity_category_standard (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code character varying(16) UNIQUE NOT NULL,
    name character varying UNIQUE NOT NULL,
    description character varying UNIQUE NOT NULL,
    code_pattern public.activity_category_code_behaviour NOT NULL, -- Custom type
    obsolete boolean NOT NULL DEFAULT false
);

INSERT INTO public.activity_category_standard(code, name, description, code_pattern)
VALUES ('isic_v4', 'ISIC 4', 'ISIC Version 4', 'digits')
     , ('nace_v2.1', 'NACE 2.1', 'NACE Version 2 Revision 1', 'dot_after_two_digits');

CREATE EXTENSION ltree SCHEMA public;

CREATE TABLE public.activity_category (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    path public.ltree NOT NULL,
    parent_id integer REFERENCES public.activity_category(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar NOT NULL,
    name character varying(256) NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(standard_id, path, active)
);
CREATE INDEX ix_activity_category_parent_id ON public.activity_category USING btree (parent_id);

-- Trigger function to handle path updates, derive code, and lookup parent
CREATE FUNCTION public.lookup_parent_and_derive_code() RETURNS trigger LANGUAGE plpgsql AS $$
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
          AND active
        ;
    ELSE
        NEW.parent_id := NULL; -- No parent, set parent_id to NULL
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger to call the function before insert or update
CREATE TRIGGER lookup_parent_and_derive_code_before_insert_update
BEFORE INSERT OR UPDATE ON public.activity_category
FOR EACH ROW
EXECUTE FUNCTION public.lookup_parent_and_derive_code();


\echo admin.upsert_activity_category
CREATE FUNCTION admin.upsert_activity_category()
RETURNS TRIGGER AS $$
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
        , active
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
    ON CONFLICT (standard_id, path, active)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                , custom = false
        WHERE activity_category.id = EXCLUDED.id
                ;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



\echo admin.delete_stale_activity_category
CREATE FUNCTION admin.delete_stale_activity_category()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

\echo public.activity_category_isic_v4
CREATE VIEW public.activity_category_isic_v4
WITH (security_invoker=on) AS
SELECT acs.code AS standard
     , ac.path
     , ac.label
     , ac.code
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs
ON ac.standard_id = acs.id
WHERE acs.code = 'isic_v4'
ORDER BY path;

CREATE TRIGGER upsert_activity_category_isic_v4
INSTEAD OF INSERT ON public.activity_category_isic_v4
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_activity_category('isic_v4');

CREATE TRIGGER delete_stale_activity_category_isic_v4
AFTER INSERT ON public.activity_category_isic_v4
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_activity_category();

\copy public.activity_category_isic_v4(path, name) FROM 'dbseed/activity-category-standards/ISIC_Rev_4_english_structure.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"');


\echo public.activity_category_nace_v2_1
CREATE VIEW public.activity_category_nace_v2_1
WITH (security_invoker=on) AS
SELECT acs.code AS standard
     , ac.path
     , ac.label
     , ac.code
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs
ON ac.standard_id = acs.id
WHERE acs.code = 'nace_v2.1'
ORDER BY path;

CREATE TRIGGER upsert_activity_category_nace_v2_1
INSTEAD OF INSERT ON public.activity_category_nace_v2_1
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_activity_category('nace_v2.1');

CREATE TRIGGER delete_stale_activity_category_nace_v2_1
AFTER INSERT ON public.activity_category_nace_v2_1
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_activity_category();

\copy public.activity_category_nace_v2_1(path, name, description) FROM 'dbseed/activity-category-standards/NACE2.1_Structure_Label_Notes_EN.import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"');


-- Settings as configured by the system.
\echo public.settings
CREATE TABLE public.settings (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    activity_category_standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    only_one_setting BOOLEAN NOT NULL DEFAULT true,
    CHECK(only_one_setting),
    UNIQUE(only_one_setting)
);


\echo public.activity_category_available
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


\echo admin.activity_category_available_upsert_custom
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



\echo public.activity_category_available_custom
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

\echo admin.activity_category_available_custom_upsert_custom
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

\echo public.activity_category_role
CREATE TABLE public.activity_category_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
    activity_category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    UNIQUE(role_id, activity_category_id)
);
CREATE INDEX ix_activity_category_role_activity_category_id ON public.activity_category_role USING btree (activity_category_id);
CREATE INDEX ix_activity_category_role_role_id ON public.activity_category_role USING btree (role_id);


\echo public.analysis_queue
CREATE TABLE public.analysis_queue (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_start_period timestamp with time zone NOT NULL,
    user_end_period timestamp with time zone NOT NULL,
    user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    comment text,
    server_start_period timestamp with time zone,
    server_end_period timestamp with time zone
);
CREATE INDEX ix_analysis_queue_user_id ON public.analysis_queue USING btree (user_id);


\echo public.country
CREATE TABLE public.country (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso_2 text UNIQUE NOT NULL,
    iso_3 text UNIQUE NOT NULL,
    iso_num text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(iso_2, iso_3, iso_num, name)
);
CREATE UNIQUE INDEX ix_country_iso_2 ON public.country USING btree (iso_2) WHERE active;
CREATE UNIQUE INDEX ix_country_iso_3 ON public.country USING btree (iso_3) WHERE active;
CREATE UNIQUE INDEX ix_country_iso_num ON public.country USING btree (iso_num) WHERE active;


\echo public.custom_analysis_check
CREATE TABLE public.custom_analysis_check (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name character varying(64),
    query character varying(2048),
    target_unit_types character varying(16)
);


\echo public.data_source
CREATE TABLE public.data_source (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_data_source_code ON public.data_source USING btree (code) WHERE active;


\echo public.tag_type
CREATE TYPE public.tag_type AS ENUM ('custom', 'system');

\echo public.tag
CREATE TABLE public.tag (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer REFERENCES public.tag(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name character varying(256) NOT NULL,
    description text,
    active boolean NOT NULL DEFAULT true,
    type public.tag_type NOT NULL,
    context_valid_after date GENERATED ALWAYS AS (context_valid_from - INTERVAL '1 day') STORED,
    context_valid_from date,
    context_valid_to date,
    context_valid_on date,
    is_scoped_tag bool NOT NULL DEFAULT false,
    updated_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT "context_valid_from leq context_valid_to"
    CHECK(context_valid_from <= context_valid_to),
    CONSTRAINT "context_valid_dates_same_nullability"
    CHECK(  context_valid_from IS NULL AND context_valid_to IS NULL
         OR context_valid_from IS NOT NULL AND context_valid_to IS NOT NULL
         )
);


\echo public.relative_period_code
CREATE TYPE public.relative_period_code AS ENUM (
    -- For data entry with context_valid_from and context_valid_to. context_valid_on should be context_valid_from when infinity, else context_valid_to
    'today',
    'year_curr',
    'year_prev',
    'year_curr_only',
    'year_prev_only',

    -- For data query with context_valid_on only, no context_valid_from and context_valid_to
    'start_of_week_curr',
    'stop_of_week_prev',
    'start_of_week_prev',

    'start_of_month_curr',
    'stop_of_month_prev',
    'start_of_month_prev',

    'start_of_quarter_curr',
    'stop_of_quarter_prev',
    'start_of_quarter_prev',

    'start_of_semester_curr',
    'stop_of_semester_prev',
    'start_of_semester_prev',

    'start_of_year_curr',
    'stop_of_year_prev',
    'start_of_year_prev',

    'start_of_quinquennial_curr',
    'stop_of_quinquennial_prev',
    'start_of_quinquennial_prev',

    'start_of_decade_curr',
    'stop_of_decade_prev',
    'start_of_decade_prev'
);

\echo public.relative_period_scope
CREATE TYPE public.relative_period_scope AS ENUM (
    'input_and_query',
    'query',
    'input'
);

\echo public.relative_period
CREATE TABLE public.relative_period (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code public.relative_period_code UNIQUE NOT NULL,
    name_when_query character varying(256),
    name_when_input character varying(256),
    scope public.relative_period_scope NOT NULL,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT "scope input_and_query requires name_when_input"
    CHECK (
        CASE scope
        WHEN 'input_and_query' THEN name_when_input IS NOT NULL AND name_when_query IS NOT NULL
        WHEN 'query'           THEN name_when_input IS     NULL AND name_when_query IS NOT NULL
        WHEN 'input'           THEN name_when_input IS NOT NULL AND name_when_query IS     NULL
        END
    )
);

\echo public.relative_period_with_time
CREATE VIEW public.relative_period_with_time AS
-- Notice that all input types also has a valid_on date for query,
-- that matches the valid_from if one swiches from input to query
-- that can be used.
SELECT *,
       --
       CASE code
           --
           WHEN 'today' THEN current_date
           WHEN 'year_prev' THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_prev_only'           THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_curr' THEN current_date
           WHEN 'year_curr_only'           THEN current_date
           --
           WHEN 'today' THEN current_date
           WHEN 'start_of_week_curr'     THEN date_trunc('week', current_date)
           WHEN 'stop_of_week_prev'      THEN date_trunc('week', current_date) - interval '1 day'
           WHEN 'start_of_week_prev'     THEN date_trunc('week', current_date - interval '1 week')
           WHEN 'start_of_month_curr'    THEN date_trunc('month', current_date)
           WHEN 'stop_of_month_prev'     THEN (date_trunc('month', current_date) - interval '1 day')
           WHEN 'start_of_month_prev'    THEN date_trunc('month', current_date - interval '1 month')
           WHEN 'start_of_quarter_curr'  THEN date_trunc('quarter', current_date)
           WHEN 'stop_of_quarter_prev'   THEN (date_trunc('quarter', current_date) - interval '1 day')
           WHEN 'start_of_quarter_prev'  THEN date_trunc('quarter', current_date - interval '3 months')
           WHEN 'start_of_semester_curr' THEN
               CASE
                   WHEN EXTRACT(month FROM current_date) <= 6
                   THEN date_trunc('year', current_date)
                   ELSE date_trunc('year', current_date) + interval '6 months'
               END
            WHEN 'stop_of_semester_prev' THEN
                CASE
                    WHEN EXTRACT(month FROM current_date) <= 6
                    THEN date_trunc('year', current_date) - interval '1 day' -- End of December last year
                    ELSE date_trunc('year', current_date) + interval '6 months' - interval '1 day' -- End of June current year
                END
           WHEN 'start_of_semester_prev' THEN
               CASE
                   WHEN EXTRACT(month FROM current_date) <= 6 THEN date_trunc('year', current_date) - interval '6 months'
                   ELSE date_trunc('year', current_date)
               END
           WHEN 'start_of_year_curr'         THEN  date_trunc('year', current_date)
           WHEN 'stop_of_year_prev'          THEN (date_trunc('year', current_date) - interval '1 day')
           WHEN 'start_of_year_prev'         THEN  date_trunc('year', current_date - interval '1 year')

           WHEN 'start_of_quinquennial_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5))
           WHEN 'stop_of_quinquennial_prev'  THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '1 day'
           WHEN 'start_of_quinquennial_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '5 years'

           WHEN 'start_of_decade_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10))
           WHEN 'stop_of_decade_prev'  THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '1 day'
           WHEN 'start_of_decade_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '10 years'
           ELSE NULL
       END::DATE AS valid_on,
       --
       CASE code
           WHEN 'today'          THEN current_date
           WHEN 'year_prev'      THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_curr'      THEN date_trunc('year', current_date)::DATE
           WHEN 'year_prev_only' THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_curr_only' THEN date_trunc('year', current_date)::DATE
           --
           ELSE NULL
       END::DATE AS valid_from,
       --
       CASE code
           WHEN 'today'          THEN 'infinity'::DATE
           WHEN 'year_prev'      THEN 'infinity'::DATE
           WHEN 'year_curr'      THEN 'infinity'::DATE
           WHEN 'year_prev_only' THEN date_trunc('year', current_date)::DATE - interval '1 day'
           WHEN 'year_curr_only' THEN date_trunc('year', current_date + interval '1 year')::DATE - interval '1 day'
           ELSE NULL
       END::DATE as valid_to
       --
FROM public.relative_period;


DO $$
DECLARE
    parent_id integer;
BEGIN
    INSERT INTO public.relative_period
        (code                         , name_when_query                      , name_when_input                  , scope             , active)
    VALUES
        ('today'                      , 'Today'                              , 'From today and onwards'         , 'input_and_query' , false)   ,
        --
        ('year_curr'                  , 'Current Year'                       , 'Current year and onwards'       , 'input_and_query' , true)   ,
        ('year_prev'                  , 'Previous Year'                      , 'From previous year and onwards' , 'input_and_query' , true)   ,
        ('year_curr_only'             , NULL                                 , 'Current year only'              , 'input'           , false)   ,
        ('year_prev_only'             , NULL                                 , 'Previous year only'             , 'input'           , false)   ,
        --
        ('start_of_week_curr'         , 'Start of Current Week'              , NULL                             , 'query'           , false)  ,
        ('stop_of_week_prev'          , 'End of Previous Week'               , NULL                             , 'query'           , false)  ,
        ('start_of_week_prev'         , 'Start of Previous Week'             , NULL                             , 'query'           , false)  ,
        ('start_of_month_curr'        , 'Start of Current Month'             , NULL                             , 'query'           , false)  ,
        ('stop_of_month_prev'         , 'End of Previous Month'              , NULL                             , 'query'           , false)  ,
        ('start_of_month_prev'        , 'Start of Previous Month'            , NULL                             , 'query'           , false)  ,
        ('start_of_quarter_curr'      , 'Start of Current Quarter'           , NULL                             , 'query'           , false)  ,
        ('stop_of_quarter_prev'       , 'End of Previous Quarter'            , NULL                             , 'query'           , false)  ,
        ('start_of_quarter_prev'      , 'Start of Previous Quarter'          , NULL                             , 'query'           , false)  ,
        ('start_of_semester_curr'     , 'Start of Current Semester'          , NULL                             , 'query'           , false)  ,
        ('stop_of_semester_prev'      , 'End of Previous Semester'           , NULL                             , 'query'           , false)  ,
        ('start_of_semester_prev'     , 'Start of Previous Semester'         , NULL                             , 'query'           , false)  ,
        ('start_of_year_curr'         , 'Start of Current Year'              , NULL                             , 'query'           , true)   ,
        ('stop_of_year_prev'          , 'End of Previous Year'               , NULL                             , 'query'           , true)   ,
        ('start_of_year_prev'         , 'Start of Previous Year'             , NULL                             , 'query'           , true)   ,
        ('start_of_quinquennial_curr' , 'Start of Current Five-Year Period'  , NULL                             , 'query'           , false)  ,
        ('stop_of_quinquennial_prev'  , 'End of Previous Five-Year Period'   , NULL                             , 'query'           , false)  ,
        ('start_of_quinquennial_prev' , 'Start of Previous Five-Year Period' , NULL                             , 'query'           , false)  ,
        ('start_of_decade_curr'       , 'Start of Current Decade'            , NULL                             , 'query'           , false)  ,
        ('stop_of_decade_prev'        , 'End of Previous Decade'             , NULL                             , 'query'           , false)  ,
        ('start_of_decade_prev'       , 'Start of Previous Decade'           , NULL                             , 'query'           , false)
    ;
END $$;


\echo public.time_context_type
CREATE TYPE public.time_context_type AS ENUM (
    'relative_period',
    'tag'
);

\echo public.time_context
CREATE VIEW public.time_context
  ( type
  , ident
  , name_when_query
  , name_when_input
  , scope
  , valid_on
  , valid_from
  , valid_to
  , code         -- Exposing the code for ordering
  , path         -- Exposing the path for ordering
  ) AS
WITH combined_data AS (
  SELECT 'relative_period'::public.time_context_type AS type
  ,      'r_'||code::VARCHAR                   AS ident
  ,      name_when_query                       AS name_when_query
  ,      name_when_input                       AS name_when_input
  ,      scope                                 AS scope
  ,      valid_on                              AS valid_on
  ,      valid_from                            AS valid_from
  ,      valid_to                              AS valid_to
  ,      code                                  AS code  -- Specific order column for relative_period
  ,      NULL::public.LTREE                    AS path  -- Null for path as not applicable here
  FROM public.relative_period_with_time
  WHERE active

  UNION ALL

  SELECT 'tag'::public.time_context_type                 AS type
  ,      't:'||path::VARCHAR                             AS ident
  ,      description                                     AS name_when_query
  ,      description                                     AS name_when_input
  ,      'input_and_query'::public.relative_period_scope AS scope
  ,      context_valid_from                              AS valid_from
  ,      context_valid_to                                AS valid_to
  ,      context_valid_on                                AS valid_on
  ,      NULL::public.relative_period_code               AS code  -- Null for code as not applicable here
  ,      path                                            AS path  -- Specific order column for tag
  FROM public.tag
  WHERE active
    AND context_valid_from IS NOT NULL
    AND context_valid_to   IS NOT NULL
    AND context_valid_on   IS NOT NULL
)
SELECT *
FROM combined_data
ORDER BY type, code, path;



\echo public.unit_size
CREATE TABLE public.unit_size (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_unit_size_code ON public.unit_size USING btree (code) WHERE active;


\echo public.reorg_type
CREATE TABLE public.reorg_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_reorg_type_code ON public.reorg_type USING btree (code) WHERE active;


\echo public.foreign_participation
CREATE TABLE public.foreign_participation (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_foreign_participation_code ON public.foreign_participation USING btree (code) WHERE active;


\echo public.enterprise_group_type
CREATE TABLE public.enterprise_group_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_enterprise_group_type_code ON public.enterprise_group_type USING btree (code) WHERE active;


\echo public.enterprise_group
CREATE TABLE public.enterprise_group (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name varchar(16),
    name varchar(256),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    enterprise_group_type_id integer REFERENCES public.enterprise_group_type(id),
    telephone_no text,
    email_address text,
    web_address text,
    contact_person text,
    notes text,
    edit_by_user_id integer NOT NULL,
    edit_comment text,
    unit_size_id integer REFERENCES public.unit_size(id),
    data_source_id integer REFERENCES public.data_source(id),
    reorg_references text,
    reorg_date timestamp with time zone,
    reorg_type_id integer REFERENCES public.reorg_type(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id)
);
CREATE INDEX ix_enterprise_group_data_source_id ON public.enterprise_group USING btree (data_source_id);
CREATE INDEX ix_enterprise_group_enterprise_group_type_id ON public.enterprise_group USING btree (enterprise_group_type_id);
CREATE INDEX ix_enterprise_group_foreign_participation_id ON public.enterprise_group USING btree (foreign_participation_id);
CREATE INDEX ix_enterprise_group_name ON public.enterprise_group USING btree (name);
CREATE INDEX ix_enterprise_group_reorg_type_id ON public.enterprise_group USING btree (reorg_type_id);
CREATE INDEX ix_enterprise_group_size_id ON public.enterprise_group USING btree (unit_size_id);


\echo admin.enterprise_group_id_exists
CREATE FUNCTION admin.enterprise_group_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.enterprise_group WHERE id = fk_id);
$$;

\echo public.enterprise_group_role
CREATE TABLE public.enterprise_group_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_enterprise_group_role_code ON public.enterprise_group_role USING btree (code) WHERE active;


\echo public.sector
CREATE TABLE public.sector (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(path, active, custom)
);
CREATE UNIQUE INDEX sector_code_active_key ON public.sector USING btree (code) WHERE active;
CREATE INDEX sector_parent_id_idx ON public.sector USING btree (parent_id);


\echo public.enterprise
CREATE TABLE public.enterprise (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    notes text,
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500)
);


\echo public.legal_form
CREATE TABLE public.legal_form (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(code, active, custom)
);
\echo ix_legal_form_code
CREATE UNIQUE INDEX ix_legal_form_code ON public.legal_form USING btree (code) WHERE active;


\echo public.legal_unit
CREATE TABLE public.legal_unit (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    birth_date date,
    death_date date,
    parent_org_link integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    free_econ_zone boolean,
    notes text,
    sector_id integer REFERENCES public.sector(id),
    legal_form_id integer REFERENCES public.legal_form(id),
    reorg_date timestamp with time zone,
    reorg_references integer,
    reorg_type_id integer REFERENCES public.reorg_type(id),
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500),
    unit_size_id integer REFERENCES public.unit_size(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    enterprise_id integer NOT NULL REFERENCES public.enterprise(id) ON DELETE RESTRICT,
    primary_for_enterprise boolean NOT NULL,
    invalid_codes jsonb
);

\echo legal_unit_active_idx
CREATE INDEX legal_unit_active_idx ON public.legal_unit(active);
\echo ix_legal_unit_data_source_id
CREATE INDEX ix_legal_unit_data_source_id ON public.legal_unit USING btree (data_source_id);
\echo ix_legal_unit_enterprise_id
CREATE INDEX ix_legal_unit_enterprise_id ON public.legal_unit USING btree (enterprise_id);
\echo ix_legal_unit_foreign_participation_id
CREATE INDEX ix_legal_unit_foreign_participation_id ON public.legal_unit USING btree (foreign_participation_id);
\echo ix_legal_unit_sector_id
CREATE INDEX ix_legal_unit_sector_id ON public.legal_unit USING btree (sector_id);
\echo ix_legal_unit_legal_form_id
CREATE INDEX ix_legal_unit_legal_form_id ON public.legal_unit USING btree (legal_form_id);
\echo ix_legal_unit_name
CREATE INDEX ix_legal_unit_name ON public.legal_unit USING btree (name);
\echo ix_legal_unit_reorg_type_id
CREATE INDEX ix_legal_unit_reorg_type_id ON public.legal_unit USING btree (reorg_type_id);
\echo ix_legal_unit_size_id
CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (unit_size_id);


\echo admin.legal_unit_id_exists
CREATE FUNCTION admin.legal_unit_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.legal_unit WHERE id = fk_id);
$$;

\echo public.establishment
CREATE TABLE public.establishment (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    birth_date date,
    death_date date,
    parent_org_link integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    free_econ_zone boolean,
    notes text,
    sector_id integer REFERENCES public.sector(id),
    reorg_date timestamp with time zone,
    reorg_references integer,
    reorg_type_id integer REFERENCES public.reorg_type(id),
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500),
    unit_size_id integer REFERENCES public.unit_size(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE RESTRICT,
    legal_unit_id integer,
    primary_for_legal_unit boolean,
    invalid_codes jsonb,
    CONSTRAINT "Must have either legal_unit_id or enterprise_id"
    CHECK( enterprise_id IS NOT NULL AND legal_unit_id IS     NULL
        OR enterprise_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    CONSTRAINT "primary_for_legal_unit and legal_unit_id must be defined together"
    CHECK( legal_unit_id IS NOT NULL AND primary_for_legal_unit IS NOT NULL
        OR legal_unit_id IS     NULL AND primary_for_legal_unit IS     NULL
        ),
    CONSTRAINT "enterprise_id enables sector_id"
    CHECK( CASE WHEN enterprise_id IS NULL THEN sector_id IS NULL END)
);

\echo establishment_active_idx
CREATE INDEX establishment_active_idx ON public.establishment(active);
\echo ix_establishment_data_source_id
CREATE INDEX ix_establishment_data_source_id ON public.establishment USING btree (data_source_id);
\echo ix_establishment_sector_id
CREATE INDEX ix_establishment_sector_id ON public.establishment USING btree (sector_id);
\echo ix_establishment_enterprise_id
CREATE INDEX ix_establishment_enterprise_id ON public.establishment USING btree (enterprise_id);
\echo ix_establishment_legal_unit_id
CREATE INDEX ix_establishment_legal_unit_id ON public.establishment USING btree (legal_unit_id);
\echo ix_establishment_name
CREATE INDEX ix_establishment_name ON public.establishment USING btree (name);
\echo ix_establishment_reorg_type_id
CREATE INDEX ix_establishment_reorg_type_id ON public.establishment USING btree (reorg_type_id);
\echo ix_establishment_size_id
CREATE INDEX ix_establishment_size_id ON public.establishment USING btree (unit_size_id);


\echo admin.establishment_id_exists
CREATE OR REPLACE FUNCTION admin.establishment_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.establishment WHERE id = fk_id);
$$;

\echo public.external_ident_type
CREATE TABLE public.external_ident_type (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code VARCHAR(128) UNIQUE NOT NULL,
    name VARCHAR(50),
    by_tag_id INTEGER UNIQUE REFERENCES public.tag(id) ON DELETE RESTRICT,
    description text,
    priority integer UNIQUE,
    archived boolean NOT NULL DEFAULT false
);

\echo lifecycle_callbacks.add_table('public.external_ident_type');
CALL lifecycle_callbacks.add_table('public.external_ident_type');

\echo public.external_ident_type_derive_code_and_name_from_by_tag_id()
CREATE OR REPLACE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.by_tag_id IS NOT NULL THEN
        SELECT tag.path, tag.name INTO NEW.code, NEW.name
        FROM public.tag
        WHERE tag.id = NEW.by_tag_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

\echo public.external_ident_type_derive_code_and_name_from_by_tag_id_insert
CREATE TRIGGER external_ident_type_derive_code_and_name_from_by_tag_id_insert
BEFORE INSERT ON public.external_ident_type
FOR EACH ROW
WHEN (NEW.by_tag_id IS NOT NULL)
EXECUTE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();

\echo public.external_ident_type_derive_code_and_name_from_by_tag_id_update
CREATE TRIGGER external_ident_type_derive_code_and_name_from_by_tag_id_update
BEFORE UPDATE ON public.external_ident_type
FOR EACH ROW
WHEN (NEW.by_tag_id IS NOT NULL AND NEW.by_tag_id IS DISTINCT FROM OLD.by_tag_id)
EXECUTE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();


CREATE VIEW public.external_ident_type_ordered AS
    SELECT *
    FROM public.external_ident_type
    ORDER BY priority ASC NULLS LAST, code
;

CREATE VIEW public.external_ident_type_active AS
    SELECT *
    FROM public.external_ident_type_ordered
    WHERE NOT archived
;


\echo INSERT INTO public.external_ident_type
-- Prepare the per-configured external identifiers.
INSERT INTO public.external_ident_type (code, name, priority, description) VALUES
('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.'),
('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus');


\echo public.external_ident
CREATE TABLE public.external_ident (
    id SERIAL NOT NULL,
    ident VARCHAR(50) NOT NULL,
    type_id INTEGER NOT NULL REFERENCES public.external_ident_type(id) ON DELETE RESTRICT,
    establishment_id INTEGER CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id INTEGER CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id INTEGER REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id INTEGER CHECK (admin.enterprise_group_id_exists(enterprise_group_id)),
    updated_by_user_id INTEGER NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);

CREATE UNIQUE INDEX external_ident_type_for_ident ON public.external_ident(type_id, ident);
CREATE UNIQUE INDEX external_ident_type_for_establishment ON public.external_ident(type_id, establishment_id) WHERE establishment_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_legal_unit ON public.external_ident(type_id, legal_unit_id) WHERE legal_unit_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_enterprise ON public.external_ident(type_id, enterprise_id) WHERE enterprise_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_enterprise_group ON public.external_ident(type_id, enterprise_group_id) WHERE enterprise_group_id IS NOT NULL;
CREATE INDEX external_ident_establishment_id_idx ON public.external_ident(establishment_id);
CREATE INDEX external_ident_legal_unit_id_idx ON public.external_ident(legal_unit_id);
CREATE INDEX external_ident_enterprise_id_idx ON public.external_ident(enterprise_id);
CREATE INDEX external_ident_enterprise_group_id_idx ON public.external_ident(enterprise_group_id);



CREATE TYPE public.activity_type AS ENUM ('primary', 'secondary', 'ancilliary');

\echo public.activity
CREATE TABLE public.activity (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    type public.activity_type NOT NULL,
    category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    updated_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_activity_category_id ON public.activity USING btree (category_id);
CREATE INDEX ix_activity_establishment_id ON public.activity USING btree (establishment_id);
CREATE INDEX ix_activity_legal_unit_id ON public.activity USING btree (legal_unit_id);
CREATE INDEX ix_activity_updated_by_user_id ON public.activity USING btree (updated_by_user_id);
CREATE INDEX ix_activity_establishment_valid_after_valid_to ON public.activity USING btree (establishment_id, valid_after, valid_to);

\echo public.tag_for_unit
CREATE TABLE public.tag_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tag_id integer NOT NULL REFERENCES public.tag(id) ON DELETE CASCADE,
    establishment_id integer CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer CHECK (admin.enterprise_group_id_exists(enterprise_group_id)),
    updated_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    UNIQUE (tag_id, establishment_id),
    UNIQUE (tag_id, legal_unit_id),
    UNIQUE (tag_id, enterprise_id),
    UNIQUE (tag_id, enterprise_group_id),
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);
CREATE INDEX ix_tag_for_unit_tag_id ON public.tag_for_unit USING btree (tag_id);
CREATE INDEX ix_tag_for_unit_establishment_id_id ON public.tag_for_unit USING btree (establishment_id);
CREATE INDEX ix_tag_for_unit_legal_unit_id_id ON public.tag_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_tag_for_unit_enterprise_id_id ON public.tag_for_unit USING btree (enterprise_id);
CREATE INDEX ix_tag_for_unit_enterprise_group_id_id ON public.tag_for_unit USING btree (enterprise_group_id);
CREATE INDEX ix_tag_for_unit_updated_by_user_id ON public.tag_for_unit USING btree (updated_by_user_id);

\echo public.analysis_log
CREATE TABLE public.analysis_log (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    analysis_queue_id integer NOT NULL REFERENCES public.analysis_queue(id) ON DELETE CASCADE,
    establishment_id integer check (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer check (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer check (admin.enterprise_group_id_exists(enterprise_group_id)),
    issued_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    summary_messages text,
    error_values text,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);
CREATE INDEX ix_analysis_log_analysis_queue_id_analyzed_queue_id ON public.analysis_log USING btree (analysis_queue_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_establishment_id ON public.analysis_log USING btree (establishment_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_legal_unit_id ON public.analysis_log USING btree (legal_unit_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_id ON public.analysis_log USING btree (enterprise_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_group_id ON public.analysis_log USING btree (enterprise_group_id);


CREATE TYPE public.person_sex AS ENUM ('Male', 'Female');
\echo public.person
CREATE TABLE public.person (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    personal_ident text UNIQUE,
    country_id integer REFERENCES public.country(id),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    given_name character varying(150),
    middle_name character varying(150),
    family_name character varying(150),
    birth_date date,
    sex public.person_sex,
    phone_number_1 text,
    phone_number_2 text,
    address text
);
CREATE INDEX ix_person_country_id ON public.person USING btree (country_id);
CREATE INDEX ix_person_given_name_surname ON public.person USING btree (given_name, middle_name, family_name);

\echo public.person_type
CREATE TABLE public.person_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);

\echo public.person_for_unit
CREATE TABLE public.person_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    person_id integer NOT NULL REFERENCES public.person(id) ON DELETE CASCADE,
    person_type_id integer REFERENCES public.person_type(id),
    establishment_id integer check (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer check (admin.legal_unit_id_exists(legal_unit_id)),
    CONSTRAINT "One and only one of establishment_id legal_unit_id  must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_person_for_unit_legal_unit_id ON public.person_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_person_for_unit_establishment_id ON public.person_for_unit USING btree (establishment_id);
CREATE INDEX ix_person_for_unit_person_id ON public.person_for_unit USING btree (person_id);
CREATE UNIQUE INDEX ix_person_for_unit_person_type_id_establishment_id_legal_unit_id_ ON public.person_for_unit USING btree (person_type_id, establishment_id, legal_unit_id, person_id);


\echo public.postal_index
CREATE TABLE public.postal_index (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
);

\echo public.region
CREATE TABLE public.region (
    id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer REFERENCES public.region(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    center_latitude numeric(9, 6),
    center_longitude numeric(9, 6),
    center_altitude numeric(6, 1),
    CONSTRAINT "parent_id is required for child"
      CHECK(public.nlevel(path) = 1 OR parent_id IS NOT NULL),
    CONSTRAINT "center coordinates all or nothing"
      CHECK((center_latitude IS NOT NULL AND center_longitude IS NOT NULL)
         OR (center_latitude IS NULL     AND center_longitude IS NULL)),
    CONSTRAINT "altitude requires coordinates"
      CHECK(CASE
                WHEN center_altitude IS NOT NULL THEN
                    (center_latitude IS NOT NULL AND center_longitude IS NOT NULL)
                ELSE
                    TRUE
            END)
);

CREATE INDEX ix_region_parent_id ON public.region USING btree (parent_id);
CREATE TYPE public.location_type AS ENUM ('physical', 'postal');

\echo public.location
CREATE TABLE public.location (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    type public.location_type NOT NULL,
    address_part1 character varying(200),
    address_part2 character varying(200),
    address_part3 character varying(200),
    postal_code character varying(200),
    postal_place character varying(200),
    region_id integer REFERENCES public.region(id) ON DELETE RESTRICT,
    country_id integer NOT NULL REFERENCES public.country(id) ON DELETE RESTRICT,
    latitude numeric(9, 6),
    longitude numeric(9, 6),
    altitude numeric(6, 1),
    establishment_id integer,
    legal_unit_id integer,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    updated_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE RESTRICT,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL),
    CONSTRAINT "coordinates require both latitude and longitude"
      CHECK((latitude IS NOT NULL AND longitude IS NOT NULL)
         OR (latitude IS NULL AND longitude IS NULL)),
    CONSTRAINT "altitude requires coordinates"
      CHECK(CASE
                WHEN altitude IS NOT NULL THEN
                    (latitude IS NOT NULL AND longitude IS NOT NULL)
                ELSE
                    TRUE
            END)
);
CREATE INDEX ix_address_region_id ON public.location USING btree (region_id);
CREATE INDEX ix_location_establishment_id_id ON public.location USING btree (establishment_id);
CREATE INDEX ix_location_legal_unit_id_id ON public.location USING btree (legal_unit_id);
CREATE INDEX ix_location_updated_by_user_id ON public.location USING btree (updated_by_user_id);


-- Create a view for region upload using path and name
\echo public.region_upload
CREATE VIEW public.region_upload
WITH (security_invoker=on) AS
SELECT path, name, center_latitude, center_longitude, center_altitude
FROM public.region
ORDER BY path;
COMMENT ON VIEW public.region_upload IS 'Upload of region by path,name that automatically connects parent_id';

\echo admin.region_upload_upsert
CREATE FUNCTION admin.region_upload_upsert()
RETURNS TRIGGER AS $$
DECLARE
    maybe_parent_id int := NULL;
    row RECORD;
BEGIN
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.region
         WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1);

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    INSERT INTO public.region (path, parent_id, name, center_latitude, center_longitude, center_altitude)
    VALUES (NEW.path, maybe_parent_id, NEW.name, NEW.center_latitude, NEW.center_longitude, NEW.center_altitude)
    ON CONFLICT (path)
    DO UPDATE SET
        parent_id = maybe_parent_id,
        name = EXCLUDED.name,
        center_latitude = EXCLUDED.center_latitude,
        center_longitude = EXCLUDED.center_longitude,
        center_altitude = EXCLUDED.center_altitude
    WHERE region.id = EXCLUDED.id
    RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for the view
CREATE TRIGGER region_upload_upsert
INSTEAD OF INSERT ON public.region_upload
FOR EACH ROW
EXECUTE FUNCTION admin.region_upload_upsert();


\echo admin.upsert_region_7_levels
CREATE FUNCTION admin.upsert_region_7_levels()
RETURNS TRIGGER AS $$
BEGIN
    WITH source AS (
        SELECT NEW."Regional Code"::ltree AS path, NEW."Regional Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree AS path, NEW."District Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code" AS path, NEW."County Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code" AS path, NEW."Constituency Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code" AS path, NEW."Subcounty Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code" AS path, NEW."Parish Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code"||NEW."Village Code" AS path, NEW."Village Name" AS name
    )
    INSERT INTO public.region_view(path, name)
    SELECT path,name FROM source;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for region
\echo public.region_7_levels_view
CREATE VIEW public.region_7_levels_view
WITH (security_invoker=on) AS
SELECT '' AS "Regional Code"
     , '' AS "Regional Name"
     , '' AS "District Code"
     , '' AS "District Name"
     , '' AS "County Code"
     , '' AS "County Name"
     , '' AS "Constituency Code"
     , '' AS "Constituency Name"
     , '' AS "Subcounty Code"
     , '' AS "Subcounty Name"
     , '' AS "Parish Code"
     , '' AS "Parish Name"
     , '' AS "Village Code"
     , '' AS "Village Name"
     ;

-- Create triggers for the view
CREATE TRIGGER upsert_region_7_levels_view
INSTEAD OF INSERT ON public.region_7_levels_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_region_7_levels();


\echo public.report_tree
CREATE TABLE public.report_tree (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text,
    type text,
    report_id integer,
    parent_node_id integer,
    archived boolean NOT NULL DEFAULT false,
    resource_group text,
    report_url text
);

\echo public.sample_frame
CREATE TABLE public.sample_frame (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    description text,
    predicate text NOT NULL,
    fields text NOT NULL,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    status integer NOT NULL,
    file_path text,
    generated_date_time timestamp with time zone,
    creation_date timestamp with time zone NOT NULL,
    editing_date timestamp with time zone
);
CREATE INDEX ix_sample_frame_user_id ON public.sample_frame USING btree (user_id);


-- Create function for upsert operation on country
\echo admin.upsert_country
CREATE FUNCTION admin.upsert_country()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.country (iso_2, iso_3, iso_num, name, active, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2, iso_3, iso_num, name)
    DO UPDATE SET
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp()
    WHERE country.id = EXCLUDED.id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create function for deleting stale countries
\echo admin.delete_stale_country
CREATE FUNCTION admin.delete_stale_country()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM public.country
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for country
\echo public.country_view
CREATE VIEW public.country_view
WITH (security_invoker=on) AS
SELECT id, iso_2, iso_3, iso_num, name, active, custom
FROM public.country;

-- Create triggers for the view
CREATE TRIGGER upsert_country_view
INSTEAD OF INSERT ON public.country_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_country();

CREATE TRIGGER delete_stale_country_view
AFTER INSERT ON public.country_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_country();


\copy public.country_view(name, iso_2, iso_3, iso_num) FROM 'dbseed/country/country_codes.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


-- Helpers to generate views for bach API handling of all the system provided configuration
-- that can also be overridden.
CREATE TYPE admin.view_type_enum AS ENUM ('ordered', 'available', 'system', 'custom');
CREATE TYPE admin.batch_api_table_properties AS (
    has_priority boolean,
    has_active boolean,
    has_archived boolean,
    has_path boolean,
    has_code boolean,
    has_custom boolean,
    has_description boolean,
    schema_name text,
    table_name text
);

\echo admin.generate_view
CREATE FUNCTION admin.generate_view(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regclass AS $generate_view$
DECLARE
    view_sql text;
    view_name_str text;
    view_name regclass;
    from_str text;
    where_clause_str text := '';
    order_clause_str text := '';
    columns text[] := ARRAY[]::text[];
    columns_str text;
BEGIN
    -- Construct the view name
    view_name_str := table_properties.table_name || '_' || view_type::text;

    -- Determine where clause and ordering logic based on view type and table properties
    CASE view_type
    WHEN 'ordered' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name);
        IF table_properties.has_priority AND table_properties.has_code THEN
            order_clause_str := 'ORDER BY priority ASC NULLS LAST, code ASC';
        ELSIF table_properties.has_path THEN
            order_clause_str := 'ORDER BY path ASC';
        ELSIF table_properties.has_code THEN
            order_clause_str := 'ORDER BY code ASC';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'available' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_ordered');
        IF table_properties.has_active THEN
            where_clause_str := 'WHERE active';
        ELSIF table_properties.has_archived THEN
            where_clause_str := 'WHERE NOT archived';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'system' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
        where_clause_str := 'WHERE custom = false';
    WHEN 'custom' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
        where_clause_str := 'WHERE custom = true';
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END CASE;


    IF columns_str IS NULL THEN
      -- Add relevant columns based on table properties
      IF table_properties.has_path THEN
          columns := array_append(columns, 'path');
      ELSEIF table_properties.has_code THEN
          columns := array_append(columns, 'code');
      END IF;

      -- Always include 'name'
      columns := array_append(columns, 'name');

      IF table_properties.has_priority THEN
          columns := array_append(columns, 'priority');
      END IF;

      IF table_properties.has_description THEN
          columns := array_append(columns, 'description');
      END IF;

      -- Combine columns into a comma-separated string for SQL query
      columns_str := array_to_string(columns, ', ');
    END IF;

    -- Construct the SQL statement for the view
    view_sql := format($view$
CREATE VIEW public.%1$I WITH (security_invoker=on) AS
SELECT %2$s
FROM %3$s
%4$s
%5$s
$view$
    , view_name_str                -- %1$
    , columns_str                  -- %2$
    , from_str                     -- %3$
    , where_clause_str             -- %4$
    , order_clause_str             -- %5$
    );

    EXECUTE view_sql;

    view_name := format('public.%I', view_name_str)::regclass;
    RAISE NOTICE 'Created view: %', view_name;

    RETURN view_name;
END;
$generate_view$ LANGUAGE plpgsql;


CREATE FUNCTION admin.get_unique_columns(
    table_properties admin.batch_api_table_properties)
RETURNS text[] LANGUAGE plpgsql AS $get_unique_columns$
DECLARE
    unique_columns text[] := ARRAY[]::text[];
BEGIN
    IF table_properties.has_active THEN
        unique_columns := array_append(unique_columns, 'active');
    ELSEIF table_properties.has_archived THEN
        unique_columns := array_append(unique_columns, 'archived');
    END IF;

    IF table_properties.has_path THEN
        unique_columns := array_append(unique_columns, 'path');
    ELSEIF table_properties.has_code THEN
        unique_columns := array_append(unique_columns, 'code');
    END IF;

    RETURN unique_columns;
END;
$get_unique_columns$;


\echo admin.generate_active_code_custom_unique_constraint
CREATE FUNCTION admin.generate_active_code_custom_unique_constraint(
    table_properties admin.batch_api_table_properties)
RETURNS VOID LANGUAGE plpgsql AS $generate_active_code_custom_unique_constraint$
DECLARE
    constraint_sql text;
    unique_columns text[];
    index_name text;
BEGIN
    -- Get the unique columns based on table properties
    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct index name by joining columns with underscores
    index_name := 'ix_' || table_properties.table_name || '_' || array_to_string(unique_columns, '_');

    -- Ensure there are columns to create a constraint for
    IF array_length(unique_columns, 1) IS NOT NULL THEN
        -- Create a unique index for the determined unique columns
        constraint_sql := format($$
CREATE UNIQUE INDEX %I ON public.%I USING btree (%s);
$$, index_name, table_properties.table_name, array_to_string(unique_columns, ', '));

        EXECUTE constraint_sql;
        RAISE NOTICE 'Created unique constraint on (%) for table %', array_to_string(unique_columns, ', '), table_properties.table_name;
    END IF;
END;
$generate_active_code_custom_unique_constraint$;


\echo admin.generate_code_upsert_function
CREATE FUNCTION admin.generate_code_upsert_function(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regprocedure LANGUAGE plpgsql AS $generate_code_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    content_columns text := 'name';
    content_values text := 'NEW.name';
    content_update_sets text := 'name = NEW.name';
    unique_columns text[];
BEGIN
    -- Utilize has_description from table_properties
    IF table_properties.has_description THEN
        content_columns := content_columns || ', description';
        content_values := content_values || ', NEW.description';
        content_update_sets := content_update_sets || ', description = NEW.description';
    END IF;

    IF table_properties.has_active THEN
        content_columns := content_columns || ', active';
        content_values := content_values || ', TRUE';
        content_update_sets := content_update_sets || ', active = TRUE';
    END IF;

    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct the SQL statement for the upsert function
function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO %3$I.%4$I (code, %5$s, custom, updated_at)
    VALUES (NEW.code, %6$s, %7$L, statement_timestamp())
    ON CONFLICT (%9$s) DO UPDATE SET
        %8$s,
        custom = %7$L,
        updated_at = statement_timestamp()
    WHERE %4$I.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %%', to_json(row);

    RETURN NULL;
END;
$body$;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, table_properties.schema_name -- %3$: Schema name for the table
, table_properties.table_name  -- %4$: Table name
, content_columns              -- %5$: Columns to be inserted/updated
, content_values               -- %6$: Values to be inserted
, custom_value                 -- %7$: Boolean indicating system or custom
, content_update_sets          -- %8$: SET clause for the ON CONFLICT update
, array_to_string(unique_columns, ', ') -- %9$: columns to use for conflict detection/resolution
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created code-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_code_upsert_function$;


\echo admin.generate_path_upsert_function
CREATE FUNCTION admin.generate_path_upsert_function(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regprocedure AS $generate_path_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    unique_columns text[];
BEGIN
    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- Get unique columns using admin.get_unique_columns
    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct the SQL statement for the upsert function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER AS $body$
BEGIN
    WITH parent AS (
        SELECT id
        FROM %3$I.%4$I
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO %3$I.%4$I (path, parent_id, name, active, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, %5$L, %6$L, statement_timestamp())
    ON CONFLICT (%7$s) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = %6$L,
        updated_at = statement_timestamp()
    WHERE %4$I.id = EXCLUDED.id;
    RETURN NULL;
END;
$body$ LANGUAGE plpgsql;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, schema_name_str              -- %3$: Schema name for the target table
, table_name_str               -- %4$: Table name
, not custom_value             -- %5$: Boolean indicating system or custom (inverted for INSERT)
, custom_value                 -- %6$: Value for custom in the INSERT and ON CONFLICT update
, array_to_string(unique_columns, ', ') -- %7$: Unique columns for ON CONFLICT
);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created path-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_path_upsert_function$ LANGUAGE plpgsql;




\echo admin.generate_prepare_function_for_custom
CREATE FUNCTION admin.generate_prepare_function_for_custom(
  table_properties admin.batch_api_table_properties
)
RETURNS regprocedure LANGUAGE plpgsql AS $generate_prepare_function_for_custom$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
BEGIN
    function_name_str := 'prepare_' || table_properties.table_name || '_custom';

    -- Construct the SQL statement for the delete function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE %3$I.%4$I
       SET active = false
     WHERE active = true
       AND custom = false;

    RETURN NULL;
END;
$body$;
$function$
, function_schema   -- %1$
, function_name_str -- %2$
, table_properties.schema_name -- %3$
, table_properties.table_name -- %4$
, custom_value      -- %5$
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created prepare function: %', function_name;

    RETURN function_name;
END;
$generate_prepare_function_for_custom$;



\echo admin.generate_view_triggers
CREATE FUNCTION admin.generate_view_triggers(view_name regclass, upsert_function_name regprocedure, prepare_function_name regprocedure)
RETURNS text[] AS $generate_triggers$
DECLARE
    view_name_str text;
    upsert_trigger_sql text;
    prepare_trigger_sql text;
    upsert_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    upsert_trigger_name text;
    prepare_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    prepare_trigger_name text := NULL;
BEGIN
    -- Lookup view_name_str
    SELECT relname INTO view_name_str
    FROM pg_catalog.pg_class
    WHERE oid = view_name;

    upsert_trigger_name_str := 'upsert_' || view_name_str;
    prepare_trigger_name_str := 'prepare_' || view_name_str;

    -- Construct the SQL statement for the upsert trigger
    upsert_trigger_sql := format($$CREATE TRIGGER %I
                                  INSTEAD OF INSERT ON %s
                                  FOR EACH ROW
                                  EXECUTE FUNCTION %s;$$,
                                  upsert_trigger_name_str, view_name::text, upsert_function_name::text);
    EXECUTE upsert_trigger_sql;
    upsert_trigger_name := format('public.%I',upsert_trigger_name_str);
    RAISE NOTICE 'Created upsert trigger: %', upsert_trigger_name;

    IF prepare_function_name IS NOT NULL THEN
      -- Construct the SQL statement for the delete trigger
      prepare_trigger_sql := format($$CREATE TRIGGER %I
                                    BEFORE INSERT ON %s
                                    FOR EACH STATEMENT
                                    EXECUTE FUNCTION %s;$$,
                                    prepare_trigger_name_str, view_name::text, prepare_function_name::text);
      -- Log and execute
      EXECUTE prepare_trigger_sql;
      prepare_trigger_name := format('public.%I',prepare_trigger_name_str);

      RAISE NOTICE 'Created prepare trigger: %', prepare_trigger_name;
    END IF;

    -- Return the regclass identifiers of the created triggers
    RETURN ARRAY[upsert_trigger_name, prepare_trigger_name];
END;
$generate_triggers$ LANGUAGE plpgsql;


CREATE FUNCTION admin.detect_batch_api_table_properties(table_name regclass)
RETURNS admin.batch_api_table_properties AS $$
DECLARE
    result admin.batch_api_table_properties;
BEGIN
    -- Initialize the result with default values
    result.has_priority := false;
    result.has_active := false;
    result.has_archived := false;
    result.has_path := false;
    result.has_code := false;
    result.has_custom := false;
    result.has_description := false;
    result.schema_name := '';
    result.table_name := '';

    -- Populate schema_name and table_name
    SELECT n.nspname, c.relname
    INTO result.schema_name, result.table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Check if specific columns exist
    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'priority' AND NOT attisdropped;
    IF FOUND THEN
        result.has_priority := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'active' AND NOT attisdropped;
    IF FOUND THEN
        result.has_active := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'archived' AND NOT attisdropped;
    IF FOUND THEN
        result.has_archived := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'path' AND NOT attisdropped;
    IF FOUND THEN
        result.has_path := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'code' AND NOT attisdropped;
    IF FOUND THEN
        result.has_code := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'custom' AND NOT attisdropped;
    IF FOUND THEN
        result.has_custom := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'description' AND NOT attisdropped;
    IF FOUND THEN
        result.has_description := true;
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql;


\echo admin.generate_table_views_for_batch_api
CREATE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    table_properties admin.batch_api_table_properties;
    view_name_ordered regclass;
    view_name_available regclass;
    view_name_system regclass;
    view_name_custom regclass;
    upsert_function_name_system regprocedure;
    upsert_function_name_custom regprocedure;
    prepare_function_name_custom regprocedure;
    triggers_name_system text[];
    triggers_name_custom text[];
BEGIN
    table_properties := admin.detect_batch_api_table_properties(table_name);

    view_name_ordered := admin.generate_view(table_properties, 'ordered');
    view_name_available := admin.generate_view(table_properties, 'available');
    view_name_system := admin.generate_view(table_properties, 'system');
    view_name_custom := admin.generate_view(table_properties, 'custom');

    PERFORM admin.generate_active_code_custom_unique_constraint(table_properties);

    -- Determine the upsert function names based on table properties
    IF table_properties.has_path THEN
        upsert_function_name_system := admin.generate_path_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_path_upsert_function(table_properties, 'custom');
    ELSIF table_properties.has_code THEN
        upsert_function_name_system := admin.generate_code_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_code_upsert_function(table_properties, 'custom');
    ELSE
        RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
    END IF;

    -- Generate prepare functions
    prepare_function_name_custom := admin.generate_prepare_function_for_custom(table_properties);

    -- Generate view triggers
    triggers_name_system := admin.generate_view_triggers(view_name_system, upsert_function_name_system, NULL);
    triggers_name_custom := admin.generate_view_triggers(view_name_custom, upsert_function_name_custom, prepare_function_name_custom);
END;
$$ LANGUAGE plpgsql;



\echo admin.drop_table_views_for_batch_api
CREATE OR REPLACE FUNCTION admin.drop_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    view_name_ordered text;
    view_name_available text;
    view_name_system text;
    view_name_custom text;
    upsert_function_name_system text;
    upsert_function_name_custom text;
    prepare_function_name_custom text;
BEGIN
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view and function names
    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_available := schema_name_str || '.' || table_name_str || '_available';
    view_name_ordered := schema_name_str || '.' || table_name_str || '_ordered';

    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';

    prepare_function_name_custom := 'admin.prepare_' || table_name_str || '_custom';

    -- Drop views
    EXECUTE 'DROP VIEW ' || view_name_custom;
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_available;
    EXECUTE 'DROP VIEW ' || view_name_ordered;

    -- Drop functions
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_custom || '()';

    EXECUTE 'DROP FUNCTION ' || prepare_function_name_custom || '()';
END;
$$ LANGUAGE plpgsql;


\echo public.region_role
CREATE TABLE public.region_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
    region_id integer NOT NULL REFERENCES public.region(id) ON DELETE CASCADE,
    UNIQUE(role_id, region_id)
);
CREATE INDEX ix_region_role ON public.region_role USING btree (region_id);


CREATE TYPE public.stat_type AS ENUM(
  'int',
  'float',
  'string',
  'bool'
);
--
CREATE TYPE public.stat_frequency AS ENUM(
  'daily',
  'weekly',
  'biweekly',
  'monthly',
  'bimonthly',
  'quarterly',
  'semesterly',
  'yearly'
);
--
\echo public.stat_definition
CREATE TABLE public.stat_definition(
  id serial PRIMARY KEY,
  code varchar NOT NULL UNIQUE,
  type public.stat_type NOT NULL,
  frequency public.stat_frequency NOT NULL,
  name varchar NOT NULL,
  description text,
  priority integer UNIQUE,
  archived boolean NOT NULL DEFAULT false
);
--
COMMENT ON COLUMN public.stat_definition.priority IS 'UI ordering of the entry fields';
COMMENT ON COLUMN public.stat_definition.archived IS 'At the time of data entry, only non archived codes can be used.';
--
CREATE VIEW public.stat_definition_ordered AS
    SELECT *
    FROM public.stat_definition
    ORDER BY priority ASC NULLS LAST, code
;

CREATE VIEW public.stat_definition_active AS
    SELECT *
    FROM public.stat_definition_ordered
    WHERE NOT archived
;
--
\echo lifecycle_callbacks.add_table('public.stat_definition');
CALL lifecycle_callbacks.add_table('public.stat_definition');
--
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('employees','int','yearly','Number of people employed','The number of people receiving an official salary with government reporting.',1),
  ('turnover','int','yearly','Turnover','The amount (EUR)',2);

\echo public.stat_for_unit
CREATE TABLE public.stat_for_unit (
    id SERIAL NOT NULL,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE RESTRICT,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    value_int INTEGER,
    value_float FLOAT,
    value_string VARCHAR,
    value_bool BOOLEAN,
    CHECK(
        (value_int IS NOT NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS NOT NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS NOT NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS NOT NULL)
    )
);


\echo admin.check_stat_for_unit_values
CREATE OR REPLACE FUNCTION admin.check_stat_for_unit_values()
RETURNS trigger AS $$
DECLARE
  new_type public.stat_type;
BEGIN
  -- Fetch the type for the current stat_definition_id
  SELECT type INTO new_type
  FROM public.stat_definition
  WHERE id = NEW.stat_definition_id;

  -- Use CASE statement to simplify the logic
  CASE new_type
    WHEN 'int' THEN
      IF NEW.value_int IS NULL OR NEW.value_float IS NOT NULL OR NEW.value_string IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'float' THEN
      IF NEW.value_float IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_string IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'string' THEN
      IF NEW.value_string IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'bool' THEN
      IF NEW.value_bool IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_string IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    ELSE
      RAISE EXCEPTION 'Unknown type: %', new_type;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_stat_for_unit_values_trigger
BEFORE INSERT OR UPDATE ON public.stat_for_unit
FOR EACH ROW EXECUTE FUNCTION admin.check_stat_for_unit_values();


\echo admin.prevent_id_update
CREATE OR REPLACE FUNCTION admin.prevent_id_update()
  RETURNS TRIGGER
  AS $$
BEGIN
  IF NEW.id <> OLD.id THEN
    RAISE EXCEPTION 'Update of id column in legal_unit table is not allowed!';
  END IF;
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;


\echo admin.prevent_id_update_on_public_tables
CREATE OR REPLACE FUNCTION admin.prevent_id_update_on_public_tables()
RETURNS void AS $$
DECLARE
    table_regclass regclass;
    schema_name_str text;
    table_name_str text;
BEGIN
    FOR table_regclass, schema_name_str, table_name_str IN
        SELECT c.oid::regclass, n.nspname, c.relname
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
    LOOP
        RAISE NOTICE '%.%: Preventing id changes', schema_name_str, table_name_str;
        EXECUTE format('CREATE TRIGGER trigger_prevent_'||table_name_str||'_id_update BEFORE UPDATE OF id ON '||schema_name_str||'.'||table_name_str||' FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update();');
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.prevent_id_update_on_public_tables();
SET LOCAL client_min_messages TO INFO;


\echo public.set_primary_legal_unit_for_enterprise
-- Functions to manage connections between enterprise <-> legal_unit <-> establishment
CREATE OR REPLACE FUNCTION public.set_primary_legal_unit_for_enterprise(
    legal_unit_id integer,
    valid_from_param date DEFAULT current_date,
    valid_to_param date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    legal_unit_row public.legal_unit;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT lu.* INTO legal_unit_row
    FROM public.legal_unit AS lu
    WHERE lu.id = legal_unit_id
      AND daterange(lu.valid_from, lu.valid_to, '[]')
       && daterange(valid_from_param, valid_to_param, '[]');
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal unit does not exist.';
    END IF;

    IF legal_unit_row.primary_for_enterprise THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the legal unit is already primary.',
          'enterprise_id', legal_unit_row.enterprise_id,
          'legal_unit_id', legal_unit_row.id
      );
    END IF;

    -- Unset all legal units of the enterprise from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = false
        WHERE primary_for_enterprise
          AND enterprise_id = legal_unit_row.enterprise_id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'legal_unit', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified legal unit as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = true
        WHERE id = legal_unit_row.id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_build_object('table', 'legal_unit', 'id', id) INTO v_set_id FROM updated_row;

    -- Return a jsonb summary of changes including table and ids of changed legal units
    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$$;

\echo public.set_primary_establishment_for_legal_unit
CREATE OR REPLACE FUNCTION public.set_primary_establishment_for_legal_unit(
    establishment_id integer,
    valid_from_param date DEFAULT current_date,
    valid_to_param date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    establishment_row public.establishment;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT * INTO establishment_row
      FROM public.establishment
     WHERE id = establishment_id
       AND daterange(valid_from, valid_to, '[]')
        && daterange(valid_from_param, valid_to_param, '[]');
     IF NOT FOUND THEN
        RAISE EXCEPTION 'Establishment does not exist or is not linked to a legal unit.';
    END IF;

    IF establishment_row.primary_for_legal_unit THEN
      RETURN jsonb_build_object(
          'message', 'No changes made as the establishment is already primary.',
          'legal_unit_id', establishment_row.legal_unit_id,
          'establishment_id', establishment_row.id
      );
    END IF;

    -- Unset all establishments of the legal unit from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = false
        WHERE primary_for_legal_unit
          AND legal_unit_id = establishment_row.legal_unit_id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'establishment', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified establishment as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = true
        WHERE id = establishment_row.id
          AND daterange(valid_from, valid_to, '[]')
           && daterange(valid_from_param, valid_to_param, '[]')
        RETURNING id
    )
    SELECT jsonb_build_object('table', 'establishment', 'id', id) INTO v_set_id FROM updated_row;

    -- Return a jsonb summary of changes including table and ids of changed establishments
    RETURN jsonb_build_object(
        'unset_primary', v_unset_ids,
        'set_primary', v_set_id
    );
END;
$$;


CREATE FUNCTION public.connect_legal_unit_to_enterprise(
    legal_unit_id integer,
    enterprise_id integer,
    valid_from date DEFAULT current_date,
    valid_to date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
#variable_conflict use_variable
DECLARE
    old_enterprise_id integer;
    updated_legal_unit_ids integer[];
    deleted_enterprise_id integer := NULL;
    is_primary BOOLEAN;
    other_legal_units_count INTEGER;
    new_primary_legal_unit_id INTEGER;
BEGIN
    -- Check if the enterprise exists
    IF NOT EXISTS(SELECT 1 FROM public.enterprise WHERE id = enterprise_id) THEN
        RAISE EXCEPTION 'Enterprise does not exist.';
    END IF;

    -- Retrieve current enterprise_id and if it's primary
    SELECT lu.enterprise_id, lu.primary_for_enterprise INTO old_enterprise_id, is_primary
    FROM public.legal_unit AS lu
    WHERE lu.id = legal_unit_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal Unit does not exist.';
    END IF;

    -- Idempotency check: If the legal unit is already connected to the given enterprise with the same parameters, do nothing.
    IF old_enterprise_id = enterprise_id THEN
        RETURN jsonb_build_object(
            'message', 'No changes made as the legal unit is already connected to the specified enterprise.',
            'legal_unit_id', legal_unit_id,
            'enterprise_id', enterprise_id
        );
    END IF;

    -- Check if there are other legal units and if none of them are primary
    IF is_primary THEN
        SELECT COUNT(*) INTO other_legal_units_count
        FROM public.legal_unit
        WHERE enterprise_id = old_enterprise_id
          AND id <> legal_unit_id;

        -- If there is only one other legal unit, set it to primary.
        IF other_legal_units_count = 1 THEN
            SELECT id INTO new_primary_legal_unit_id
            FROM public.legal_unit
            WHERE enterprise_id = old_enterprise_id
              AND id <> legal_unit_id;

            UPDATE public.legal_unit
            SET primary_for_enterprise = true
            WHERE id = new_primary_legal_unit_id;
        ELSIF other_legal_units_count > 1 THEN
            RAISE EXCEPTION 'Assign another primary legal_unit to existing enterprise first';
        END IF;
    END IF;

    -- Connect the legal unit to the enterprise and track the updated id
    WITH updated AS (
        UPDATE public.legal_unit AS lu
        SET enterprise_id = enterprise_id
          , primary_for_enterprise = false
        WHERE lu.id = legal_unit_id
        RETURNING lu.id
    )
    SELECT array_agg(id) INTO updated_legal_unit_ids FROM updated;

    -- Remove possibly stale enterprise and capture its id if deleted
    WITH deleted AS (
        DELETE FROM public.enterprise AS en
        WHERE en.id = old_enterprise_id
        AND NOT EXISTS(
            SELECT 1
            FROM public.legal_unit AS lu
            WHERE lu.enterprise_id = old_enterprise_id
        )
        RETURNING id
    )
    SELECT id INTO deleted_enterprise_id FROM deleted;

    -- Return a jsonb summary of changes including the updated legal unit ids, old and new enterprise_ids, and deleted enterprise id if applicable
    RETURN jsonb_build_object(
        'updated_legal_unit_ids', updated_legal_unit_ids,
        'old_enterprise_id', old_enterprise_id,
        'new_enterprise_id', enterprise_id,
        'deleted_enterprise_id', deleted_enterprise_id
    );
END;
$$;


-- TODO: Create a view to see an establishment with statistics
-- TODO: allow upsert on statistics view according to stat_definition

---- Example dynamic generation of view for each active stat_definition
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view()
-- RETURNS VOID LANGUAGE plpgsql AS $$
-- DECLARE
--     dyn_query TEXT;
--     stat_code RECORD;
-- BEGIN
--     -- Start building the dynamic query
--     dyn_query := 'CREATE OR REPLACE VIEW legal_unit_history_with_stats AS SELECT id, unit_ident, name, edit_comment, valid_from, valid_to';
--
--     -- For each code in stat_definition, add it as a column
--     FOR stat_code IN (SELECT code FROM stat_definition WHERE archived = false ORDER BY priority)
--     LOOP
--         dyn_query := dyn_query || ', stats ->> ''' || stat_code.code || ''' AS "' || stat_code.code || '"';
--     END LOOP;
--
--     dyn_query := dyn_query || ' FROM legal_unit_history';
--
--     -- Execute the dynamic query
--     EXECUTE dyn_query;
--     -- Reload PostgREST to expose the new view
--     NOTIFY pgrst, 'reload config';
-- END;
-- $$;
-- --
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view_trigger()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     -- Call the view generation function
--     PERFORM generate_legal_unit_history_with_stats_view();
--
--     -- As this is an AFTER trigger, we don't need to return any specific row.
--     RETURN NULL;
-- END;
-- $$;
-- --
-- CREATE TRIGGER regenerate_stats_view_trigger
-- AFTER INSERT OR UPDATE OR DELETE ON stat_definition
-- FOR EACH ROW
-- EXECUTE FUNCTION generate_legal_unit_history_with_stats_view_trigger();
-- --
-- SELECT generate_legal_unit_history_with_stats_view();



-- TODO: Use pg_audit.

CREATE TYPE public.statistical_unit_type AS ENUM('establishment','legal_unit','enterprise','enterprise_group');


\echo public.timepoints
CREATE VIEW public.timepoints AS
    WITH es AS (
        -- establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , id AS unit_id
             , valid_after
             , valid_to
         FROM public.establishment
        UNION
        -- activity -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , a.establishment_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE a.establishment_id IS NOT NULL
        UNION
        -- location -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , l.establishment_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.establishment AS es
            ON l.establishment_id = es.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE l.establishment_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , sfu.establishment_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE sfu.establishment_id IS NOT NULL
    ), lu AS (
        -- legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , id AS unit_id
             , valid_after
             , valid_to
         FROM public.legal_unit
        UNION
        -- activity -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , a.legal_unit_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.legal_unit AS lu
            ON a.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE a.legal_unit_id IS NOT NULL
        UNION
        -- location -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , l.legal_unit_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.legal_unit AS lu
            ON l.legal_unit_id = lu.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE l.legal_unit_id IS NOT NULL
        UNION
        -- stat_for_unit -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , sfu.legal_unit_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.legal_unit AS lu
            ON sfu.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE sfu.legal_unit_id IS NOT NULL
        UNION
        -- establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , lu.id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(es.valid_after, es.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
        UNION
        -- activity -> establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , es.legal_unit_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , lu.id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
    ), en AS (
        -- legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , enterprise_id AS unit_id
             , valid_after
             , valid_to
         FROM public.legal_unit
        UNION
        -- establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(es.valid_after, es.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- activity -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- activity -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.legal_unit AS lu
            ON a.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- activity -> establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- location -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.establishment AS es
            ON l.establishment_id = es.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- location -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.legal_unit AS lu
            ON l.legal_unit_id = lu.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
           AND lu.primary_for_enterprise
        UNION
        -- stat_for_unit -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- stat_for_unit -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.legal_unit AS lu
            ON sfu.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
    ), base AS (
          SELECT * FROM es
          UNION ALL
          SELECT * FROM lu
          UNION ALL
          SELECT * FROM en
    ), timepoint AS (
          SELECT unit_type, unit_id, valid_after AS timepoint FROM base
            UNION
          SELECT unit_type, unit_id, valid_to AS timepoint FROM base
    )
    SELECT *
    FROM timepoint
    ORDER BY unit_type, unit_id, timepoint
;

--SELECT * FROM public.timepoints;

\echo public.timesegments
CREATE VIEW public.timesegments AS
  WITH timesegments_with_trailing_point AS (
      SELECT
          unit_type,
          unit_id,
          timepoint AS valid_after,
          LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS valid_to
      FROM public.timepoints
  )
  -- Remove the last lonely started but unfinished segment.
  SELECT *
  FROM timesegments_with_trailing_point
  WHERE valid_to IS NOT NULL
  ORDER BY unit_type, unit_id, valid_after
;

--SELECT * FROM public.timesegments;

\echo public.jsonb_stats_to_summary
/*
 * ======================================================================================
 * Function: jsonb_stats_to_summary
 * Purpose: Aggregates and summarizes JSONB data by computing statistics for various data types.
 *
 * This function accumulates statistics for JSONB objects, including numeric, string, boolean,
 * array, and nested object types. The function is used as the state transition function in
 * the jsonb_stats_to_summary_agg aggregate, summarizing data across multiple rows.
 *
 * Summary by Type:
 * 1. Numeric:
 *    - Computes the sum, count, mean, maximum, minimum, variance, standard deviation (via sum_sq_diff),
 *      and coefficient of variation.
 *    - Example:
 *      Input: {"a": 10}, {"a": 5}, {"a": 20}
 *      Output: {"a": {"sum": 35, "count": 3, "mean": 11.67, "max": 20, "min": 5, "variance": 58.33, "stddev": 7.64,
 *                    "coefficient_of_variation_pct": 65.47}}
 *    - Calculation References:
 *      - Mean update: https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
 *      - Variance and standard deviation update: Welford's method
 *      - Coefficient of Variation (CV): Standard deviation divided by mean.
 *
 * 2. String:
 *    - Counts occurrences of each distinct string value.
 *    - Example:
 *      Input: {"b": "apple"}, {"b": "banana"}, {"b": "apple"}
 *      Output: {"b": {"counts": {"apple": 2, "banana": 1}}}
 *
 * 3. Boolean:
 *    - Counts the occurrences of true and false values.
 *    - Example:
 *      Input: {"c": true}, {"c": false}, {"c": true}
 *      Output: {"c": {"counts": {"true": 2, "false": 1}}}
 *
 * 4. Array:
 *    - Aggregates the count of each unique value item across all arrays.
 *    - Example:
 *      Input: {"d": [1, 2]}, {"d": [2, 3]}, {"d": [3, 4]}
 *      Output: {"d": {"counts": {"1": 1, "2": 2, "3": 2, "4": 1}}}
 *    - Note: An exception is raised if arrays contain mixed types.
 *
 * 5. Object (Nested JSON):
 *    - Recursively aggregates nested JSON objects.
 *    - Example:
 *      Input: {"e": {"f": 1}}, {"e": {"f": 2}}, {"e": {"f": 3}}
 *      Output: {"e": {"f": {"sum": 6, "count": 3, "max": 3, "min": 1}}}
 *
 * Note:
 * - The function raises an exception if it encounters a type mismatch for a key across different rows.
 * - Semantically, a single key will always have the same structure across different rows, as it is uniquely defined in a table.
 * - The function should be used in conjunction with the jsonb_stats_to_summary_agg aggregate to process multiple rows.
 * ======================================================================================
 */

CREATE FUNCTION public.jsonb_stats_to_summary(state jsonb, stats jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE STRICT AS $$
DECLARE
    prev_stat_state jsonb;
    stat_key text;
    stat_value jsonb;
    stat_type text;
    prev_stat_type text;
    next_stat_state jsonb;
    state_type text;
    stats_type text;
BEGIN
    IF state IS NULL OR stats IS NULL THEN
        RAISE EXCEPTION 'Logic error: STRICT function should never be called with NULL';
    END IF;

    state_type := jsonb_typeof(state);
    IF state_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for state "%": % <> object', state, state_type;
    END IF;

    stats_type := jsonb_typeof(stats);
    IF stats_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for stats "%": % <> object', stats, stats_type;
    END IF;

    -- Update state with data from `value`
    FOR stat_key, stat_value IN SELECT * FROM jsonb_each(stats) LOOP
        stat_type := jsonb_typeof(stat_value);

        IF state ? stat_key THEN
            prev_stat_state := state->stat_key;
            prev_stat_type := prev_stat_state->>'type';
            IF stat_type <> prev_stat_type THEN
                RAISE EXCEPTION 'Type mismatch between values for key "%" was "%" became "%"', stat_key, prev_stat_type, stat_type;
            END IF;
            next_stat_state = jsonb_build_object('type', stat_type);

            CASE stat_type
                -- Handle numeric values with iterative mean, variance, standard deviation, and coefficient of variation.
                WHEN 'number' THEN
                    DECLARE
                        sum numeric := (prev_stat_state->'sum')::numeric + stat_value::numeric;
                        count integer := (prev_stat_state->'count')::integer + 1;
                        delta numeric := stat_value::numeric - (prev_stat_state->'mean')::numeric;
                        mean numeric := (prev_stat_state->'mean')::numeric + delta / count;
                        min numeric := LEAST((prev_stat_state->'min')::numeric, stat_value::numeric);
                        max numeric := GREATEST((prev_stat_state->'max')::numeric, stat_value::numeric);
                        sum_sq_diff numeric := (prev_stat_state->'sum_sq_diff')::numeric + delta * (stat_value::numeric - mean);

                        -- Calculate variance and standard deviation
                        variance numeric := CASE WHEN count > 1 THEN sum_sq_diff / (count - 1) ELSE NULL END;
                        stddev numeric := CASE WHEN variance IS NOT NULL THEN sqrt(variance) ELSE NULL END;

                        -- Calculate Coefficient of Variation (CV)
                        coefficient_of_variation_pct numeric := CASE
                            WHEN mean IS NULL OR mean = 0 THEN NULL
                            ELSE (stddev / mean) * 100
                        END;
                    BEGIN
                        next_stat_state :=  next_stat_state ||
                            jsonb_build_object(
                                'sum', sum,
                                'count', count,
                                'mean', mean,
                                'min', min,
                                'max', max,
                                'sum_sq_diff', sum_sq_diff,
                                'variance', variance,
                                'stddev', stddev,
                                'coefficient_of_variation_pct', coefficient_of_variation_pct
                            );
                    END;

                -- Handle string values
                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            -- The previous dictionary with count for each key.
                            (prev_stat_state->'counts')
                            -- Appending to it
                            ||
                            -- The updated count for this particular key.
                            jsonb_build_object(
                                -- Notice that `->>0` extracts the non-quoted string,
                                -- otherwise the key would be double quoted.
                                stat_value->>0,
                                COALESCE((prev_stat_state->'counts'->(stat_value->>0))::integer, 0) + 1
                            )
                        );

                -- Handle boolean types
                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', COALESCE((prev_stat_state->'counts'->'true')::integer, 0) + (stat_value::boolean)::integer,
                                'false', COALESCE((prev_stat_state->'counts'->'false')::integer, 0) + (NOT stat_value::boolean)::integer
                            )
                        );

                -- Handle array types
                WHEN 'array' THEN
                    DECLARE
                        element text;
                        element_count integer;
                        count integer;
                    BEGIN
                        -- Start with the previous state, to preserve previous counts.
                        next_stat_state := prev_stat_state;

                        FOR element IN SELECT jsonb_array_elements_text(stat_value) LOOP
                            -- Retrieve the old count for this element, defaulting to 0 if not present
                            count := COALESCE((next_stat_state->'counts'->element)::integer, 0) + 1;

                            -- Update the next state with the incremented count
                            next_stat_state := jsonb_set(
                                next_stat_state,
                                ARRAY['counts',element],
                                to_jsonb(count)
                            );
                        END LOOP;
                    END;

                -- Handle object (nested JSON)
                WHEN 'object' THEN
                    next_stat_state := public.jsonb_stats_to_summary(prev_stat_state, stat_value);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        ELSE
            -- Initialize new entry in state
            next_stat_state = jsonb_build_object('type', stat_type);
            CASE stat_type
                WHEN 'number' THEN
                    next_stat_state := next_stat_state ||
                        jsonb_build_object(
                            'sum', stat_value::numeric,
                            'count', 1,
                            'mean', stat_value::numeric,
                            'min', stat_value::numeric,
                            'max', stat_value::numeric,
                            'sum_sq_diff', 0,
                            'variance', 0,
                            'stddev', 0,
                            'coefficient_of_variation_pct', 0
                        );

                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            -- Notice that `->>0` extracts the non-quoted string,
                            -- otherwise the key would be double quoted.
                            'counts', jsonb_build_object(stat_value->>0, 1)
                        );

                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                            jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', (stat_value::boolean)::integer,
                                'false', (NOT stat_value::boolean)::integer
                            )
                        );

                WHEN 'array' THEN
                    -- Initialize array with counts of each unique value
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            (
                            SELECT jsonb_object_agg(element,1)
                            FROM jsonb_array_elements_text(stat_value) AS element
                            )
                        );

                WHEN 'object' THEN
                    next_stat_state := public.jsonb_stats_to_summary(next_stat_state, stat_value);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        END IF;

        state := state || jsonb_build_object(stat_key, next_stat_state);
    END LOOP;

    RETURN state;
END;
$$;


CREATE FUNCTION public.jsonb_stats_to_summary_round(state jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE STRICT AS $$
DECLARE
    key text;
    val jsonb;
    result jsonb := '{}';
    rounding_keys text[] := ARRAY['mean', 'sum_sq_diff', 'variance', 'stddev', 'coefficient_of_variation_pct'];
    sub_key text;
BEGIN
    -- Iterate through the keys in the state JSONB object
    FOR key, val IN SELECT * FROM jsonb_each(state) LOOP
        CASE jsonb_typeof(val)
            WHEN 'object' THEN
                -- Iterate over the rounding keys directly and apply rounding if key exists and value is numeric
                FOR sub_key IN SELECT unnest(rounding_keys) LOOP
                    IF val ? sub_key AND jsonb_typeof(val->sub_key) = 'number' THEN
                        val := val || jsonb_build_object(sub_key, round((val->sub_key)::numeric, 2));
                    END IF;
                END LOOP;

                -- Recursively process nested objects
                result := result || jsonb_build_object(key, public.jsonb_stats_to_summary_round(val));

            ELSE
                -- Non-object types are added to the result as is
                result := result || jsonb_build_object(key, val);
        END CASE;
    END LOOP;

    RETURN result;
END;
$$;


\echo public.jsonb_stats_to_summary_agg
CREATE AGGREGATE public.jsonb_stats_to_summary_agg(jsonb) (
    sfunc = public.jsonb_stats_to_summary,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_to_summary_round
);


\echo public.jsonb_stats_summary_merge
CREATE FUNCTION public.jsonb_stats_summary_merge(a jsonb, b jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
    key_a text;
    key_b text;
    val_a jsonb;
    val_b jsonb;
    merged_val jsonb;
    type_a text;
    type_b text;
    result jsonb := '{}';
BEGIN
    -- Ensure both a and b are objects
    IF jsonb_typeof(a) <> 'object' OR jsonb_typeof(b) <> 'object' THEN
        RAISE EXCEPTION 'Both arguments must be JSONB objects';
    END IF;

    -- Iterate over keys in both JSONB objects
    FOR key_a, val_a IN SELECT * FROM jsonb_each(a) LOOP
        IF b ? key_a THEN
            val_b := b->key_a;
            type_a := val_a->>'type';
            type_b := val_b->>'type';

            -- Ensure the types are the same for the same key
            IF type_a <> type_b THEN
                RAISE EXCEPTION 'Type mismatch for key "%": % vs %', key_a, type_a, type_b;
            END IF;

            -- Merge the values based on their type
            CASE type_a
                WHEN 'number' THEN
                    DECLARE
                        count_a INTEGER := (val_a->'count')::INTEGER;
                        count_b INTEGER := (val_b->'count')::INTEGER;
                        total_count INTEGER := count_a + count_b;

                        mean_a NUMERIC := (val_a->'mean')::NUMERIC;
                        mean_b NUMERIC := (val_b->'mean')::NUMERIC;
                        merged_mean NUMERIC := (mean_a * count_a + mean_b * count_b) / total_count;

                        sum_sq_diff_a NUMERIC := (val_a->'sum_sq_diff')::NUMERIC;
                        sum_sq_diff_b NUMERIC := (val_b->'sum_sq_diff')::NUMERIC;
                        delta NUMERIC := mean_b - mean_a;

                        merged_sum_sq_diff NUMERIC :=
                            sum_sq_diff_a + sum_sq_diff_b + delta * delta * count_a * count_b / total_count;
                        merged_variance NUMERIC :=
                            CASE WHEN total_count > 1
                            THEN merged_sum_sq_diff / (total_count - 1)
                            ELSE NULL
                            END;
                        merged_stddev NUMERIC :=
                            CASE WHEN merged_variance IS NOT NULL
                            THEN sqrt(merged_variance)
                            ELSE NULL
                            END;

                        -- Calculate Coefficient of Variation (CV)
                        coefficient_of_variation_pct NUMERIC :=
                            CASE WHEN merged_mean <> 0
                            THEN (merged_stddev / merged_mean) * 100
                            ELSE NULL
                            END;
                    BEGIN
                        merged_val := jsonb_build_object(
                            'sum', (val_a->'sum')::numeric + (val_b->'sum')::numeric,
                            'count', total_count,
                            'mean', merged_mean,
                            'min', LEAST((val_a->'min')::numeric, (val_b->'min')::numeric),
                            'max', GREATEST((val_a->'max')::numeric, (val_b->'max')::numeric),
                            'sum_sq_diff', merged_sum_sq_diff,
                            'variance', merged_variance,
                            'stddev', merged_stddev,
                            'coefficient_of_variation_pct', coefficient_of_variation_pct
                        );
                    END;

                WHEN 'string' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );

                WHEN 'boolean' THEN
                    merged_val := jsonb_build_object(
                        'counts', jsonb_build_object(
                            'true', (val_a->'counts'->>'true')::integer + (val_b->'counts'->>'true')::integer,
                            'false', (val_a->'counts'->>'false')::integer + (val_b->'counts'->>'false')::integer
                        )
                    );

                WHEN 'array' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );

                WHEN 'object' THEN
                    merged_val := public.jsonb_stats_summary_merge(val_a, val_b);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for key "%"', type_a, key_a;
            END CASE;

            -- Add the merged value to the result
            result := result || jsonb_build_object(key_a, jsonb_build_object('type', type_a) || merged_val);
        ELSE
            -- Key only in a
            result := result || jsonb_build_object(key_a, val_a);
        END IF;
    END LOOP;

    -- Add keys only in b
    FOR key_b, val_b IN SELECT key, value FROM jsonb_each(b) WHERE NOT (a ? key) LOOP
        result := result || jsonb_build_object(key_b, val_b);
    END LOOP;

    RETURN result;
END;
$$;


\echo public.jsonb_stats_summary_merge_agg
CREATE AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb) (
    sfunc = public.jsonb_stats_summary_merge,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_to_summary_round
);


\echo public.jsonb_concat_agg()
-- Aggregate: jsonb_concat_agg
-- Purpose: Aggregate function to concatenate JSONB objects from multiple rows into a single JSONB object.
-- Example:
--   SELECT jsonb_concat_agg(column_name) FROM table_name;
--   Output: A single JSONB object resulting from the concatenation of JSONB objects from all rows.
-- Notice:
--   The function `jsonb_concat` is not documented, but named equivalent of `||`.
CREATE AGGREGATE public.jsonb_concat_agg(jsonb) (
    sfunc = jsonb_concat,
    stype = jsonb,
    initcond = '{}'
);


-- Final function to remove duplicates from concatenated arrays
CREATE FUNCTION public.array_distinct_concat_final(anycompatiblearray)
RETURNS anycompatiblearray LANGUAGE sql AS $$
SELECT array_agg(DISTINCT elem)
  FROM unnest($1) as elem;
$$;

-- Aggregate function using array_cat for concatenation and public.array_distinct_concat_final to remove duplicates
CREATE AGGREGATE public.array_distinct_concat(anycompatiblearray) (
  SFUNC = pg_catalog.array_cat,
  STYPE = anycompatiblearray,
  FINALFUNC = public.array_distinct_concat_final,
  INITCOND = '{}'
);


\echo public.get_jsonb_stats
CREATE OR REPLACE FUNCTION public.get_jsonb_stats(
    p_establishment_id INTEGER,
    p_legal_unit_id INTEGER,
    p_valid_after DATE,
    p_valid_to DATE
) RETURNS JSONB LANGUAGE sql AS $get_jsonb_stats$
    SELECT public.jsonb_concat_agg(
        CASE sd.type
            WHEN 'int' THEN jsonb_build_object(sd.code, sfu.value_int)
            WHEN 'float' THEN jsonb_build_object(sd.code, sfu.value_float)
            WHEN 'string' THEN jsonb_build_object(sd.code, sfu.value_string)
            WHEN 'bool' THEN jsonb_build_object(sd.code, sfu.value_bool)
        END
    )
    FROM public.stat_for_unit AS sfu
    LEFT JOIN public.stat_definition AS sd
        ON sfu.stat_definition_id = sd.id
    WHERE (p_establishment_id IS NULL OR sfu.establishment_id = p_establishment_id)
      AND (p_legal_unit_id IS NULL OR sfu.legal_unit_id = p_legal_unit_id)
      AND daterange(p_valid_after, p_valid_to, '(]')
      && daterange(sfu.valid_after, sfu.valid_to, '(]')
$get_jsonb_stats$;


\echo public.timeline_establishment
CREATE VIEW public.timeline_establishment
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
    , name
    , birth_date
    , death_date
    , search
    , primary_activity_category_id
    , primary_activity_category_path
    , secondary_activity_category_id
    , secondary_activity_category_path
    , activity_category_paths
    , sector_id
    , sector_path
    , sector_code
    , sector_name
    , data_source_ids
    , data_source_codes
    , legal_form_id
    , legal_form_code
    , legal_form_name
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postal_code
    , physical_postal_place
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postal_code
    , postal_postal_place
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , establishment_id
    , legal_unit_id
    , enterprise_id
    , stats
    )
    AS
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , es.name AS name
           , es.birth_date AS birth_date
           , es.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', es.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
           --
           , NULLIF(ARRAY_REMOVE(ARRAY[pac.path, sac.path], NULL), '{}') AS activity_category_paths
           --
           , s.id   AS sector_id
           , s.path AS sector_path
           , s.code AS sector_code
           , s.name AS sector_name
           --
           , COALESCE(ds.ids, ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           , NULL::INTEGER AS legal_form_id
           , NULL::TEXT    AS legal_form_code
           , NULL::TEXT    AS legal_form_name
           --
           , phl.address_part1 AS physical_address_part1
           , phl.address_part2 AS physical_address_part2
           , phl.address_part3 AS physical_address_part3
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , es.invalid_codes AS invalid_codes
           --
           , es.id AS establishment_id
           , es.legal_unit_id AS legal_unit_id
           , es.enterprise_id AS enterprise_id
           --
           , COALESCE(public.get_jsonb_stats(es.id, NULL, t.valid_after, t.valid_to), '{}'::JSONB) AS stats
      --
      FROM public.timesegments AS t
      INNER JOIN public.establishment AS es
          ON t.unit_type = 'establishment' AND t.unit_id = es.id
         AND daterange(t.valid_after, t.valid_to, '(]')
          && daterange(es.valid_after, es.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = es.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = es.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON es.sector_id = s.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.establishment_id = es.id
             AND phl.type = 'physical'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = es.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
            SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.establishment_id = es.id
              AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
        SELECT array_agg(ds.id) AS ids
             , array_agg(ds.code) AS codes
        FROM public.data_source AS ds
        WHERE COALESCE(ds.id = es.data_source_id       , FALSE)
           OR COALESCE(ds.id = pa.data_source_id       , FALSE)
           OR COALESCE(ds.id = sa.data_source_id       , FALSE)
           OR COALESCE(ds.id = phl.data_source_id      , FALSE)
           OR COALESCE(ds.id = pol.data_source_id      , FALSE)
           OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      --
      ORDER BY t.unit_type, t.unit_id, t.valid_after
;

--SELECT * FROM public.timeline_establishment;

\echo public.timeline_legal_unit
CREATE VIEW public.timeline_legal_unit
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
    , name
    , birth_date
    , death_date
    , search
    , primary_activity_category_id
    , primary_activity_category_path
    , secondary_activity_category_id
    , secondary_activity_category_path
    , activity_category_paths
    , sector_id
    , sector_path
    , sector_code
    , sector_name
    , data_source_ids
    , data_source_codes
    , legal_form_id
    , legal_form_code
    , legal_form_name
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postal_code
    , physical_postal_place
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postal_code
    , postal_postal_place
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , establishment_ids
    , legal_unit_id
    , enterprise_id
    , stats
    , stats_summary
    )
    AS
      WITH basis AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , lu.name AS name
           , lu.birth_date AS birth_date
           , lu.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', lu.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
           --
           , NULLIF(ARRAY_REMOVE(ARRAY[pac.path, sac.path], NULL), '{}') AS activity_category_paths
           --
           , s.id    AS sector_id
           , s.path  AS sector_path
           , s.code  AS sector_code
           , s.name  AS sector_name
           --
           , COALESCE(ds.ids,ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           , lf.id   AS legal_form_id
           , lf.code AS legal_form_code
           , lf.name AS legal_form_name
           --
           , phl.address_part1 AS physical_address_part1
           , phl.address_part2 AS physical_address_part2
           , phl.address_part3 AS physical_address_part3
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , lu.invalid_codes AS invalid_codes
           --
           , lu.id AS legal_unit_id
           , lu.enterprise_id AS enterprise_id
           , COALESCE(public.get_jsonb_stats(NULL, lu.id, t.valid_after, t.valid_to), '{}'::JSONB) AS stats
      --
      FROM public.timesegments AS t
      INNER JOIN public.legal_unit AS lu
          ON t.unit_type = 'legal_unit' AND t.unit_id = lu.id
         AND daterange(t.valid_after, t.valid_to, '(]')
          && daterange(lu.valid_after, lu.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = lu.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = lu.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON lu.sector_id = s.id
      --
      LEFT OUTER JOIN public.legal_form AS lf
              ON lu.legal_form_id = lf.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.legal_unit_id = lu.id
             AND phl.type = 'physical'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = lu.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
              SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
              FROM public.stat_for_unit AS sfu
              WHERE sfu.legal_unit_id = lu.id
                AND daterange(t.valid_after, t.valid_to, '(]')
                && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
         WHERE COALESCE(ds.id = lu.data_source_id       , FALSE)
            OR COALESCE(ds.id = pa.data_source_id       , FALSE)
            OR COALESCE(ds.id = sa.data_source_id       , FALSE)
            OR COALESCE(ds.id = phl.data_source_id      , FALSE)
            OR COALESCE(ds.id = pol.data_source_id      , FALSE)
            OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      ), aggregation AS (
        SELECT tes.legal_unit_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tes.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tes.data_source_codes) AS data_source_codes
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids
             , public.jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
          FROM public.timeline_establishment AS tes
          INNER JOIN basis
           ON tes.legal_unit_id = basis.legal_unit_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tes.valid_after, tes.valid_to, '(]')
        GROUP BY tes.legal_unit_id, basis.valid_after , basis.valid_to
        )
      SELECT basis.unit_type
           , basis.unit_id
           , basis.valid_after
           , basis.valid_from
           , basis.valid_to
           , basis.name
           , basis.birth_date
           , basis.death_date
           , basis.search
           , basis.primary_activity_category_id
           , basis.primary_activity_category_path
           , basis.secondary_activity_category_id
           , basis.secondary_activity_category_path
           , basis.activity_category_paths
           , basis.sector_id
           , basis.sector_path
           , basis.sector_code
           , basis.sector_name
           , (
               SELECT array_agg(DISTINCT id)
               FROM (
                   SELECT unnest(basis.data_source_ids) AS id
                   UNION ALL
                   SELECT unnest(aggregation.data_source_ids) AS id
               ) AS ids
           ) AS data_source_ids
           , (
               SELECT array_agg(DISTINCT code)
               FROM (
                   SELECT unnest(basis.data_source_codes) AS code
                   UNION ALL
                   SELECT unnest(aggregation.data_source_codes) AS code
               ) AS codes
           ) AS data_source_codes
           , basis.legal_form_id
           , basis.legal_form_code
           , basis.legal_form_name
           , basis.physical_address_part1
           , basis.physical_address_part2
           , basis.physical_address_part3
           , basis.physical_postal_code
           , basis.physical_postal_place
           , basis.physical_region_id
           , basis.physical_region_path
           , basis.physical_country_id
           , basis.physical_country_iso_2
           , basis.postal_address_part1
           , basis.postal_address_part2
           , basis.postal_address_part3
           , basis.postal_postal_code
           , basis.postal_postal_place
           , basis.postal_region_id
           , basis.postal_region_path
           , basis.postal_country_id
           , basis.postal_country_iso_2
           , basis.invalid_codes
           , COALESCE(aggregation.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
           , basis.legal_unit_id
           , basis.enterprise_id
           -- Expose the stats for just this entry.
           , basis.stats AS stats
           -- Continue one more aggregation iteration adding the stats for this unit
           -- to the aggregated stats for establishments, by using the internal
           -- aggregation function for one more step.
           , public.jsonb_stats_to_summary(COALESCE(aggregation.stats_summary,'{}'::JSONB), basis.stats) AS stats_summary
      FROM basis
      LEFT OUTER JOIN aggregation
       ON basis.legal_unit_id = aggregation.legal_unit_id
      AND basis.valid_after = aggregation.valid_after
      AND basis.valid_to = aggregation.valid_to
      --
      ORDER BY unit_type, unit_id, valid_after
;

--SELECT * FROM public.timeline_legal_unit;


\echo public.timeline_enterprise
CREATE VIEW public.timeline_enterprise
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
    , name
    , birth_date
    , death_date
    , search
    , primary_activity_category_id
    , primary_activity_category_path
    , secondary_activity_category_id
    , secondary_activity_category_path
    , activity_category_paths
    , sector_id
    , sector_path
    , sector_code
    , sector_name
    , data_source_ids
    , data_source_codes
    , legal_form_id
    , legal_form_code
    , legal_form_name
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postal_code
    , physical_postal_place
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postal_code
    , postal_postal_place
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , establishment_ids
    , legal_unit_ids
    , enterprise_id
    , primary_establishment_id
    , primary_legal_unit_id
    , stats_summary
    )
    AS
      WITH basis_with_legal_unit AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , plu.name AS name
           , plu.birth_date AS birth_date
           , plu.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', plu.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
           --
           , NULLIF(ARRAY_REMOVE(ARRAY[pac.path, sac.path], NULL), '{}') AS activity_category_paths
           --
           , s.id   AS sector_id
           , s.path AS sector_path
           , s.code AS sector_code
           , s.name AS sector_name
           --
           , COALESCE(ds.ids,ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           , lf.id   AS legal_form_id
           , lf.code AS legal_form_code
           , lf.name AS legal_form_name
           --
           , phl.address_part1 AS physical_address_part1
           , phl.address_part2 AS physical_address_part2
           , phl.address_part3 AS physical_address_part3
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , plu.invalid_codes AS invalid_codes
           --
           , en.id AS enterprise_id
           , plu.id AS primary_legal_unit_id
      FROM public.timesegments AS t
      INNER JOIN public.enterprise AS en
          ON t.unit_type = 'enterprise' AND t.unit_id = en.id
      INNER JOIN public.legal_unit AS plu
          ON plu.enterprise_id = en.id
          AND plu.primary_for_enterprise
          AND daterange(t.valid_after, t.valid_to, '(]')
           && daterange(plu.valid_after, plu.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = plu.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = plu.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON plu.sector_id = s.id
      --
      LEFT OUTER JOIN public.legal_form AS lf
              ON plu.legal_form_id = lf.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.legal_unit_id = plu.id
             AND phl.type = 'physical'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = plu.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
              SELECT array_agg(sfu.data_source_id) AS data_source_ids
              FROM public.stat_for_unit AS sfu
              WHERE sfu.legal_unit_id = plu.id
                AND daterange(t.valid_after, t.valid_to, '(]')
                && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
          WHERE COALESCE(ds.id = plu.data_source_id      , FALSE)
             OR COALESCE(ds.id = pa.data_source_id       , FALSE)
             OR COALESCE(ds.id = sa.data_source_id       , FALSE)
             OR COALESCE(ds.id = phl.data_source_id      , FALSE)
             OR COALESCE(ds.id = pol.data_source_id      , FALSE)
             OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      ), basis_with_establishment AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , pes.name AS name
           , pes.birth_date AS birth_date
           , pes.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', pes.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
           --
           , NULLIF(ARRAY_REMOVE(ARRAY[pac.path, sac.path], NULL), '{}') AS activity_category_paths
           --
           , s.id   AS sector_id
           , s.path AS sector_path
           , s.code AS sector_code
           , s.name AS sector_name
           --
           , COALESCE(ds.ids,ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           -- An establishment has no legal_form, that is for legal_unit only.
           , NULL::INTEGER AS legal_form_id
           , NULL::VARCHAR AS legal_form_code
           , NULL::VARCHAR AS legal_form_name
           --
           , phl.address_part1 AS physical_address_part1
           , phl.address_part2 AS physical_address_part2
           , phl.address_part3 AS physical_address_part3
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , pes.invalid_codes AS invalid_codes
           --
           , en.id AS enterprise_id
           , pes.id AS primary_establishment_id
      FROM public.timesegments AS t
      INNER JOIN public.enterprise AS en
          ON t.unit_type = 'enterprise' AND t.unit_id = en.id
      INNER JOIN public.establishment AS pes
          ON pes.enterprise_id = en.id
          AND daterange(t.valid_after, t.valid_to, '(]')
           && daterange(pes.valid_after, pes.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = pes.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = pes.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON pes.sector_id = s.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.establishment_id = pes.id
             AND phl.type = 'physical'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = pes.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
            SELECT array_agg(sfu.data_source_id) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.legal_unit_id = pes.id
              AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
         WHERE COALESCE(ds.id = pes.data_source_id      , FALSE)
            OR COALESCE(ds.id = pa.data_source_id       , FALSE)
            OR COALESCE(ds.id = sa.data_source_id       , FALSE)
            OR COALESCE(ds.id = phl.data_source_id      , FALSE)
            OR COALESCE(ds.id = pol.data_source_id      , FALSE)
            OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      ), establishment_aggregation AS (
        SELECT tes.enterprise_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tes.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tes.data_source_codes) AS data_source_codes
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids
             , public.jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
          FROM public.timeline_establishment AS tes
          INNER JOIN basis_with_establishment AS basis
           ON tes.enterprise_id = basis.enterprise_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tes.valid_after, tes.valid_to, '(]')
        GROUP BY tes.enterprise_id, basis.valid_after , basis.valid_to
      ), legal_unit_aggregation AS (
        SELECT tlu.enterprise_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tlu.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tlu.data_source_codes) AS data_source_codes
             , public.array_distinct_concat(tlu.establishment_ids) AS establishment_ids
             , array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.legal_unit_id IS NOT NULL) AS legal_unit_ids
             , public.jsonb_stats_summary_merge_agg(tlu.stats_summary) AS stats_summary
          FROM public.timeline_legal_unit AS tlu
          INNER JOIN basis_with_legal_unit AS basis
           ON tlu.enterprise_id = basis.enterprise_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tlu.valid_after, tlu.valid_to, '(]')
        GROUP BY tlu.enterprise_id, basis.valid_after , basis.valid_to
        ), basis_with_legal_unit_aggregation AS (
          SELECT basis.unit_type
               , basis.unit_id
               , basis.valid_after
               , basis.valid_from
               , basis.valid_to
               , basis.name
               , basis.birth_date
               , basis.death_date
               , basis.search
               , basis.primary_activity_category_id
               , basis.primary_activity_category_path
               , basis.secondary_activity_category_id
               , basis.secondary_activity_category_path
               , basis.activity_category_paths
               , basis.sector_id
               , basis.sector_path
               , basis.sector_code
               , basis.sector_name
               , (
                   SELECT array_agg(DISTINCT id)
                   FROM (
                       SELECT unnest(basis.data_source_ids) AS id
                       UNION
                       SELECT unnest(lua.data_source_ids) AS id
                   ) AS ids
               ) AS data_source_ids
               , (
                   SELECT array_agg(DISTINCT code)
                   FROM (
                       SELECT unnest(basis.data_source_codes) AS code
                       UNION ALL
                       SELECT unnest(lua.data_source_codes) AS code
                   ) AS codes
               ) AS data_source_codes
               , basis.legal_form_id
               , basis.legal_form_code
               , basis.legal_form_name
               , basis.physical_address_part1
               , basis.physical_address_part2
               , basis.physical_address_part3
               , basis.physical_postal_code
               , basis.physical_postal_place
               , basis.physical_region_id
               , basis.physical_region_path
               , basis.physical_country_id
               , basis.physical_country_iso_2
               , basis.postal_address_part1
               , basis.postal_address_part2
               , basis.postal_address_part3
               , basis.postal_postal_code
               , basis.postal_postal_place
               , basis.postal_region_id
               , basis.postal_region_path
               , basis.postal_country_id
               , basis.postal_country_iso_2
               , basis.invalid_codes
               , COALESCE(lua.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
               , COALESCE(lua.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids
               , basis.enterprise_id
               , NULL::INTEGER AS primary_establishment_id
               , basis.primary_legal_unit_id
               , lua.stats_summary AS stats_summary
          FROM basis_with_legal_unit AS basis
          LEFT OUTER JOIN legal_unit_aggregation AS lua
                       ON basis.enterprise_id = lua.enterprise_id
                      AND basis.valid_after = lua.valid_after
                      AND basis.valid_to = lua.valid_to
        ), basis_with_establishment_aggregation AS (
          SELECT basis.unit_type
               , basis.unit_id
               , basis.valid_after
               , basis.valid_from
               , basis.valid_to
               , basis.name
               , basis.birth_date
               , basis.death_date
               , basis.search
               , basis.primary_activity_category_id
               , basis.primary_activity_category_path
               , basis.secondary_activity_category_id
               , basis.secondary_activity_category_path
               , basis.activity_category_paths
               , basis.sector_id
               , basis.sector_path
               , basis.sector_code
               , basis.sector_name
               , (
                   SELECT array_agg(DISTINCT id)
                   FROM (
                       SELECT unnest(basis.data_source_ids) AS id
                       UNION
                       SELECT unnest(esa.data_source_ids) AS id
                   ) AS ids
               ) AS data_source_ids
               , (
                   SELECT array_agg(DISTINCT code)
                   FROM (
                       SELECT unnest(basis.data_source_codes) AS code
                       UNION ALL
                       SELECT unnest(esa.data_source_codes) AS code
                   ) AS codes
               ) AS data_source_codes
               , basis.legal_form_id
               , basis.legal_form_code
               , basis.legal_form_name
               , basis.physical_address_part1
               , basis.physical_address_part2
               , basis.physical_address_part3
               , basis.physical_postal_code
               , basis.physical_postal_place
               , basis.physical_region_id
               , basis.physical_region_path
               , basis.physical_country_id
               , basis.physical_country_iso_2
               , basis.postal_address_part1
               , basis.postal_address_part2
               , basis.postal_address_part3
               , basis.postal_postal_code
               , basis.postal_postal_place
               , basis.postal_region_id
               , basis.postal_region_path
               , basis.postal_country_id
               , basis.postal_country_iso_2
               , basis.invalid_codes
               , COALESCE(esa.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
               , ARRAY[]::INT[] AS legal_unit_ids
               , basis.enterprise_id
               , basis.primary_establishment_id
               , NULL::INTEGER AS primary_legal_unit_id
               , esa.stats_summary AS stats_summary
          FROM basis_with_establishment AS basis
          LEFT OUTER JOIN establishment_aggregation AS esa
                       ON basis.enterprise_id = esa.enterprise_id
                      AND basis.valid_after = esa.valid_after
                      AND basis.valid_to = esa.valid_to
        ), basis_with_both AS (
            SELECT * FROM basis_with_legal_unit_aggregation
            UNION ALL
            SELECT * FROM basis_with_establishment_aggregation
        )
        SELECT * FROM basis_with_both
         ORDER BY unit_type, unit_id, valid_after
;

-- SELECT * FROM public.timeline_enterprise;

\echo public.get_external_idents
CREATE FUNCTION public.get_external_idents(
  unit_type public.statistical_unit_type,
  unit_id INTEGER
) RETURNS JSONB LANGUAGE sql STABLE STRICT AS $$
    SELECT jsonb_object_agg(eit.code, ei.ident ORDER BY eit.priority NULLS LAST, eit.code) AS external_idents
    FROM public.external_ident AS ei
    JOIN public.external_ident_type AS eit ON eit.id = ei.type_id
    WHERE
      CASE unit_type
        WHEN 'enterprise' THEN ei.enterprise_id = unit_id
        WHEN 'legal_unit' THEN ei.legal_unit_id = unit_id
        WHEN 'establishment' THEN ei.establishment_id = unit_id
        WHEN 'enterprise_group' THEN ei.enterprise_group_id = unit_id
      END;
$$;


\echo public.enterprise_external_idents
CREATE VIEW public.enterprise_external_idents AS
  SELECT 'enterprise'::public.statistical_unit_type AS unit_type
        , plu.enterprise_id AS unit_id
        , public.get_external_idents('legal_unit', plu.id) AS external_idents
        , plu.valid_after
        , plu.valid_to
  FROM public.legal_unit plu
  WHERE  plu.primary_for_enterprise = true
  UNION ALL
  SELECT 'enterprise'::public.statistical_unit_type AS unit_type
       , pes.enterprise_id AS unit_id
       , public.get_external_idents('establishment', pes.id) AS external_idents
       , pes.valid_after
       , pes.valid_to
  FROM public.establishment pes
  WHERE pes.enterprise_id IS NOT NULL
; -- END public.enterprise_external_idents


\echo public.get_tag_paths
CREATE FUNCTION public.get_tag_paths(
  unit_type public.statistical_unit_type,
  unit_id INTEGER
) RETURNS public.ltree[] LANGUAGE sql STABLE STRICT AS $$
  WITH ordered_data AS (
    SELECT DISTINCT t.path
    FROM public.tag_for_unit AS tfu
    JOIN public.tag AS t ON t.id = tfu.tag_id
    WHERE
      CASE unit_type
      WHEN 'enterprise' THEN tfu.enterprise_id = unit_id
      WHEN 'legal_unit' THEN tfu.legal_unit_id = unit_id
      WHEN 'establishment' THEN tfu.establishment_id = unit_id
      WHEN 'enterprise_group' THEN tfu.enterprise_group_id = unit_id
      END
    ORDER BY t.path
  ), agg_data AS (
    SELECT array_agg(path) AS tag_paths FROM ordered_data
  )
  SELECT COALESCE(tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
  FROM agg_data;
$$;



\echo public.statistical_unit_def
CREATE VIEW public.statistical_unit_def
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
    , external_idents
    , name
    , birth_date
    , death_date
    , search
    , primary_activity_category_id
    , primary_activity_category_path
    , secondary_activity_category_id
    , secondary_activity_category_path
    , activity_category_paths
    , sector_id
    , sector_path
    , sector_code
    , sector_name
    , data_source_ids
    , data_source_codes
    , legal_form_id
    , legal_form_code
    , legal_form_name
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postal_code
    , physical_postal_place
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postal_code
    , postal_postal_place
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , establishment_ids
    , legal_unit_ids
    , enterprise_ids
    , stats
    , stats_summary
    , establishment_count
    , legal_unit_count
    , enterprise_count
    , tag_paths
    )
    AS
    WITH data AS (
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , public.get_external_idents(unit_type, unit_id) AS external_idents
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , data_source_ids
           , data_source_codes
           , legal_form_id
           , legal_form_code
           , legal_form_name
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , ARRAY[establishment_id]::INT[] AS establishment_ids
           -- An establishment may have either a legal_unit or
           -- an enterprise, so handle that any of them are null gracefully.
           , CASE WHEN legal_unit_id IS NULL
                  THEN ARRAY[]::INT[]
                  ELSE ARRAY[legal_unit_id]::INT[]
              END AS legal_unit_ids
           , CASE WHEN enterprise_id IS NULL
                  THEN ARRAY[]::INT[]
                  ELSE ARRAY[enterprise_id]::INT[]
              END AS enterprise_ids
           , stats
           , COALESCE(public.jsonb_stats_to_summary('{}'::JSONB,stats), '{}'::JSONB) AS stats_summary
      FROM public.timeline_establishment
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , public.get_external_idents(unit_type, unit_id) AS external_idents
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , data_source_ids
           , data_source_codes
           , legal_form_id
           , legal_form_code
           , legal_form_name
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , establishment_ids
           , ARRAY[legal_unit_id]::INT[] AS legal_unit_ids
           , ARRAY[enterprise_id]::INT[] AS enterprise_ids
           , stats
           , stats_summary
      FROM public.timeline_legal_unit
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , COALESCE(
             public.get_external_idents(unit_type, unit_id),
             public.get_external_idents('establishment'::public.statistical_unit_type, primary_establishment_id),
             public.get_external_idents('legal_unit'::public.statistical_unit_type, primary_legal_unit_id)
           ) AS external_idents
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , data_source_ids
           , data_source_codes
           , legal_form_id
           , legal_form_code
           , legal_form_name
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , establishment_ids
           , legal_unit_ids
           , ARRAY[enterprise_id]::INT[] AS enterprise_ids
           , NULL::JSONB AS stats
           , stats_summary
      FROM public.timeline_enterprise
      --UNION ALL
      --SELECT * FROM enterprise_group_timeline
    )
    SELECT data.unit_type
         , data.unit_id
         , data.valid_after
         , data.valid_from
         , data.valid_to
         , data.external_idents
         , data.name
         , data.birth_date
         , data.death_date
         , data.search
         , data.primary_activity_category_id
         , data.primary_activity_category_path
         , data.secondary_activity_category_id
         , data.secondary_activity_category_path
         , data.activity_category_paths
         , data.sector_id
         , data.sector_path
         , data.sector_code
         , data.sector_name
         , data.data_source_ids
         , data.data_source_codes
         , data.legal_form_id
         , data.legal_form_code
         , data.legal_form_name
         , data.physical_address_part1
         , data.physical_address_part2
         , data.physical_address_part3
         , data.physical_postal_code
         , data.physical_postal_place
         , data.physical_region_id
         , data.physical_region_path
         , data.physical_country_id
         , data.physical_country_iso_2
         , data.postal_address_part1
         , data.postal_address_part2
         , data.postal_address_part3
         , data.postal_postal_code
         , data.postal_postal_place
         , data.postal_region_id
         , data.postal_region_path
         , data.postal_country_id
         , data.postal_country_iso_2
         , data.invalid_codes
         , data.establishment_ids
         , data.legal_unit_ids
         , data.enterprise_ids
         , data.stats
         , data.stats_summary
         , COALESCE(array_length(data.establishment_ids,1),0) AS establishment_count
         , COALESCE(array_length(data.legal_unit_ids,1),0) AS legal_unit_count
         , COALESCE(array_length(data.enterprise_ids,1),0) AS enterprise_count
         , public.get_tag_paths(data.unit_type, data.unit_id) AS tag_paths
    FROM data;
;


\echo public.statistical_unit
CREATE MATERIALIZED VIEW public.statistical_unit AS
SELECT * FROM public.statistical_unit_def;

\echo statistical_unit_key
CREATE UNIQUE INDEX "statistical_unit_key"
    ON public.statistical_unit
    (valid_from
    ,valid_to
    ,unit_type
    ,unit_id
    );
\echo idx_statistical_unit_unit_type
CREATE INDEX idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
\echo idx_statistical_unit_establishment_id
CREATE INDEX idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
\echo idx_statistical_unit_search
CREATE INDEX idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
\echo idx_statistical_unit_primary_activity_category_id
CREATE INDEX idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
\echo idx_statistical_unit_secondary_activity_category_id
CREATE INDEX idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
\echo idx_statistical_unit_physical_region_id
CREATE INDEX idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
\echo idx_statistical_unit_physical_country_id
CREATE INDEX idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
\echo idx_statistical_unit_sector_id
CREATE INDEX idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);

\echo idx_statistical_unit_data_source_ids
CREATE INDEX idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);

CREATE INDEX idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
CREATE INDEX idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

\echo idx_statistical_unit_legal_form_id
CREATE INDEX idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);
\echo idx_statistical_unit_invalid_codes
CREATE INDEX idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
\echo idx_statistical_unit_invalid_codes_exists
CREATE INDEX idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

\echo idx_statistical_unit_primary_activity_category_path
CREATE INDEX idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
\echo idx_gist_statistical_unit_primary_activity_category_path
CREATE INDEX idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

\echo idx_statistical_unit_secondary_activity_category_path
CREATE INDEX idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
\echo idx_gist_statistical_unit_secondary_activity_category_path
CREATE INDEX idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

\echo idx_statistical_unit_activity_category_paths
CREATE INDEX idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
\echo idx_gist_statistical_unit_activity_category_paths
CREATE INDEX idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

\echo idx_statistical_unit_physical_region_path
CREATE INDEX idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
\echo idx_gist_statistical_unit_physical_region_path
CREATE INDEX idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

\echo idx_statistical_unit_external_idents
CREATE INDEX idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
\echo idx_gist_statistical_unit_external_idents
CREATE INDEX idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

\echo idx_statistical_unit_tag_paths
CREATE INDEX idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
\echo idx_gist_statistical_unit_tag_paths
CREATE INDEX idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);


\echo admin.generate_statistical_unit_jsonb_indices()
CREATE PROCEDURE admin.generate_statistical_unit_jsonb_indices()
LANGUAGE plpgsql AS $generate_statistical_unit_jsonb_indices$
DECLARE
    ident_type public.external_ident_type;
    stat_definition public.stat_definition;
BEGIN
    -- Loop over each external_ident_type to create indices
    FOR ident_type IN SELECT * FROM public.external_ident_type_active LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_ei_%1$s_idx ON public.statistical_unit ((external_idents->>%1$L))
$$, ident_type.code);
        RAISE NOTICE 'Created index su_ei_% for external_ident_type', ident_type.code;
    END LOOP;

    -- Loop over each stat_definition to create indices
    FOR stat_definition IN SELECT * FROM public.stat_definition_active LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_s_%1$s_idx ON public.statistical_unit ((stats->>%1$L));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_sum_idx ON public.statistical_unit ((stats_summary->%1$L->>'sum'));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_count_idx ON public.statistical_unit ((stats_summary->%1$L->>'count'));
$$, stat_definition.code);
        RAISE NOTICE 'Created indices for stat_definition %', stat_definition.code;
    END LOOP;
END;
$generate_statistical_unit_jsonb_indices$;

\echo admin.cleanup_statistical_unit_jsonb_indices()
CREATE PROCEDURE admin.cleanup_statistical_unit_jsonb_indices()
LANGUAGE plpgsql AS $cleanup_statistical_unit_jsonb_indices$
DECLARE
    r RECORD;
BEGIN
    -- Use a query to find and drop all indices matching the patterns
    FOR r IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'statistical_unit'
          AND indexname ILIKE 'su_ei_%_idx'
            OR indexname ILIKE 'su_s_%_idx'
            OR indexname ILIKE 'su_ss_%_sum_idx'
            OR indexname ILIKE 'su_ss_%_count_idx'
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped index %', r.indexname;
    END LOOP;
END;
$cleanup_statistical_unit_jsonb_indices$;

\echo Add statistical_unit callbacks for jsonb indices
CALL lifecycle_callbacks.add(
    'statistical_unit_jsonb_indices',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_statistical_unit_jsonb_indices',
    'admin.cleanup_statistical_unit_jsonb_indices'
    );

\echo Calling public.generate_statistical_unit_jsonb_indices
CALL admin.generate_statistical_unit_jsonb_indices();


\echo public.activity_category_used
CREATE MATERIALIZED VIEW public.activity_category_used AS
SELECT acs.code AS standard_code
     , ac.id
     , ac.path
     , acp.path AS parent_path
     , ac.code
     , ac.label
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
LEFT JOIN public.activity_category AS acp ON ac.parent_id = acp.id
WHERE acs.id = (SELECT activity_category_standard_id FROM public.settings)
  AND ac.active
  AND ac.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT primary_activity_category_path) FROM public.statistical_unit WHERE primary_activity_category_path IS NOT NULL)
ORDER BY path;

CREATE UNIQUE INDEX "activity_category_used_key"
    ON public.activity_category_used (path);


\echo public.region_used
CREATE MATERIALIZED VIEW public.region_used AS
SELECT r.id
     , r.path
     , r.level
     , r.label
     , r.code
     , r.name
FROM public.region AS r
WHERE r.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT physical_region_path) FROM public.statistical_unit WHERE physical_region_path IS NOT NULL)
ORDER BY public.nlevel(path), path;

CREATE UNIQUE INDEX "region_used_key"
    ON public.region_used (path);

\echo public.sector_used
CREATE MATERIALIZED VIEW public.sector_used AS
SELECT s.id
     , s.path
     , s.label
     , s.code
     , s.name
FROM public.sector AS s
WHERE s.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT sector_path) FROM public.statistical_unit WHERE sector_path IS NOT NULL)
  AND s.active
ORDER BY s.path;

CREATE UNIQUE INDEX "sector_used_key"
    ON public.sector_used (path);

\echo public.data_source_used
CREATE MATERIALIZED VIEW public.data_source_used AS
SELECT s.id
     , s.code
     , s.name
FROM public.data_source AS s
WHERE s.id IN (
    SELECT unnest(public.array_distinct_concat(data_source_ids))
      FROM public.statistical_unit
     WHERE data_source_ids IS NOT NULL
  )
  AND s.active
ORDER BY s.code;

CREATE UNIQUE INDEX "data_source_used_key"
    ON public.data_source_used (code);

\echo public.legal_form_used
CREATE MATERIALIZED VIEW public.legal_form_used AS
SELECT lf.id
     , lf.code
     , lf.name
FROM public.legal_form AS lf
WHERE lf.id IN (SELECT legal_form_id FROM public.statistical_unit WHERE legal_form_id IS NOT NULL)
  AND lf.active
ORDER BY lf.id;

CREATE UNIQUE INDEX "legal_form_used_key"
    ON public.legal_form_used (code);


\echo public.country_used
CREATE MATERIALIZED VIEW public.country_used AS
SELECT c.id
     , c.iso_2
     , c.name
FROM public.country AS c
WHERE c.id IN (SELECT physical_country_id FROM public.statistical_unit WHERE physical_country_id IS NOT NULL)
  AND c.active
ORDER BY c.id;

CREATE UNIQUE INDEX "country_used_key"
    ON public.country_used (iso_2);


\echo public.statistical_unit_facet
CREATE MATERIALIZED VIEW public.statistical_unit_facet AS
SELECT valid_from
     , valid_to
     , unit_type
     , physical_region_path
     , primary_activity_category_path
     , sector_path
     , legal_form_id
     , physical_country_id
     , count(*) AS count
     , public.jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
FROM public.statistical_unit
GROUP BY valid_from
       , valid_to
       , unit_type
       , physical_region_path
       , primary_activity_category_path
       , sector_path
       , legal_form_id
       , physical_country_id
;

\echo statistical_unit_facet_valid_from
CREATE INDEX statistical_unit_facet_valid_from ON public.statistical_unit_facet(valid_from);
\echo statistical_unit_facet_valid_to
CREATE INDEX statistical_unit_facet_valid_to ON public.statistical_unit_facet(valid_to);
\echo statistical_unit_facet_unit_type
CREATE INDEX statistical_unit_facet_unit_type ON public.statistical_unit_facet(unit_type);

\echo statistical_unit_facet_physical_region_path_btree
CREATE INDEX statistical_unit_facet_physical_region_path_btree ON public.statistical_unit_facet USING BTREE (physical_region_path);
\echo statistical_unit_facet_physical_region_path_gist
CREATE INDEX statistical_unit_facet_physical_region_path_gist ON public.statistical_unit_facet USING GIST (physical_region_path);

\echo statistical_unit_facet_primary_activity_category_path_btree
CREATE INDEX statistical_unit_facet_primary_activity_category_path_btree ON public.statistical_unit_facet USING BTREE (primary_activity_category_path);
\echo statistical_unit_facet_primary_activity_category_path_gist
CREATE INDEX statistical_unit_facet_primary_activity_category_path_gist ON public.statistical_unit_facet USING GIST (primary_activity_category_path);

\echo statistical_unit_facet_sector_path_btree
CREATE INDEX statistical_unit_facet_sector_path_btree ON public.statistical_unit_facet USING BTREE (sector_path);
\echo statistical_unit_facet_sector_path_gist
CREATE INDEX statistical_unit_facet_sector_path_gist ON public.statistical_unit_facet USING GIST (sector_path);

\echo statistical_unit_facet_legal_form_id_btree
CREATE INDEX statistical_unit_facet_legal_form_id_btree ON public.statistical_unit_facet USING BTREE (legal_form_id);
\echo statistical_unit_facet_physical_country_id_btree
CREATE INDEX statistical_unit_facet_physical_country_id_btree ON public.statistical_unit_facet USING BTREE (physical_country_id);


\echo public.statistical_unit_facet_drilldown
CREATE FUNCTION public.statistical_unit_facet_drilldown(
    unit_type public.statistical_unit_type DEFAULT 'enterprise',
    region_path public.ltree DEFAULT NULL,
    activity_category_path public.ltree DEFAULT NULL,
    sector_path public.ltree DEFAULT NULL,
    legal_form_id INTEGER DEFAULT NULL,
    country_id INTEGER DEFAULT NULL,
    valid_on date DEFAULT current_date
)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.unit_type = unit_type' is always true.
    WITH params AS (
        SELECT unit_type AS param_unit_type
             , region_path AS param_region_path
             , activity_category_path AS param_activity_category_path
             , sector_path AS param_sector_path
             , legal_form_id AS param_legal_form_id
             , country_id AS param_country_id
             , valid_on AS param_valid_on
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_facet AS (
        SELECT suf.physical_region_path
             , suf.primary_activity_category_path
             , suf.sector_path
             , suf.legal_form_id
             , suf.physical_country_id
             , count
             , stats_summary
        FROM public.statistical_unit_facet AS suf
           , params
        WHERE
            suf.valid_from <= param_valid_on AND param_valid_on <= suf.valid_to
            AND (param_unit_type IS NULL OR suf.unit_type = param_unit_type)
            AND (
                param_region_path IS NULL
                OR suf.physical_region_path IS NOT NULL AND suf.physical_region_path OPERATOR(public.<@) param_region_path
            )
            AND (
                param_activity_category_path IS NULL
                OR suf.primary_activity_category_path IS NOT NULL AND suf.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
            )
            AND (
                param_sector_path IS NULL
                OR suf.sector_path IS NOT NULL AND suf.sector_path OPERATOR(public.<@) param_sector_path
            )
            AND (
                param_legal_form_id IS NULL
                OR suf.legal_form_id IS NOT NULL AND suf.legal_form_id = param_legal_form_id
            )
            AND (
                param_country_id IS NULL
                OR suf.physical_country_id IS NOT NULL AND suf.physical_country_id = param_country_id
            )
    ), available_facet_stats AS (
        SELECT COALESCE(SUM(af.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(af.stats_summary) AS stats_summary
        FROM available_facet AS af
    ),
    breadcrumb_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_facet AS suf ON suf.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_facet AS suf ON suf.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_facet AS suf ON suf.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.id
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.id
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_facet AS suf ON suf.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_facet AS suf ON suf.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT to_jsonb(source.*) FROM available_facet_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'legal_form_id',param_legal_form_id,
            'country_id',param_country_id,
            'valid_on',param_valid_on
          )
        )
    FROM params;
$$;


\echo public.history_resolution
CREATE TYPE public.history_resolution AS ENUM('year','year-month');

\echo public.statistical_history_periods
CREATE VIEW public.statistical_history_periods AS
WITH year_range AS (
  SELECT
      min(valid_from) AS start_year,
      least(max(valid_to), current_date) AS stop_year
  FROM public.statistical_unit
)
SELECT 'year'::public.history_resolution AS resolution
     , EXTRACT(YEAR FROM curr_start)::INT AS year
     , NULL::INTEGER AS month
     , (series.curr_start - interval '1 day')::DATE AS prev_stop
     , series.curr_start::DATE
     , (series.curr_start + interval '1 year' - interval '1 day')::DATE AS curr_stop
FROM year_range,
LATERAL generate_series(
    date_trunc('year', year_range.start_year)::DATE,
    date_trunc('year', year_range.stop_year)::DATE,
    interval '1 year'
) AS series(curr_start)
UNION ALL
SELECT 'year-month'::public.history_resolution AS resolution
     , EXTRACT(YEAR FROM curr_start)::INT AS year
     , EXTRACT(MONTH FROM curr_start)::INT AS month
     , (series.curr_start - interval '1 day')::DATE AS prev_stop
     , series.curr_start::DATE
     , (series.curr_start + interval '1 month' - interval '1 day')::DATE AS curr_stop
FROM year_range,
LATERAL generate_series(
    date_trunc('month', year_range.start_year)::DATE,
    date_trunc('month', year_range.stop_year)::DATE,
    interval '1 month'
) AS series(curr_start)
;


\echo public.statistical_history_def
SELECT pg_catalog.set_config('search_path', 'public', false);
CREATE VIEW public.statistical_history_def AS
WITH year_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , su_curr.unit_type AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         -- Notice that `stats` is the stats of this particular unit as recorded,
         -- while stats_summary is the aggregated stats of multiple contained units.
         -- For our tracking of changes we will only look at the base `stats` for
         -- changes, and not at the summaries, as I don't see how it makes sense
         -- to track changes in statistical summaries, but rather in the reported
         -- statistical variables, and then possibly summarise the changes.
         , su_prev.stats AS prev_stats
         , su_curr.stats AS curr_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
    WHERE range.resolution = 'year'
), year_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN public.stats_change(start_stats,stop_stats) ELSE NULL END AS stats_change
         --
    FROM year_with_unit_basis AS basis
), year_and_month_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , range.month AS month
         , su_curr.unit_type AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         , su_prev.stats AS start_stats
         , su_curr.stats AS stop_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
    WHERE range.resolution = 'year-month'
), year_and_month_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN public.stats_change(start_stats,stop_stats) ELSE NULL END AS stats_change
         --
    FROM year_and_month_with_unit_basis AS basis
), year_with_unit AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , NULL::INTEGER                           AS month
         , source.unit_type                        AS unit_type
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
         --
    FROM year_with_unit_derived AS source
    GROUP BY resolution, year, unit_type
), year_and_month_with_unit AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , source.month                            AS month
         , source.unit_type                        AS unit_type
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
         --
    FROM year_and_month_with_unit_derived AS source
    GROUP BY resolution, year, month, unit_type
)
SELECT * FROM year_with_unit
UNION ALL
SELECT * FROM year_and_month_with_unit
;

-- Reset the search path such that all things must have an explicit namespace.
SELECT pg_catalog.set_config('search_path', '', false);


\echo public.statistical_history
CREATE MATERIALIZED VIEW public.statistical_history AS
SELECT * FROM public.statistical_history_def
ORDER BY year, month;

\echo statistical_history_month_key
CREATE UNIQUE INDEX "statistical_history_month_key"
    ON public.statistical_history
    ( resolution
    , year
    , month
    , unit_type
    ) WHERE resolution = 'year-month'::public.history_resolution;
\echo statistical_history_year_key
CREATE UNIQUE INDEX "statistical_history_year_key"
    ON public.statistical_history
    ( resolution
    , year
    , unit_type
    ) WHERE resolution = 'year'::public.history_resolution;

\echo idx_history_resolution
CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
\echo idx_statistical_history_year
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
\echo idx_statistical_history_month
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
\echo idx_statistical_history_births
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
\echo idx_statistical_history_deaths
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
\echo idx_statistical_history_count
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
\echo idx_statistical_history_stats
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);


\echo public.statistical_history_facet_def
SELECT pg_catalog.set_config('search_path', 'public', false);
CREATE VIEW public.statistical_history_facet_def AS
WITH year_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , NULL::INTEGER AS month
         , su_curr.unit_type AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         , su_prev.stats AS prev_stats
         , su_curr.stats AS curr_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
    WHERE range.resolution = 'year'
), year_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN public.stats_change(start_stats,stop_stats) ELSE NULL END AS stats_change
         --
    FROM year_with_unit_basis AS basis
), year_and_month_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , range.month AS month
         , COALESCE(su_prev.unit_type, su_curr.unit_type) AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         , su_prev.stats AS prev_stats
         , su_curr.stats AS curr_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
    WHERE range.resolution = 'year-month'
), year_and_month_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN stop_stats - start_stats ELSE NULL END AS stats_change
         --
    FROM year_and_month_with_unit_basis AS basis
), year_with_unit_per_facet AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , NULL::INTEGER                           AS month
         , source.unit_type                        AS unit_type
         --
         , source.curr_primary_activity_category_path   AS primary_activity_category_path
         , source.curr_secondary_activity_category_path AS secondary_activity_category_path
         , source.curr_sector_path                      AS sector_path
         , source.curr_legal_form_id                    AS legal_form_id
         , source.curr_physical_region_path             AS physical_region_path
         , source.curr_physical_country_id              AS physical_country_id
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
    FROM year_with_unit_derived AS source
    GROUP BY resolution, year, unit_type
           , primary_activity_category_path
           , secondary_activity_category_path
           , sector_path
           , legal_form_id
           , physical_region_path
           , physical_country_id
), year_and_month_with_unit_per_facet AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , source.month                            AS month
         , source.unit_type                        AS unit_type
         --
         , source.curr_primary_activity_category_path   AS primary_activity_category_path
         , source.curr_secondary_activity_category_path AS secondary_activity_category_path
         , source.curr_sector_path                      AS sector_path
         , source.curr_legal_form_id                    AS legal_form_id
         , source.curr_physical_region_path             AS physical_region_path
         , source.curr_physical_country_id              AS physical_country_id
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
    FROM year_and_month_with_unit_derived AS source
    GROUP BY resolution, year, month, unit_type
           , primary_activity_category_path
           , secondary_activity_category_path
           , sector_path
           , legal_form_id
           , physical_region_path
           , physical_country_id
)
SELECT * FROM year_with_unit_per_facet
UNION ALL
SELECT * FROM year_and_month_with_unit_per_facet
;
SELECT pg_catalog.set_config('search_path', '', false);

\echo public.statistical_history_facet
CREATE MATERIALIZED VIEW public.statistical_history_facet AS
SELECT * FROM public.statistical_history_facet_def
ORDER BY year, month;

\echo statistical_history_facet_month_key
CREATE UNIQUE INDEX "statistical_history_facet_month_key"
    ON public.statistical_history_facet
    ( resolution
    , year
    , month
    , unit_type
    , primary_activity_category_path
    , secondary_activity_category_path
    , sector_path
    , legal_form_id
    , physical_region_path
    , physical_country_id
    ) WHERE resolution = 'year-month'::public.history_resolution;
\echo statistical_history_facet_year_key
CREATE UNIQUE INDEX "statistical_history_facet_year_key"
    ON public.statistical_history_facet
    ( year
    , month
    , unit_type
    , primary_activity_category_path
    , secondary_activity_category_path
    , sector_path
    , legal_form_id
    , physical_region_path
    , physical_country_id
    ) WHERE resolution = 'year'::public.history_resolution;

\echo idx_statistical_history_facet_year
CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
\echo idx_statistical_history_facet_month
CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
\echo idx_statistical_history_facet_births
CREATE INDEX idx_statistical_history_facet_births ON public.statistical_history_facet (births);
\echo idx_statistical_history_facet_deaths
CREATE INDEX idx_statistical_history_facet_deaths ON public.statistical_history_facet (deaths);

\echo idx_statistical_history_facet_primary_activity_category_path
CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
\echo idx_gist_statistical_history_facet_primary_activity_category_path
CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet USING GIST (primary_activity_category_path);

\echo idx_statistical_history_facet_secondary_activity_category_path
CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
\echo idx_gist_statistical_history_facet_secondary_activity_category_path
CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet USING GIST (secondary_activity_category_path);

\echo idx_statistical_history_facet_sector_path
CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
\echo idx_gist_statistical_history_facet_sector_path
CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);

\echo idx_statistical_history_facet_legal_form_id
CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);

\echo idx_statistical_history_facet_physical_region_path
CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
\echo idx_gist_statistical_history_facet_physical_region_path
CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);

\echo idx_statistical_history_facet_physical_country_id
CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
\echo idx_statistical_history_facet_count
CREATE INDEX idx_statistical_history_facet_count ON public.statistical_history_facet (count);
\echo idx_statistical_history_facet_stats_summary
CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);


\echo public.statistical_history_drilldown
CREATE FUNCTION public.statistical_history_drilldown(
    unit_type public.statistical_unit_type DEFAULT 'enterprise',
    resolution public.history_resolution DEFAULT 'year',
    year INTEGER DEFAULT NULL,
    region_path public.ltree DEFAULT NULL,
    activity_category_path public.ltree DEFAULT NULL,
    sector_path public.ltree DEFAULT NULL,
    legal_form_id INTEGER DEFAULT NULL,
    country_id INTEGER DEFAULT NULL
)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.resolution = resolution' is always true.
    WITH params AS (
        SELECT
            unit_type AS param_unit_type,
            resolution AS param_resolution,
            year AS param_year,
            region_path AS param_region_path,
            activity_category_path AS param_activity_category_path,
            sector_path AS param_sector_path,
            legal_form_id AS param_legal_form_id,
            country_id AS param_country_id
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_history AS (
        SELECT sh.*
        FROM public.statistical_history_facet AS sh
           , params
        WHERE (param_unit_type IS NULL OR sh.unit_type = param_unit_type)
          AND (param_resolution IS NULL OR sh.resolution = param_resolution)
          AND (param_year IS NULL OR sh.year = param_year)
          AND (
              param_region_path IS NULL
              OR sh.physical_region_path IS NOT NULL AND sh.physical_region_path OPERATOR(public.<@) param_region_path
              )
          AND (
              param_activity_category_path IS NULL
              OR sh.primary_activity_category_path IS NOT NULL AND sh.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
              )
          AND (
              param_sector_path IS NULL
              OR sh.sector_path IS NOT NULL AND sh.sector_path OPERATOR(public.<@) param_sector_path
              )
          AND (
              param_legal_form_id IS NULL
              OR sh.legal_form_id IS NOT NULL AND sh.legal_form_id = param_legal_form_id
              )
          AND (
              param_country_id IS NULL
              OR sh.physical_country_id IS NOT NULL AND sh.physical_country_id = param_country_id
              )
    ), available_history_stats AS (
        SELECT year, month
             , COALESCE(ah.count, 0) AS count
            --
             , COALESCE(ah.stats_summary, '{}'::JSONB) AS stats_summary
             --
             , COALESCE(ah.births, 0) AS births
             , COALESCE(ah.deaths, 0) AS deaths
             --
             , COALESCE(ah.primary_activity_category_change_count , 0) AS primary_activity_category_change_count
             , COALESCE(ah.sector_change_count                    , 0) AS sector_change_count
             , COALESCE(ah.legal_form_change_count                , 0) AS legal_form_change_count
             , COALESCE(ah.physical_region_change_count           , 0) AS physical_region_change_count
             , COALESCE(ah.physical_country_change_count          , 0) AS physical_country_change_count
             --
        FROM available_history AS ah
        ORDER BY year ASC, month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_history AS sh ON sh.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_history AS sh ON sh.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_history AS sh ON sh.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
       ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.code
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(sh.count), 0) AS count
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_history AS sh ON sh.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
        ORDER BY lf.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(sh.count), 0) AS count
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_history AS sh ON sh.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
        ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'type',param_resolution,
            'year',param_year,
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'legal_form_id',param_legal_form_id,
            'country_id',param_country_id
          )
        )
    FROM params;
$$;


\echo public.data_source_hierarchy
CREATE OR REPLACE FUNCTION public.data_source_hierarchy(data_source_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('data_source', to_jsonb(s.*)) AS data
          FROM public.data_source AS s
         WHERE data_source_id IS NOT NULL AND s.id = data_source_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.stat_for_unit_hierarchy
CREATE OR REPLACE FUNCTION public.stat_for_unit_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH ordered_data AS (
    SELECT
        to_jsonb(sfu.*)
        - 'value_int' - 'value_float' - 'value_string' - 'value_bool'
        || jsonb_build_object('stat_definition', to_jsonb(sd.*))
        || CASE sd.type
            WHEN 'int' THEN jsonb_build_object(sd.code, sfu.value_int)
            WHEN 'float' THEN jsonb_build_object(sd.code, sfu.value_float)
            WHEN 'string' THEN jsonb_build_object(sd.code, sfu.value_string)
            WHEN 'bool' THEN jsonb_build_object(sd.code, sfu.value_bool)
           END
        || (SELECT public.data_source_hierarchy(sfu.data_source_id))
        AS data
    FROM public.stat_for_unit AS sfu
    JOIN public.stat_definition AS sd ON sd.id = sfu.stat_definition_id
    WHERE (  parent_establishment_id    IS NOT NULL AND sfu.establishment_id    = parent_establishment_id
          OR parent_legal_unit_id       IS NOT NULL AND sfu.legal_unit_id       = parent_legal_unit_id
          )
      AND sfu.valid_after < valid_on AND valid_on <= sfu.valid_to
    ORDER BY sd.priority ASC NULLS LAST, sd.code
), data_list AS (
    SELECT jsonb_agg(data) AS data FROM ordered_data
)
SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('stat_for_unit',data)
    END
  FROM data_list;
$$;


\echo public.tag_for_unit_hierarchy
CREATE FUNCTION public.tag_for_unit_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  parent_enterprise_id INTEGER DEFAULT NULL,
  parent_enterprise_group_id INTEGER DEFAULT NULL
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(t.*)
        AS data
      FROM public.tag_for_unit AS tfu
      JOIN public.tag AS t ON tfu.tag_id = t.id
     WHERE (  parent_establishment_id    IS NOT NULL AND tfu.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND tfu.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND tfu.enterprise_id       = parent_enterprise_id
           OR parent_enterprise_group_id IS NOT NULL AND tfu.enterprise_group_id = parent_enterprise_group_id
           )
       ORDER BY t.path
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('tag',data)
    END
  FROM data_list;
  ;
$$;


\echo public.region_hierarchy
CREATE OR REPLACE FUNCTION public.region_hierarchy(region_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('region', to_jsonb(s.*)) AS data
          FROM public.region AS s
         WHERE region_id IS NOT NULL AND s.id = region_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

\echo public.country_hierarchy
CREATE OR REPLACE FUNCTION public.country_hierarchy(country_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('country', to_jsonb(s.*)) AS data
          FROM public.country AS s
         WHERE country_id IS NOT NULL AND s.id = country_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.location_hierarchy
CREATE OR REPLACE FUNCTION public.location_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(l.*)
        || (SELECT public.region_hierarchy(l.region_id))
        || (SELECT public.country_hierarchy(l.country_id))
        || (SELECT public.data_source_hierarchy(l.data_source_id))
        AS data
      FROM public.location AS l
     WHERE l.valid_after < valid_on AND valid_on <= l.valid_to
       AND (  parent_establishment_id IS NOT NULL AND l.establishment_id = parent_establishment_id
           OR parent_legal_unit_id    IS NOT NULL AND l.legal_unit_id    = parent_legal_unit_id
           )
       ORDER BY l.type
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('location',data)
    END
  FROM data_list;
  ;
$$;


\echo public.activity_category_standard_hierarchy
CREATE OR REPLACE FUNCTION public.activity_category_standard_hierarchy(standard_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'activity_category_standard',
                    to_jsonb(acs.*)
                ) AS data
          FROM public.activity_category_standard AS acs
         WHERE standard_id IS NOT NULL AND acs.id = standard_id
         ORDER BY acs.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.activity_category_hierarchy
CREATE OR REPLACE FUNCTION public.activity_category_hierarchy(activity_category_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
            'activity_category',
                to_jsonb(ac.*)
                || (SELECT public.activity_category_standard_hierarchy(ac.standard_id))
            )
            AS data
         FROM public.activity_category AS ac
         WHERE activity_category_id IS NOT NULL AND ac.id = activity_category_id
         ORDER BY ac.path
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.activity_hierarchy
CREATE OR REPLACE FUNCTION public.activity_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH ordered_data AS (
        SELECT to_jsonb(a.*)
               || (SELECT public.activity_category_hierarchy(a.category_id))
               || (SELECT public.data_source_hierarchy(a.data_source_id))
               AS data
          FROM public.activity AS a
         WHERE a.valid_after < valid_on AND valid_on <= a.valid_to
           AND (  parent_establishment_id IS NOT NULL AND a.establishment_id = parent_establishment_id
               OR parent_legal_unit_id    IS NOT NULL AND a.legal_unit_id    = parent_legal_unit_id
               )
           ORDER BY a.type
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('activity',data)
    END
  FROM data_list;
  ;
$$;


\echo public.sector_hierarchy
CREATE OR REPLACE FUNCTION public.sector_hierarchy(sector_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('sector', to_jsonb(s.*)) AS data
          FROM public.sector AS s
         WHERE sector_id IS NOT NULL AND s.id = sector_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.legal_form_hierarchy
CREATE OR REPLACE FUNCTION public.legal_form_hierarchy(legal_form_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('legal_form', to_jsonb(lf.*)) AS data
          FROM public.legal_form AS lf
         WHERE legal_form_id IS NOT NULL AND lf.id = legal_form_id
         ORDER BY lf.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.external_idents_hierarchy
CREATE FUNCTION public.external_idents_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  parent_enterprise_id INTEGER DEFAULT NULL,
  parent_enterprise_group_id INTEGER DEFAULT NULL
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH agg_data AS (
    SELECT jsonb_object_agg(eit.code, ei.ident ORDER BY eit.priority NULLS LAST, eit.code) AS data
     FROM public.external_ident AS ei
     JOIN public.external_ident_type AS eit ON eit.id = ei.type_id
     WHERE (  parent_establishment_id    IS NOT NULL AND ei.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND ei.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND ei.enterprise_id       = parent_enterprise_id
           OR parent_enterprise_group_id IS NOT NULL AND ei.enterprise_group_id = parent_enterprise_group_id
           )
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('external_idents',data)
    END
  FROM agg_data;
  ;
$$;


\echo public.establishment_hierarchy
CREATE OR REPLACE FUNCTION public.establishment_hierarchy(
    parent_legal_unit_id INTEGER DEFAULT NULL,
    parent_enterprise_id INTEGER DEFAULT NULL,
    valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.external_idents_hierarchy(es.id,NULL,NULL,NULL))
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.stat_for_unit_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.sector_hierarchy(es.sector_id))
        || (SELECT public.data_source_hierarchy(es.data_source_id))
        || (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL))
        AS data
    FROM public.establishment AS es
   WHERE (  (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_after < valid_on AND valid_on <= es.valid_to
   ORDER BY es.primary_for_legal_unit DESC, es.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('establishment',data)
    END
  FROM data_list;
$$;

\echo public.legal_unit_hierarchy
CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(parent_enterprise_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || (SELECT public.establishment_hierarchy(lu.id, NULL, valid_on))
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.sector_hierarchy(lu.sector_id))
        || (SELECT public.legal_form_hierarchy(lu.legal_form_id))
        || (SELECT public.data_source_hierarchy(lu.data_source_id))
        || (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL))
        AS data
    FROM public.legal_unit AS lu
   WHERE parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id
     AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
   ORDER BY lu.primary_for_enterprise DESC, lu.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('legal_unit',data)
    END
  FROM data_list;
$$;

\echo public.enterprise_hierarchy
CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || (SELECT public.legal_unit_hierarchy(en.id, valid_on))
                 || (SELECT public.establishment_hierarchy(NULL, en.id, valid_on))
                 || (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL))
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


\echo public.statistical_unit_enterprise_id
CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_after < valid_on AND valid_on <= es.valid_to
            )
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'legal_unit' THEN (
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'enterprise' THEN (
            -- The same enterprise can be returned multiple times
            -- if it has multiple legal_unit's connected, so use DISTINCT.
            SELECT DISTINCT lu.enterprise_id
              FROM public.legal_unit AS lu
             WHERE lu.enterprise_id = unit_id
               AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
         UNION ALL
            SELECT es.enterprise_id
              FROM public.establishment AS es
             WHERE es.enterprise_id = unit_id
               AND es.valid_after < valid_on AND valid_on <= es.valid_to
         )
         WHEN 'enterprise_group' THEN NULL --TODO
         END
  ;
$$;


\echo public.statistical_unit_hierarchy
CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT --jsonb_strip_nulls(
            public.enterprise_hierarchy(
              public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
              , valid_on
            )
        --)
;
$$;


CREATE FUNCTION public.relevant_statistical_units(
    unit_type public.statistical_unit_type,
    unit_id INTEGER,
    valid_on DATE DEFAULT current_date
) RETURNS SETOF public.statistical_unit LANGUAGE sql STABLE AS $$
    WITH valid_units AS (
        SELECT * FROM public.statistical_unit
        WHERE valid_after < valid_on AND valid_on <= valid_to
    ), root_unit AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'enterprise'
          AND unit_id = public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
    ), related_units AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'legal_unit'
          AND unit_id IN (SELECT unnest(legal_unit_ids) FROM root_unit)
            UNION ALL
        SELECT * FROM valid_units
        WHERE unit_type = 'establishment'
          AND unit_id IN (SELECT unnest(establishment_ids) FROM root_unit)
    ), relevant_units AS (
        SELECT * FROM root_unit
            UNION ALL
        SELECT * FROM related_units
    )
    SELECT * FROM relevant_units;
$$;


\echo public.statistical_unit_refresh_now
CREATE OR REPLACE FUNCTION public.statistical_unit_refresh_now()
RETURNS TABLE(view_name text, refresh_time_ms numeric) AS $$
DECLARE
    name text;
    start_at TIMESTAMPTZ;
    stop_at TIMESTAMPTZ;
    duration_ms numeric(18,3);
    materialized_views text[] := ARRAY
        [ 'statistical_unit'
        , 'activity_category_used'
        , 'region_used'
        , 'sector_used'
        , 'data_source_used'
        , 'legal_form_used'
        , 'country_used'
        , 'statistical_unit_facet'
        , 'statistical_history'
        , 'statistical_history_facet'
        ];
BEGIN
    FOREACH name IN ARRAY materialized_views LOOP
        SELECT clock_timestamp() INTO start_at;

        EXECUTE format('REFRESH MATERIALIZED VIEW public.%I', name);

        SELECT clock_timestamp() INTO stop_at;
        duration_ms := EXTRACT(EPOCH FROM (stop_at - start_at)) * 1000;

        -- Set the function's returning columns
        view_name := name;
        refresh_time_ms := duration_ms;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


SELECT public.statistical_unit_refresh_now();

\echo public.statistical_unit_refreshed_at
CREATE FUNCTION public.statistical_unit_refreshed_at()
RETURNS TABLE(view_name text, modified_at timestamp) AS $$
DECLARE
    path_separator char;
    materialized_view_schema text := 'public';
    materialized_view_names text[] := ARRAY
        [ 'statistical_unit'
        , 'activity_category_used'
        , 'region_used'
        , 'sector_used'
        , 'legal_form_used'
        , 'country_used'
        , 'statistical_unit_facet'
        , 'statistical_history'
        , 'statistical_history_facet'
        ];
BEGIN
    SELECT INTO path_separator
    CASE WHEN SUBSTR(setting, 1, 1) = '/' THEN '/' ELSE '\\' END
    FROM pg_settings WHERE name = 'data_directory';

    FOR view_name, modified_at IN
        SELECT
              c.relname AS view_name
            , (pg_stat_file(
                (SELECT setting FROM pg_settings WHERE name = 'data_directory')
                || path_separator || pg_relation_filepath(c.oid)
            )).modification AS modified_at
        FROM
            pg_class c
            JOIN pg_namespace ns ON c.relnamespace = ns.oid
        WHERE
            c.relkind = 'm'
            AND ns.nspname = materialized_view_schema
            AND c.relname = ANY(materialized_view_names)
    LOOP
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--SELECT public.statistical_unit_refreshed_at();


-- Ref https://stackoverflow.com/a/76356252/1023558
\echo public.websearch_to_wildcard_tsquery
CREATE FUNCTION public.websearch_to_wildcard_tsquery(query text)
RETURNS tsquery AS $$
    DECLARE
        query_splits text[];
        split text;
        new_query text := '';
    BEGIN
        SELECT regexp_split_to_array(d::text, '\s* \s*') INTO query_splits FROM pg_catalog.websearch_to_tsquery('simple', query) d;
        FOREACH split IN ARRAY query_splits LOOP
            CASE WHEN split = '|' OR split = '&' OR split = '!' OR split = '<->' OR split = '!('
                THEN new_query := new_query || split || ' ';
            ELSE new_query := new_query || split || ':* ';
            END CASE;
        END LOOP;
        RETURN to_tsquery('simple', new_query);
    END;
$$ LANGUAGE plpgsql;
--


\echo public.generate_mermaid_er_diagram
/*
  Function: public.generate_mermaid_er_diagram()
  Purpose: Generates a Mermaid syntax ER diagram representing the schema of the database.

  Description:
  This function constructs a textual representation of the database schema using the Mermaid ER diagram syntax.
  It lists tables with their columns and types and describes the relationships between tables through foreign keys.

  Relationship Notation:
  - The relationships are represented with the following cardinality symbols:
    - Left-hand side (from the perspective of the right entity):
      - "||": Exactly one
      - "|o": Zero or one
      - "}o": Zero or more (no upper limit)
      - "}|": One or more (no upper limit)
    - Right-hand side (from the perspective of the left entity):
      - "||": Exactly one
      - "o|": One or more (no upper limit)
      - "o{": Zero or more (no upper limit)
      - "|{": One or more (no upper limit)

  Cardinality Representation:
  - The notation is interpreted based on the perspective of the entities:
    - For "EntityA ||--o{ EntityB":
      - From EntityB to EntityA:
        - Each instance of EntityB must be associated with exactly one instance of EntityA ("||" on EntityA side).
      - From EntityA to EntityB:
        - Each instance of EntityA can be associated with zero or more instances of EntityB ("o{" on EntityB side).

  This interpretation is consistent with the Mermaid syntax rules, ensuring that the generated diagram accurately reflects
  the database schema's relationships and constraints.

  Usage:
  This function can be used to visualize the structure of the database schema, making it easier to understand the
  relationships and cardinalities between different tables.

  Note: The output is a text-based ER diagram in Mermaid syntax, which can be rendered using Mermaid-compatible tools to produce a visual representation of the schema.
*/
CREATE OR REPLACE FUNCTION public.generate_mermaid_er_diagram()
RETURNS text AS $$
DECLARE
    rec RECORD;
    result text := 'erDiagram';
BEGIN
    -- First part of the query (tables and columns)
    result := result || E'\n\t%% Entities (derived from tables)';
    FOR rec IN
        SELECT format(E'\t%s["%s"] {\n%s\n\t}',
            -- Include the schema and a underscore if different than 'public' for the source table
            -- since period is not valid syntax for an entity name.
            CASE WHEN n.nspname <> 'public'
                 THEN n.nspname || '_' || c.relname
                 ELSE c.relname
            END,
            -- Provide the correct name with period as the label.
            CASE WHEN n.nspname <> 'public'
                 THEN n.nspname || '.' || c.relname
                 ELSE c.relname
            END,
            -- Notice that mermaid uses the "attribute_type attribute_name" pattern
            -- and that if there are spaces there must be double quoting.
            string_agg(format(E'\t\t"%s" %s',
                format_type(t.oid, a.atttypmod),
                a.attname
            ), E'\n' ORDER BY a.attnum)
        )
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute a ON c.oid = a.attrelid AND a.attnum > 0 AND NOT a.attisdropped
        LEFT JOIN pg_type t ON a.atttypid = t.oid
        WHERE c.relkind IN ('r', 'p')
          AND NOT c.relispartition
          AND n.nspname !~ '^pg_'
          AND n.nspname !~ '^_'
          AND n.nspname <> 'information_schema'
        GROUP BY n.nspname, c.relname
        ORDER BY n.nspname, c.relname
    LOOP
        result := result || E'\n' || rec.format;
    END LOOP;

    -- Second part of the query (foreign key constraints)
    result := result || E'\n\t%% Relationships (derived from foreign keys)';
    -- Documentation of relationship syntax from https://mermaid.js.org/syntax/entityRelationshipDiagram.html#relationship-syntax
    -- In particular:
    --     Value (left)    Value (right)   Meaning
    --     |o              o|              Zero or one
    --     ||              ||              Exactly one
    --     }o              o{              Zero or more (no upper limit)
    --     }|              |{              One or more (no upper limit)
    FOR rec IN
        SELECT format(E'\t%s %s--%s %s : %s',
            -- Include the schema and a underscore if different than 'public' for the source table
            -- since period is not valid syntax for an entity name.
            CASE WHEN n1.nspname <> 'public'
                 THEN n1.nspname || '_' || c1.relname
                 ELSE c1.relname
            END,
            -- The relationship cardinality from the referenced table (target) towards the referencing table (source).
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM pg_constraint con
                    WHERE con.conrelid = c.confrelid
                    AND con.conkey = c.conkey
                    AND con.contype IN ('p', 'u')
                )
                THEN '}|' -- Every instance in the target can have one or more instances in the source
                ELSE '}o' -- Every instance in the target can have zero or more instances in the source
            END,
            -- The relationship cardinality from the referencing table (source) towards the referenced table (target).
            CASE
                WHEN a.attnotnull THEN '||' -- Every instance in the source must reference exactly one instance in the target
                ELSE 'o|'                   -- Every instance in the source may reference zero or one instance in the target
            END,
            -- Include the schema and a period if different than 'public' for the target table
            CASE WHEN n2.nspname <> 'public'
                 THEN n2.nspname || '.' || c2.relname
                 ELSE c2.relname
            END,
            c.conname
        )
        FROM pg_constraint c
        JOIN pg_class c1 ON c.conrelid = c1.oid AND c.contype = 'f'
        JOIN pg_class c2 ON c.confrelid = c2.oid
        JOIN pg_namespace n1 ON n1.oid = c1.relnamespace
        JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
        JOIN pg_attribute a ON a.attnum = ANY (c.conkey) AND a.attrelid = c.conrelid
        WHERE NOT c1.relispartition
          AND NOT c2.relispartition
          AND n1.nspname !~ '^pg_'
          AND n1.nspname !~ '^_'
          AND n1.nspname <> 'information_schema'
          AND n2.nspname !~ '^pg_'
          AND n2.nspname !~ '^_'
          AND n2.nspname <> 'information_schema'
        ORDER BY n1.nspname, c1.relname, n2.nspname, c2.relname
    LOOP
        result := result || E'\n' || rec.format;
    END LOOP;

    RETURN result;
END;
$$ LANGUAGE plpgsql;


\echo public.sector_custom_only
CREATE VIEW public.sector_custom_only(path, name, description)
WITH (security_invoker=on) AS
SELECT ac.path
     , ac.name
     , ac.description
FROM public.sector AS ac
WHERE ac.active
  AND ac.custom
ORDER BY path;

\echo admin.sector_custom_only_upsert
CREATE FUNCTION admin.sector_custom_only_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    maybe_parent_id int := NULL;
    row RECORD;
BEGIN
    -- Find parent sector based on NEW.path
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.sector
         WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND active
           AND custom;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    -- Perform an upsert operation on public.sector
    BEGIN
        INSERT INTO public.sector
            ( path
            , parent_id
            , name
            , description
            , updated_at
            , active
            , custom
            )
        VALUES
            ( NEW.path
            , maybe_parent_id
            , NEW.name
            , NEW.description
            , statement_timestamp()
            , TRUE -- Active
            , TRUE -- Custom
            )
        ON CONFLICT (path, active, custom)
        DO UPDATE SET
                parent_id = maybe_parent_id
              , name = NEW.name
              , description = NEW.description
              , updated_at = statement_timestamp()
              , active = TRUE
              , custom = TRUE
           RETURNING * INTO row;

        -- Log the upserted row
        RAISE DEBUG 'UPSERTED %', to_json(row);

    EXCEPTION WHEN unique_violation THEN
        DECLARE
            code varchar := regexp_replace(regexp_replace(NEW.path::TEXT, '[^0-9]', '', 'g'),'^([0-9]{2})(.+)$','\1.\2','');
            data JSONB := to_jsonb(NEW);
        BEGIN
           data := jsonb_set(data, '{code}', code::jsonb, true);
            RAISE EXCEPTION '% for row %', SQLERRM, data
                USING
                DETAIL = 'Failed during UPSERT operation',
                HINT = 'Check for path derived numeric code violations';
        END;
    END;

    RETURN NULL;
END;
$$;


CREATE TRIGGER sector_custom_only_upsert
INSTEAD OF INSERT ON public.sector_custom_only
FOR EACH ROW
EXECUTE FUNCTION admin.sector_custom_only_upsert();


\echo admin.sector_custom_only_prepare
CREATE OR REPLACE FUNCTION admin.sector_custom_only_prepare()
RETURNS TRIGGER AS $$
BEGIN
    -- Deactivate all non-custom sector entries before insertion
    UPDATE public.sector
       SET active = false
     WHERE active = true
       AND custom = false;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sector_custom_only_prepare_trigger
BEFORE INSERT ON public.sector_custom_only
FOR EACH STATEMENT
EXECUTE FUNCTION admin.sector_custom_only_prepare();


\echo public.legal_form_custom_only
CREATE VIEW public.legal_form_custom_only(code, name)
WITH (security_invoker=on) AS
SELECT ac.code
     , ac.name
FROM public.legal_form AS ac
WHERE ac.active
  AND ac.custom
ORDER BY code;

\echo admin.legal_form_custom_only_upsert
CREATE FUNCTION admin.legal_form_custom_only_upsert()
RETURNS TRIGGER AS $$
DECLARE
    row RECORD;
BEGIN
    -- Perform an upsert operation on public.legal_form
    INSERT INTO public.legal_form
        ( code
        , name
        , updated_at
        , active
        , custom
        )
    VALUES
        ( NEW.code
        , NEW.name
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (code, active, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , active = TRUE
          , custom = TRUE
       WHERE legal_form.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER legal_form_custom_only_upsert
INSTEAD OF INSERT ON public.legal_form_custom_only
FOR EACH ROW
EXECUTE FUNCTION admin.legal_form_custom_only_upsert();


\echo admin.legal_form_custom_only_prepare
CREATE OR REPLACE FUNCTION admin.legal_form_custom_only_prepare()
RETURNS TRIGGER AS $$
BEGIN
    -- Deactivate all non-custom legal_form entries before insertion
    UPDATE public.legal_form
       SET active = false
     WHERE active = true
       AND custom = false;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER legal_form_custom_only_prepare_trigger
BEFORE INSERT ON public.legal_form_custom_only
FOR EACH STATEMENT
EXECUTE FUNCTION admin.legal_form_custom_only_prepare();


-- Load seed data after all constraints are in place
SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.sector');
SET LOCAL client_min_messages TO INFO;

\copy public.sector_system(path, name) FROM 'dbseed/sector.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.legal_form');
SET LOCAL client_min_messages TO INFO;

\copy public.legal_form_system(code, name) FROM 'dbseed/legal_form.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.reorg_type');
SET LOCAL client_min_messages TO INFO;

\copy public.reorg_type_system(code, name, description) FROM 'dbseed/reorg_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.foreign_participation');
SET LOCAL client_min_messages TO INFO;

\copy public.foreign_participation_system(code, name) FROM 'dbseed/foreign_participation.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.data_source');
SET LOCAL client_min_messages TO INFO;

\copy public.data_source_system(code, name) FROM 'dbseed/data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.unit_size');
SET LOCAL client_min_messages TO INFO;

\copy public.unit_size_system(code, name) FROM 'dbseed/unit_size.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.person_type');
SET LOCAL client_min_messages TO INFO;

\copy public.person_type_system(code, name) FROM 'dbseed/person_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_type');
SET LOCAL client_min_messages TO INFO;

\copy public.enterprise_group_type_system(code, name) FROM 'dbseed/enterprise_group_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_role');
SET LOCAL client_min_messages TO INFO;

\copy public.enterprise_group_role_system(code, name) FROM 'dbseed/enterprise_group_role.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


-- TODO Later: Move to sql_saga
CREATE TYPE admin.existing_upsert_case AS ENUM
    -- n is NEW
    -- e is existing
    -- e_t is new tail to existing
    -- Used to merge to avoid multiple rows
    ( 'existing_adjacent_valid_from'
    -- [--e--]
    --        [--n--]
    -- IF equivalent THEN delete(e) AND n.valid_from = e.valid.from
    -- [---------n--]
    , 'existing_adjacent_valid_to'
    --        [--e--]
    -- [--n--]
    -- IFF equivalent THEN delete(e) AND n.valid_to = e.valid_to
    -- [--n---------]
    -- Used to adjust the valid_from/valid_to to carve out room for new data.
    , 'existing_overlaps_valid_from'
    --    [---e---]
    --         [----n----]
    -- IFF equivalent THEN delete(e) AND n.valid_from = e.valid_from
    --    [---------n----]
    -- ELSE e.valid_to = n.valid_from - '1 day'
    --    [-e-]
    --         [----n----]
    , 'inside_existing'
    -- [---------e--------]
    --        [--n--]
    -- IFF equivalent THEN delete(e) AND n.valid_from = e.valid_from AND n.valid_to = e.valid_to
    -- [---------n--------]
    -- ELSE IF NOT n.active THEN e.valid_to = n.valid_from - '1 day'
    -- [--e--]
    --        [--n--]
    -- ELSE e.valid_to = n.valid_from - '1 day', e_t.valid_from = n.valid_to + '1 day', e_t.valid_to = e.valid_to
    -- [--e--]       [-e_t-]
    --        [--n--]
    , 'contains_existing'
    --          [-e-]
    --       [----n----]
    -- THEN delete(e)
    --       [----n----]
    , 'existing_overlaps_valid_to'
    --        [----e----]
    --    [----n----]
    -- IFF equivalent THEN delete(e) AND n.valid_to = e.valid_to
    --    [----n--------]
    -- ELSE IF NOT n.active
    --    [----n----]
    -- ELSE e.valid_from = n.valid_to + '1 day'
    --               [-e-]
    --    [----n----]
    );
-- The n.active dependent logic is not implemented, because It's not clear to me
-- that that you insert should modify things outside the specified timeline.

-- TODO Later: CREATE FUNCTION sql_saga.api_upsert(NEW record, ...)

\echo admin.upsert_generic_valid_time_table
CREATE FUNCTION admin.upsert_generic_valid_time_table
    ( schema_name text
    , table_name text
    , unique_columns jsonb
    , temporal_columns text[]
    , ephemeral_columns text[]
    , NEW RECORD
    )
RETURNS INTEGER AS $upsert_generic_valid_time_table$
DECLARE
  existing_id integer := NEW.id;
  existing RECORD;
  result RECORD;
  existing_data jsonb;
  new_data jsonb;
  new_base_data jsonb;
  adjusted_valid_from date;
  adjusted_valid_to date;
  equivalent_data jsonb;
  equivalent_clause text;
  identifying_clause text;
  existing_query text;
  delete_existing_sql text;
  identifying_query text;
  generated_columns text[];
  generated_columns_sql CONSTANT text :=
      'SELECT array_agg(a.attname) '
      'FROM pg_catalog.pg_attribute AS a '
      'WHERE a.attrelid = $1 '
      '  AND a.attnum > 0 '
      '  AND NOT a.attisdropped '
      '  AND (pg_catalog.pg_get_serial_sequence(a.attrelid::regclass::text, a.attname) IS NOT NULL '
      '    OR a.attidentity <> '''' '
      '    OR a.attgenerated <> '''' '
      '    OR EXISTS (SELECT FROM pg_catalog.pg_constraint AS _c '
      '               WHERE _c.conrelid = a.attrelid '
      '                 AND _c.contype = ''p'' '
      '                 AND _c.conkey @> ARRAY[a.attnum]) '
      '              )';
BEGIN
  new_data := to_jsonb(NEW);
  -- Loop through each conflicting row
  RAISE DEBUG 'UPSERT row %', new_data;
  -- Remove fields that are generated by the database,
  -- since we don't wish to override them with NULL
  -- and get a constraint error.
  EXECUTE generated_columns_sql INTO generated_columns USING (schema_name||'.'||table_name)::regclass;

  new_base_data := new_data - generated_columns;
  -- The equivalent data is the data that makes up the equivalent, and
  -- is the basis for considering it equal to another row, and thus
  -- no historic versioning is required.
  -- Ephemeral columns are used for internal delete tracking, and are non temporal,
  -- and the temporal columns themselves are not part of the value.
  equivalent_data := new_base_data - ephemeral_columns - temporal_columns;

  SELECT string_agg(' '||quote_ident(key)||' IS NOT DISTINCT FROM $1.'||quote_ident(key)||' ', ' AND ')
  INTO equivalent_clause
  FROM jsonb_each_text(equivalent_data);

  IF NEW.id IS NULL THEN
      SELECT
        string_agg(
            CASE jsonb_typeof(unique_column)
            WHEN 'array' THEN
                    '(' || (SELECT string_agg(' '||element||'= $1.'||element||' ', ' AND ') FROM jsonb_array_elements_text(unique_column) AS element) || ')'
            WHEN 'string' THEN ' '||unique_column::text||'= $1.'||unique_column::text||' '
            ELSE NULL
            END,
            ' OR '
        ) INTO identifying_clause
      FROM (SELECT jsonb_array_elements(unique_columns) AS unique_column) AS subquery;

      identifying_query := format($$
          SELECT id
          FROM %1$I.%2$I
          WHERE %3$s
          LIMIT 1;$$
          , schema_name
          , table_name
          , identifying_clause
        );
      RAISE DEBUG 'identifying_query %', identifying_query;

      EXECUTE identifying_query INTO existing_id USING NEW;
      RAISE DEBUG 'existing_id %', existing_id;
      NEW.id = existing_id;
  END IF;

  existing_query := format($$
      SELECT *
           , (%3$s) AS equivalent
           , CASE
             WHEN valid_to = ($1.valid_from - '1 day'::INTERVAL) THEN 'existing_adjacent_valid_from'
             WHEN valid_from = ($1.valid_to + '1 day'::INTERVAL) THEN 'existing_adjacent_valid_to'
             WHEN valid_from <  $1.valid_from AND valid_to <= $1.valid_to THEN 'existing_overlaps_valid_from'
             WHEN valid_from <  $1.valid_from AND valid_to >  $1.valid_to THEN 'inside_existing'
             WHEN valid_from >= $1.valid_from AND valid_to <= $1.valid_to THEN 'contains_existing'
             WHEN valid_from >= $1.valid_from AND valid_to >  $1.valid_to THEN 'existing_overlaps_valid_to'
             END::admin.existing_upsert_case AS upsert_case
      FROM %1$I.%2$I
      WHERE daterange(valid_from, valid_to, '[]') && daterange(($1.valid_from - '1 day'::INTERVAL)::DATE, ($1.valid_to + '1 day'::INTERVAL)::DATE, '[]')
        AND id = $2
      ORDER BY valid_from$$
      , schema_name
      , table_name
      , equivalent_clause
    );
  --RAISE DEBUG 'existing_query %', existing_query;

  FOR existing IN EXECUTE existing_query USING NEW, existing_id
  LOOP
      existing_data := to_jsonb(existing);
      RAISE DEBUG 'EXISTING row %', existing_data;

      delete_existing_sql := format($$
       DELETE FROM %1$I.%2$I
        WHERE id = $1
          AND valid_from = $2
          AND valid_to = $3;
      $$, schema_name, table_name);

      CASE existing.upsert_case
      WHEN 'existing_adjacent_valid_from' THEN
        IF existing.equivalent THEN
          RAISE DEBUG 'Upsert Case: existing_adjacent_valid_from AND equivalent';
          RAISE DEBUG 'DELETE EXISTING';
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          NEW.valid_from := existing.valid_from;
        END IF;
      WHEN 'existing_adjacent_valid_to' THEN
        IF existing.equivalent THEN
          RAISE DEBUG 'Upsert Case: existing_adjacent_valid_to AND equivalent';
          RAISE DEBUG 'DELETE EXISTING';
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          NEW.valid_to := existing.valid_to;
        END IF;
      WHEN 'existing_overlaps_valid_from' THEN
        IF existing.equivalent THEN
          RAISE DEBUG 'Upsert Case: existing_overlaps_valid_from AND equivalent';
          RAISE DEBUG 'DELETE EXISTING';
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          NEW.valid_from := existing.valid_from;
        ELSE
          RAISE DEBUG 'Upsert Case: existing_overlaps_valid_from AND different';
          adjusted_valid_to := NEW.valid_from - interval '1 day';
          RAISE DEBUG 'adjusted_valid_to = %', adjusted_valid_to;
          IF adjusted_valid_to <= existing.valid_from THEN
            RAISE DEBUG 'DELETE EXISTING with zero valid duration %.%(id=%)', schema_name, table_name, existing.id;
            EXECUTE EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          ELSE
            RAISE DEBUG 'Adjusting existing row %.%(id=%)', schema_name, table_name, existing.id;
            EXECUTE format($$
                UPDATE %1$I.%2$I
                SET valid_to = $1
                WHERE
                  id = $2
                  AND valid_from = $3
                  AND valid_to = $4
              $$, schema_name, table_name) USING adjusted_valid_to, existing.id, existing.valid_from, existing.valid_to;
          END IF;
        END IF;
      WHEN 'inside_existing' THEN
        IF existing.equivalent THEN
          RAISE DEBUG 'Upsert Case: inside_existing AND equivalent';
          RAISE DEBUG 'DELETE EXISTING';
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          NEW.valid_from := existing.valid_from;
          NEW.valid_to := existing.valid_to;
        ELSE
          RAISE DEBUG 'Upsert Case: inside_existing AND different';
          adjusted_valid_from := NEW.valid_to + interval '1 day';
          adjusted_valid_to := NEW.valid_from - interval '1 day';
          RAISE DEBUG 'adjusted_valid_from = %', adjusted_valid_from;
          RAISE DEBUG 'adjusted_valid_to = %', adjusted_valid_to;
          IF adjusted_valid_to <= existing.valid_from THEN
            RAISE DEBUG 'Deleting existing with zero valid duration %.%(id=%)', schema_name, table_name, existing.id;
            RAISE DEBUG 'DELETE EXISTING';
            EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          ELSE
            RAISE DEBUG 'ADJUSTING EXISTING row %.%(id=%)', schema_name, table_name, existing.id;
            EXECUTE format($$
                UPDATE %1$I.%2$I
                SET valid_to = $1
                WHERE
                  id = $2
                  AND valid_from = $3
                  AND valid_to = $4
              $$, schema_name, table_name) USING adjusted_valid_to, existing.id, existing.valid_from, existing.valid_to;
          END IF;
          IF existing.valid_to < adjusted_valid_from THEN
            RAISE DEBUG 'Don''t create zero duration row';
          ELSE
            existing.valid_from := adjusted_valid_from;
            existing_data := to_jsonb(existing);
            new_base_data := existing_data - generated_columns;
            RAISE DEBUG 'Inserting new tail %', new_base_data;
            EXECUTE format('INSERT INTO %1$I.%2$I(%3$s) VALUES (%4$s)', schema_name, table_name,
              (SELECT string_agg(quote_ident(key), ', ' ORDER BY key) FROM jsonb_each_text(new_base_data)),
              (SELECT string_agg(quote_nullable(value), ', ' ORDER BY key) FROM jsonb_each_text(new_base_data)));
          END IF;
        END IF;
      WHEN 'contains_existing' THEN
          RAISE DEBUG 'Upsert Case: contains_existing';
          RAISE DEBUG 'DELETE EXISTING contained by NEW %.%(id=%)', schema_name, table_name, existing.id;
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
      WHEN 'existing_overlaps_valid_to' THEN
        IF existing.equivalent THEN
          RAISE DEBUG 'Upsert Case: existing_overlaps_valid_to AND equivalent';
          RAISE DEBUG 'DELETE EXISTING';
          EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          NEW.valid_to := existing.valid_to;
        ELSE
          RAISE DEBUG 'Upsert Case: existing_overlaps_valid_to AND different';
          adjusted_valid_from := NEW.valid_to + interval '1 day';
          RAISE DEBUG 'adjusted_valid_from = %', adjusted_valid_from;
          IF existing.valid_to < adjusted_valid_from THEN
              RAISE DEBUG 'DELETE EXISTING with zero valid duration %.%(id=%)', schema_name, table_name, existing.id;
              EXECUTE delete_existing_sql USING existing.id, existing.valid_from, existing.valid_to;
          ELSE
            RAISE DEBUG 'Adjusting existing row %.%(id=%)', schema_name, table_name, existing.id;
            EXECUTE format($$
                UPDATE %1$I.%2$I
                SET valid_from = $1
                WHERE
                  id = $2
                  AND valid_from = $3
                  AND valid_to = $4
              $$, schema_name, table_name) USING adjusted_valid_from, existing.id, existing.valid_from, existing.valid_to;
          END IF;
        END IF;
      ELSE
        RAISE EXCEPTION 'Unknown existing_upsert_case: %', existing.upsert_case;
      END CASE;
    END LOOP;
  --
  -- Insert a new entry
  -- If there was any existing row, then reuse that same id
  new_base_data := to_jsonb(NEW) - generated_columns;
  -- The id is a generated row, so add it back again after removal.
  IF existing_id IS NOT NULL THEN
    new_base_data := jsonb_set(new_base_data, '{id}', existing_id::text::jsonb, true);
  END IF;

  RAISE DEBUG 'INSERT %.%(%)', schema_name, table_name, new_base_data;
  EXECUTE format('INSERT INTO %1$I.%2$I(%3$s) VALUES (%4$s) RETURNING *', schema_name, table_name,
    (SELECT string_agg(quote_ident(key), ', ' ORDER BY key) FROM jsonb_each_text(new_base_data)),
    (SELECT string_agg(quote_nullable(value), ', ' ORDER BY key) FROM jsonb_each_text(new_base_data)))
  INTO result;
  RETURN result.id;
END;
$upsert_generic_valid_time_table$ LANGUAGE plpgsql;




-- View for current information about a legal unit.
\echo public.legal_unit_era
CREATE VIEW public.legal_unit_era
WITH (security_invoker=on) AS
SELECT *
FROM public.legal_unit
  ;

\echo admin.legal_unit_era_upsert
CREATE FUNCTION admin.legal_unit_era_upsert()
RETURNS TRIGGER AS $legal_unit_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'legal_unit';
  unique_columns jsonb :=
    jsonb_build_array(
            'id'
        );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::TEXT[];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$legal_unit_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER legal_unit_era_upsert
INSTEAD OF INSERT ON public.legal_unit_era
FOR EACH ROW
EXECUTE FUNCTION admin.legal_unit_era_upsert();


-- View for current information about a legal unit.
\echo public.establishment_era
CREATE VIEW public.establishment_era
WITH (security_invoker=on) AS
SELECT *
FROM public.establishment
  ;

\echo admin.establishment_era_upsert
CREATE FUNCTION admin.establishment_era_upsert()
RETURNS TRIGGER AS $establishment_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'establishment';
  unique_columns jsonb :=
    jsonb_build_array(
            'id'
        );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::TEXT[];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$establishment_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER establishment_era_upsert
INSTEAD OF INSERT ON public.establishment_era
FOR EACH ROW
EXECUTE FUNCTION admin.establishment_era_upsert();


-- View for current information about a location.
\echo public.location_era
CREATE VIEW public.location_era
WITH (security_invoker=on) AS
SELECT *
FROM public.location;

\echo admin.location_era_upsert
CREATE FUNCTION admin.location_era_upsert()
RETURNS TRIGGER AS $location_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'location';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('type', 'establishment_id'),
    jsonb_build_array('type', 'legal_unit_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::text[];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$location_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER location_era_upsert
INSTEAD OF INSERT ON public.location_era
FOR EACH ROW
EXECUTE FUNCTION admin.location_era_upsert();


-- View for current information about a activity.
\echo public.activity_era
CREATE VIEW public.activity_era
WITH (security_invoker=on) AS
SELECT *
FROM public.activity;

\echo admin.activity_era_upsert
CREATE FUNCTION admin.activity_era_upsert()
RETURNS TRIGGER AS $activity_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'activity';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('type', 'establishment_id'),
    jsonb_build_array('type', 'legal_unit_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY['updated_at'];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$activity_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER activity_era_upsert
INSTEAD OF INSERT ON public.activity_era
FOR EACH ROW
EXECUTE FUNCTION admin.activity_era_upsert();


\echo public.stat_for_unit_era
CREATE VIEW public.stat_for_unit_era
WITH (security_invoker=on) AS
SELECT *
FROM public.stat_for_unit;

\echo admin.stat_for_unit_era_upsert
CREATE FUNCTION admin.stat_for_unit_era_upsert()
RETURNS TRIGGER AS $stat_for_unit_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'stat_for_unit';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('stat_definition_id', 'establishment_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::text[];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$stat_for_unit_era_upsert$ LANGUAGE plpgsql;

\echo stat_for_unit_era_upsert
CREATE TRIGGER stat_for_unit_era_upsert
INSTEAD OF INSERT ON public.stat_for_unit_era
FOR EACH ROW
EXECUTE FUNCTION admin.stat_for_unit_era_upsert();


---- Create function for deleting stale countries
--CREATE FUNCTION admin.delete_stale_legal_unit_era()
--RETURNS TRIGGER AS $$
--BEGIN
--    DELETE FROM public.region
--    WHERE updated_at < statement_timestamp() AND active = false;
--    RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;

--CREATE TRIGGER delete_stale_legal_unit_era
--AFTER INSERT ON public.legal_unit_era
--FOR EACH STATEMENT
--EXECUTE FUNCTION admin.delete_stale_legal_unit_era();


-- ========================================================
-- BEGIN:  Helper functions for import
-- ========================================================

\echo admin.import_lookup_tag
CREATE FUNCTION admin.import_lookup_tag(
    new_jsonb JSONB,
    OUT tag_id INTEGER
) RETURNS INTEGER AS $$
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
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_country
CREATE FUNCTION admin.import_lookup_country(
    new_jsonb JSONB,
    country_type TEXT,
    OUT country_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    country_iso_2_field TEXT;
    country_iso_2 TEXT;
BEGIN
    -- Check that country_type is valid and determine the fields
    IF country_type NOT IN ('physical', 'postal') THEN
        RAISE EXCEPTION 'Invalid country_type: %', country_type;
    END IF;

    country_iso_2_field := country_type || '_country_iso_2';

    -- Get the value of the country ISO 2 field from the JSONB parameter
    country_iso_2 := new_jsonb ->> country_iso_2_field;

    -- Check if country_iso_2 is not null and not empty
    IF country_iso_2 IS NOT NULL AND country_iso_2 <> '' THEN
        SELECT country.id INTO country_id
        FROM public.country
        WHERE iso_2 = country_iso_2;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find % for row %', country_iso_2_field, new_jsonb;
            updated_invalid_codes := updated_invalid_codes || jsonb_build_object(country_iso_2_field, country_iso_2);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_region
CREATE FUNCTION admin.import_lookup_region(
    IN new_jsonb JSONB,
    IN region_type TEXT,
    OUT region_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    region_code_field TEXT;
    region_path_field TEXT;
    region_code TEXT;
    region_path_str TEXT;
    region_path public.LTREE;
BEGIN
    -- Check that region_type is valid and determine the fields
    IF region_type NOT IN ('physical', 'postal') THEN
        RAISE EXCEPTION 'Invalid region_type: %', region_type;
    END IF;

    region_code_field := region_type || '_region_code';
    region_path_field := region_type || '_region_path';

    -- Get the values of the region code and path fields from the JSONB parameter
    region_code := new_jsonb ->> region_code_field;
    region_path_str := new_jsonb ->> region_path_field;

    -- Check if both region_code and region_path are specified
    IF region_code IS NOT NULL AND region_code <> '' AND
       region_path_str IS NOT NULL AND region_path_str <> '' THEN
        RAISE EXCEPTION 'Only one of % or % can be specified for row %', region_code_field, region_path_field, new_jsonb;
    ELSE
        IF region_code IS NOT NULL AND region_code <> '' THEN
            SELECT id INTO region_id
            FROM public.region
            WHERE code = region_code;

            IF NOT FOUND THEN
                RAISE WARNING 'Could not find % for row %', region_code_field, new_jsonb;
                updated_invalid_codes := updated_invalid_codes || jsonb_build_object(region_code_field, region_code);
            END IF;
        ELSIF region_path_str IS NOT NULL AND region_path_str <> '' THEN
            BEGIN
                region_path := region_path_str::public.LTREE;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Invalid % for row % with error "%"', region_path_field, new_jsonb, SQLERRM;
            END;

            SELECT id INTO region_id
            FROM public.region
            WHERE path = region_path;

            IF NOT FOUND THEN
                RAISE WARNING 'Could not find % for row %', region_path_field, new_jsonb;
                updated_invalid_codes := updated_invalid_codes || jsonb_build_object(region_path_field, region_path);
            END IF;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_activity_category
CREATE FUNCTION admin.import_lookup_activity_category(
    new_jsonb JSONB,
    category_type TEXT,
    OUT activity_category_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    category_code_field TEXT;
    category_code TEXT;
BEGIN
    IF category_type NOT IN ('primary', 'secondary') THEN
        RAISE EXCEPTION 'Invalid category_type: %', category_type;
    END IF;

    category_code_field := category_type || '_activity_category_code';

    -- Get the value of the category code field from the JSONB parameter
    category_code := new_jsonb ->> category_code_field;

    -- Check if category_code is not null and not empty
    IF category_code IS NOT NULL AND category_code <> '' THEN
        SELECT id INTO activity_category_id
        FROM public.activity_category_available
        WHERE code = category_code;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find % for row %', category_code_field, new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, ARRAY[category_code_field], to_jsonb(category_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_sector
CREATE FUNCTION admin.import_lookup_sector(
    new_jsonb JSONB,
    OUT sector_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    sector_code TEXT;
BEGIN
    -- Get the value of the sector_code field from the JSONB parameter
    sector_code := new_jsonb ->> 'sector_code';

    -- Check if sector_code is not null and not empty
    IF sector_code IS NOT NULL AND sector_code <> '' THEN
        SELECT id INTO sector_id
        FROM public.sector
        WHERE code = sector_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find sector_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{sector_code}', to_jsonb(sector_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_data_source
CREATE FUNCTION admin.import_lookup_data_source(
    new_jsonb JSONB,
    OUT data_source_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    data_source_code TEXT;
BEGIN
    -- Get the value of the data_source_code field from the JSONB parameter
    data_source_code := new_jsonb ->> 'data_source_code';

    -- Check if data_source_code is not null and not empty
    IF data_source_code IS NOT NULL AND data_source_code <> '' THEN
        SELECT id INTO data_source_id
        FROM public.data_source
        WHERE code = data_source_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find data_source_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{data_source_code}', to_jsonb(data_source_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.import_lookup_legal_form
CREATE FUNCTION admin.import_lookup_legal_form(
    new_jsonb JSONB,
    OUT legal_form_id INTEGER,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    legal_form_code TEXT;
BEGIN
    -- Get the value of the legal_form_code field from the JSONB parameter
    legal_form_code := new_jsonb ->> 'legal_form_code';

    -- Check if legal_form_code is not null and not empty
    IF legal_form_code IS NOT NULL AND legal_form_code <> '' THEN
        SELECT id INTO legal_form_id
        FROM public.legal_form
        WHERE code = legal_form_code
          AND active;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not find legal_form_code for row %', new_jsonb;
            updated_invalid_codes := jsonb_set(updated_invalid_codes, '{legal_form_code}', to_jsonb(legal_form_code), true);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.type_date_field
CREATE FUNCTION admin.type_date_field(
    IN new_jsonb JSONB,
    IN field_name TEXT,
    OUT date_value DATE,
    INOUT updated_invalid_codes JSONB
) RETURNS RECORD AS $$
DECLARE
    date_str TEXT;
    invalid_code JSONB;
BEGIN
    date_str := new_jsonb ->> field_name;

    IF date_str IS NOT NULL AND date_str <> '' THEN
        BEGIN
            date_value := date_str::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            invalid_code := jsonb_build_object(field_name, date_str);
            updated_invalid_codes := updated_invalid_codes || invalid_code;
        END;
    END IF;
END;
$$ LANGUAGE plpgsql;


\echo admin.process_external_idents
CREATE FUNCTION admin.process_external_idents(
    new_jsonb JSONB,
    unit_type TEXT,
    OUT external_idents public.external_ident[],
    OUT prior_id INTEGER
) RETURNS RECORD AS $process_external_idents$
DECLARE
    unit_fk_field TEXT;
    unit_fk_value INTEGER;
    ident_code TEXT;
    ident_value TEXT;
    ident_row public.external_ident;
    ident_type_row public.external_ident_type;
    ident_codes TEXT[] := '{}';
    -- Helpers to provide error messages to the user, with the ident_type_code
    -- that would otherwise be lost.
    ident_jsonb JSONB;
    prev_ident_jsonb JSONB;
    unique_ident_specified BOOLEAN := false;
BEGIN
    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    unit_fk_field := unit_type || '_id';

    FOR ident_type_row IN
        (SELECT * FROM public.external_ident_type)
    LOOP
        ident_code := ident_type_row.code;
        ident_codes := array_append(ident_codes, ident_code);

        IF new_jsonb ? ident_code THEN
            ident_value := new_jsonb ->> ident_code;

            IF ident_value IS NOT NULL AND ident_value <> '' THEN
                unique_ident_specified := true;

                SELECT to_jsonb(ei.*)
                     || jsonb_build_object(
                    'ident_code', eit.code -- For user feedback
                    ) INTO ident_jsonb
                FROM public.external_ident AS ei
                JOIN public.external_ident_type AS eit
                  ON ei.type_id = eit.id
                WHERE eit.id = ident_type_row.id
                  AND ei.ident = ident_value;

                IF NOT FOUND THEN
                    -- Prepare a row to be added later after the legal_unit is created
                    -- and the legal_unit_id is known.
                    ident_jsonb := jsonb_build_object(
                                'ident_code', ident_type_row.code, -- For user feedback - ignored by jsonb_populate_record
                                'type_id', ident_type_row.id, -- For jsonb_populate_record
                                'ident', ident_value
                        );
                    -- Initialise the ROW using mandatory positions, however,
                    -- populate with jsonb_populate_record for avoiding possible mismatch.
                    ident_row := ROW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
                    ident_row := jsonb_populate_record(NULL::public.external_ident,ident_jsonb);
                    external_idents := array_append(external_idents, ident_row);
                ELSE -- FOUND
                    unit_fk_value := (ident_jsonb ->> unit_fk_field)::INTEGER;
                    IF unit_fk_value IS NULL THEN
                        DECLARE
                          conflicting_unit_type TEXT;
                        BEGIN
                          CASE
                            WHEN (ident_jsonb ->> 'establishment_id') IS NOT NULL THEN
                              conflicting_unit_type := 'establishment';
                            WHEN (ident_jsonb ->> 'legal_unit_id') IS NOT NULL THEN
                              conflicting_unit_type := 'legal_unit';
                            WHEN (ident_jsonb ->> 'enterprise_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise';
                            WHEN (ident_jsonb ->> 'enterprise_group_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise_group';
                            ELSE
                              RAISE EXCEPTION 'Missing logic for external_ident %', ident_jsonb;
                          END CASE;
                          RAISE EXCEPTION 'The external identifier % for % already taken by a % for row %'
                                          , ident_code, unit_type, conflicting_unit_type, new_jsonb;
                        END;
                    END IF;
                    IF prior_id IS NULL THEN
                        prior_id := unit_fk_value;
                    ELSEIF prior_id IS DISTINCT FROM unit_fk_value THEN
                        -- All matching identifiers must be consistent.
                        RAISE EXCEPTION 'Inconsistent external identifiers % and % for row %'
                                        , prev_ident_jsonb, ident_jsonb, new_jsonb;
                    END IF;
                END IF; -- FOUND / NOT FOUND
                prev_ident_jsonb := ident_jsonb;
            END IF; -- ident_value provided
        END IF; -- ident_type.code in import
    END LOOP; -- public.external_ident_type

    IF NOT unique_ident_specified THEN
        RAISE EXCEPTION 'No external identifier (%) is specified for row %', array_to_string(ident_codes, ','), new_jsonb;
    END IF;
END; -- Process external identifiers
$process_external_idents$ LANGUAGE plpgsql;


-- Find a connected legal_unit - i.e. a field with a `legal_unit`
-- prefix that points to an external identifier.
\echo admin.process_linked_legal_unit_external_idents
CREATE FUNCTION admin.process_linked_legal_unit_external_idents(
    new_jsonb JSONB,
    OUT legal_unit_id INTEGER,
    OUT linked_ident_specified BOOL
) RETURNS RECORD AS $process_linked_legal_unit_external_ident$
DECLARE
    unit_type TEXT := 'legal_unit';
    unit_fk_field TEXT;
    unit_fk_value INTEGER;
    ident_code TEXT;
    ident_value TEXT;
    ident_row public.external_ident;
    ident_type_row public.external_ident_type;
    ident_codes TEXT[] := '{}';
    -- Helpers to provide error messages to the user, with the ident_type_code
    -- that would otherwise be lost.
    ident_jsonb JSONB;
    prev_ident_jsonb JSONB;
BEGIN
    linked_ident_specified := false;
    unit_fk_value := NULL;
    legal_unit_id := NULL;

    unit_fk_field := unit_type || '_id';

    FOR ident_type_row IN
        (SELECT * FROM public.external_ident_type)
    LOOP
        ident_code := unit_type || '_' || ident_type_row.code;
        ident_codes := array_append(ident_codes, ident_code);

        IF new_jsonb ? ident_code THEN
            ident_value := new_jsonb ->> ident_code;

            IF ident_value IS NOT NULL AND ident_value <> '' THEN
                linked_ident_specified := true;

                SELECT to_jsonb(ei.*)
                     || jsonb_build_object(
                    'ident_code', ident_code -- For user feedback
                    ) INTO ident_jsonb
                FROM public.external_ident AS ei
                WHERE ei.type_id = ident_type_row.id
                  AND ei.ident = ident_value;

                IF NOT FOUND THEN
                  RAISE EXCEPTION 'Could not find % for row %', ident_code, new_jsonb;
                ELSE -- FOUND
                    unit_fk_value := (ident_jsonb -> unit_fk_field)::INTEGER;
                    IF unit_fk_value IS NULL THEN
                        RAISE EXCEPTION 'The external identifier % is not for a % but % for row %'
                                        , ident_code, unit_type, ident_jsonb, new_jsonb;
                    END IF;
                    IF legal_unit_id IS NULL THEN
                        legal_unit_id := unit_fk_value;
                    ELSEIF legal_unit_id IS DISTINCT FROM unit_fk_value THEN
                        -- All matching identifiers must be consistent.
                        RAISE EXCEPTION 'Inconsistent external identifiers % and % for row %'
                                        , prev_ident_jsonb, ident_jsonb, new_jsonb;
                    END IF;
                END IF; -- FOUND / NOT FOUND
                prev_ident_jsonb := ident_jsonb;
            END IF; -- ident_value provided
        END IF; -- ident_type.code in import
    END LOOP; -- public.external_ident_type
END; -- Process external identifiers
$process_linked_legal_unit_external_ident$ LANGUAGE plpgsql;


\echo admin.validate_stats_for_unit
CREATE PROCEDURE admin.validate_stats_for_unit(new_jsonb JSONB)
LANGUAGE plpgsql AS $validate_stats_for_unit$
DECLARE
    stat_def_row public.stat_definition;
    stat_code TEXT;
    stat_value TEXT;
    sql_type_str TEXT;
    stat_type_check TEXT;
BEGIN
    FOR stat_def_row IN
        (SELECT * FROM public.stat_definition ORDER BY priority, code)
    LOOP
        stat_code := stat_def_row.code;
        IF new_jsonb ? stat_code THEN
            stat_value := new_jsonb ->> stat_code;
            IF stat_value IS NOT NULL AND stat_value <> '' THEN
                sql_type_str :=
                    CASE stat_def_row.type
                    WHEN 'int' THEN 'INT4'
                    WHEN 'float' THEN 'FLOAT8'
                    WHEN 'string' THEN 'TEXT'
                    WHEN 'bool' THEN 'BOOL'
                    END;
                stat_type_check := format('SELECT %L::%s', stat_value, sql_type_str);
                BEGIN -- Try to cast the stat_value into the correct type.
                    EXECUTE stat_type_check;
                EXCEPTION WHEN OTHERS THEN
                    RAISE EXCEPTION 'Invalid % type for stat % for row % with error "%"', stat_def_row.type, stat_code, new_jsonb, SQLERRM;
                END;
            END IF; -- stat_value provided
        END IF; -- stat_code in import
    END LOOP; -- public.stat_definition
END;
$validate_stats_for_unit$;


\echo admin.process_stats_for_unit
CREATE PROCEDURE admin.process_stats_for_unit(
    new_jsonb JSONB,
    unit_type TEXT,
    unit_id INTEGER,
    valid_from DATE,
    valid_to DATE,
    data_source_id INTEGER
) LANGUAGE plpgsql AS $process_stats_for_unit$
DECLARE
    stat_code TEXT;
    stat_value TEXT;
    stat_type public.stat_type;
    stat_jsonb JSONB;
    stat_row public.stat_for_unit;
    stat_def_row public.stat_definition;
    stat_codes TEXT[] := '{}';
    unit_fk_field TEXT;
    statbus_constraints_already_deferred BOOLEAN;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    unit_fk_field := unit_type || '_id';

    FOR stat_def_row IN
        (SELECT * FROM public.stat_definition ORDER BY priority, code)
    LOOP
        stat_code := stat_def_row.code;
        stat_type := stat_def_row.type;
        IF new_jsonb ? stat_code THEN
            stat_value := new_jsonb ->> stat_code;
            IF stat_value IS NOT NULL AND stat_value <> '' THEN
                stat_jsonb := jsonb_build_object(
                    'stat_definition_id', stat_def_row.id,
                    'valid_from', valid_from,
                    'valid_to', valid_to,
                    'data_source_id', data_source_id,
                    unit_fk_field, unit_id,
                    'value_' || stat_type, stat_value
                );
                stat_row := ROW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
                BEGIN
                    -- Assign jsonb to the row - casting the fields as required,
                    -- possibly throwing an error message.
                    stat_row := jsonb_populate_record(NULL::public.stat_for_unit,stat_jsonb);
                EXCEPTION WHEN OTHERS THEN
                    RAISE EXCEPTION 'Invalid % for row % with error "%"',stat_code, new_jsonb, SQLERRM;
                END;
                INSERT INTO public.stat_for_unit_era
                    ( stat_definition_id
                    , valid_after
                    , valid_from
                    , valid_to
                    , data_source_id
                    , establishment_id
                    , legal_unit_id
                    , value_int
                    , value_float
                    , value_string
                    , value_bool
                    )
                 SELECT stat_row.stat_definition_id
                      , stat_row.valid_after
                      , stat_row.valid_from
                      , stat_row.valid_to
                      , stat_row.data_source_id
                      , stat_row.establishment_id
                      , stat_row.legal_unit_id
                      , stat_row.value_int
                      , stat_row.value_float
                      , stat_row.value_string
                      , stat_row.value_bool
                RETURNING *
                INTO stat_row
                ;
                IF NOT statbus_constraints_already_deferred THEN
                    IF current_setting('client_min_messages') ILIKE 'debug%' THEN
                        DECLARE
                            row RECORD;
                        BEGIN
                            RAISE DEBUG 'DEBUG: Selecting from public.stat_for_unit where id = %', stat_row.id;
                            FOR row IN
                                SELECT * FROM public.stat_for_unit WHERE id = stat_row.id
                            LOOP
                                RAISE DEBUG 'stat_for_unit row: %', to_json(row);
                            END LOOP;
                        END;
                    END IF;
                    SET CONSTRAINTS ALL IMMEDIATE;
                    SET CONSTRAINTS ALL DEFERRED;
                END IF;

                RAISE DEBUG 'inserted_stat_for_unit: %', to_jsonb(stat_row);
            END IF; -- stat_value provided
        END IF; -- stat_code in import
    END LOOP; -- public.stat_definition
END;
$process_stats_for_unit$;


\echo admin.process_enterprise_connection
CREATE FUNCTION admin.process_enterprise_connection(
    IN prior_unit_id INTEGER,
    IN unit_type TEXT,
    IN new_valid_from DATE,
    IN new_valid_to DATE,
    IN edited_by_user_id INTEGER,
    OUT enterprise_id INTEGER,
    OUT legal_unit_id INTEGER,
    OUT is_primary_for_enterprise BOOLEAN
) RETURNS RECORD LANGUAGE plpgsql AS $process_enterprise_connection$
DECLARE
    new_center DATE;
    order_clause TEXT;
BEGIN
    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    IF prior_unit_id IS NOT NULL THEN
        -- Calculate the new center date, handling infinity.
        IF new_valid_from = '-infinity' THEN
            new_center := new_valid_to;
        ELSIF new_valid_to = 'infinity' THEN
            new_center := new_valid_from;
        ELSE
            new_center := new_valid_from + ((new_valid_to - new_valid_from) / 2);
        END IF;

        -- Find the closest enterprise connected to the prior legal unit or establishment, with consistent midpoint logic.
        order_clause := $$
            ORDER BY (
                CASE
                    WHEN valid_from = '-infinity' THEN ABS($2::DATE - valid_to)
                    WHEN valid_to = 'infinity' THEN ABS(valid_from - $2::DATE)
                    ELSE ABS($2::DATE - (valid_from + ((valid_to - valid_from) / 2))::DATE)
                END
            ) ASC
        $$;

        IF unit_type = 'establishment' THEN
            EXECUTE format($$
                SELECT enterprise_id, legal_unit_id
                FROM public.establishment
                WHERE id = $1
                %s
                LIMIT 1
            $$, order_clause)
            INTO enterprise_id, legal_unit_id
            USING prior_unit_id, new_center;

            IF enterprise_id IS NOT NULL THEN
                is_primary_for_enterprise := true;
            END IF;

        ELSIF unit_type = 'legal_unit' THEN
            EXECUTE format($$
                SELECT enterprise_id
                FROM public.legal_unit
                WHERE id = $1
                %s
                LIMIT 1
            $$, order_clause)
            INTO enterprise_id
            USING prior_unit_id, new_center;

            EXECUTE $$
                SELECT NOT EXISTS(
                    SELECT 1
                    FROM public.legal_unit
                    WHERE enterprise_id = $1
                    AND primary_for_enterprise
                    AND id <> $2
                    AND daterange(valid_from, valid_to, '[]')
                     && daterange($3, $4, '[]')
                )
            $$
            INTO is_primary_for_enterprise
            USING enterprise_id, prior_unit_id, new_valid_from, new_valid_to;
        END IF;

    ELSE
        -- Create a new enterprise and connect to it.
        INSERT INTO public.enterprise
            (active, edit_by_user_id, edit_comment)
        VALUES
            (true, edited_by_user_id, 'Batch import')
        RETURNING id INTO enterprise_id;

        -- This will be the primary legal unit or establishment for the enterprise.
        is_primary_for_enterprise := true;
    END IF;

    RETURN;
END;
$process_enterprise_connection$;

-- ========================================================
-- END:  Helper functions for import
-- ========================================================

\echo admin.import_legal_unit_era_upsert
CREATE FUNCTION admin.import_legal_unit_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    edited_by_user RECORD;
    tag RECORD;
    physical_region RECORD;
    physical_country RECORD;
    postal_region RECORD;
    postal_country RECORD;
    primary_activity_category RECORD;
    secondary_activity_category RECORD;
    sector RECORD;
    data_source RECORD;
    legal_form RECORD;
    upsert_data RECORD;
    new_typed RECORD;
    external_idents_to_add public.external_ident[] := ARRAY[]::public.external_ident[];
    prior_legal_unit_id INTEGER;
    enterprise RECORD;
    is_primary_for_enterprise BOOLEAN;
    inserted_legal_unit RECORD;
    inserted_location RECORD;
    inserted_activity RECORD;
    invalid_codes JSONB := '{}'::jsonb;
    statbus_constraints_already_deferred BOOLEAN;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    -- Ensure that id exists and can be referenced
    -- without getting either error
    --   record "physical_region" is not assigned yet
    --   record "physical_region" has no field "id"
    -- Since it always has the correct fallback of NULL for id
    --
    SELECT NULL::DATE AS birth_date
         , NULL::DATE AS death_date
         , NULL::DATE AS valid_from
         , NULL::DATE AS valid_to
        INTO new_typed;
    SELECT NULL::int AS id INTO enterprise;
    SELECT NULL::int AS id INTO physical_region;
    SELECT NULL::int AS id INTO physical_country;
    SELECT NULL::int AS id INTO postal_region;
    SELECT NULL::int AS id INTO postal_country;
    SELECT NULL::int AS id INTO primary_activity_category;
    SELECT NULL::int AS id INTO secondary_activity_category;
    SELECT NULL::int AS id INTO sector;
    SELECT NULL::int AS id INTO data_source;
    SELECT NULL::int AS id INTO legal_form;
    SELECT NULL::int AS id INTO tag;

    SELECT * INTO edited_by_user
    FROM public.statbus_user
    -- TODO: Uncomment when going into production
    -- WHERE uuid = auth.uid()
    LIMIT 1;

    SELECT tag_id INTO tag.id FROM admin.import_lookup_tag(new_jsonb);

    SELECT country_id          , updated_invalid_codes
    INTO   physical_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'physical', invalid_codes);

    SELECT region_id          , updated_invalid_codes
    INTO   physical_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'physical', invalid_codes);

    SELECT country_id        , updated_invalid_codes
    INTO   postal_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'postal', invalid_codes);

    SELECT region_id        , updated_invalid_codes
    INTO   postal_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'postal', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO primary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'primary', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO secondary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'secondary', invalid_codes);

    SELECT sector_id , updated_invalid_codes
    INTO   sector.id , invalid_codes
    FROM admin.import_lookup_sector(new_jsonb, invalid_codes);

    SELECT data_source_id , updated_invalid_codes
    INTO   data_source.id , invalid_codes
    FROM admin.import_lookup_data_source(new_jsonb, invalid_codes);

    SELECT legal_form_id , updated_invalid_codes
    INTO   legal_form.id , invalid_codes
    FROM admin.import_lookup_legal_form(new_jsonb, invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.birth_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'birth_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.death_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'death_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_from , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_from',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_to   , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_to',invalid_codes);

    CALL admin.validate_stats_for_unit(new_jsonb);

    SELECT external_idents        , prior_id
    INTO   external_idents_to_add , prior_legal_unit_id
    FROM admin.process_external_idents(new_jsonb,'legal_unit') AS r;

    SELECT NEW.tax_ident AS tax_ident
         , NEW.name AS name
         , new_typed.birth_date AS birth_date
         , new_typed.death_date AS death_date
         , true AS active
         , 'Batch import' AS edit_comment
         , CASE WHEN invalid_codes <@ '{}'::jsonb THEN NULL ELSE invalid_codes END AS invalid_codes
      INTO upsert_data;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    SELECT r.enterprise_id, r.is_primary_for_enterprise
    INTO     enterprise.id,   is_primary_for_enterprise
    FROM admin.process_enterprise_connection(
        prior_legal_unit_id, 'legal_unit',
        new_typed.valid_from, new_typed.valid_to,
        edited_by_user.id) AS r;

    INSERT INTO public.legal_unit_era
        ( valid_from
        , valid_to
        , id
        , name
        , birth_date
        , death_date
        , active
        , edit_comment
        , sector_id
        , legal_form_id
        , invalid_codes
        , enterprise_id
        , primary_for_enterprise
        , data_source_id
        , edit_by_user_id
        )
    VALUES
        ( new_typed.valid_from
        , new_typed.valid_to
        , prior_legal_unit_id
        , upsert_data.name
        , upsert_data.birth_date
        , upsert_data.death_date
        , upsert_data.active
        , upsert_data.edit_comment
        , sector.id
        , legal_form.id
        , upsert_data.invalid_codes
        , enterprise.id
        , is_primary_for_enterprise
        , data_source.id
        , edited_by_user.id
        )
     RETURNING *
     INTO inserted_legal_unit;
    RAISE DEBUG 'inserted_legal_unit %', to_json(inserted_legal_unit);

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.legal_unit where id = %', inserted_legal_unit.id;
                FOR row IN
                    SELECT * FROM public.legal_unit WHERE id = inserted_legal_unit.id
                LOOP
                    RAISE DEBUG 'legal_unit row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Store external identifiers
    IF array_length(external_idents_to_add, 1) > 0 THEN
        INSERT INTO public.external_ident
            ( type_id
            , ident
            , legal_unit_id
            , updated_by_user_id
            )
         SELECT type_id
              , ident
              , inserted_legal_unit.id
              , edited_by_user.id
         FROM unnest(external_idents_to_add);
    END IF;


    IF physical_region.id IS NOT NULL OR physical_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postal_code
            , postal_place
            , region_id
            , country_id
            , data_source_id
            , updated_by_user_id
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'physical'
            , NULLIF(NEW.physical_address_part1,'')
            , NULLIF(NEW.physical_address_part2,'')
            , NULLIF(NEW.physical_address_part3,'')
            , NULLIF(NEW.physical_postal_code,'')
            , NULLIF(NEW.physical_postal_place,'')
            , physical_region.id
            , physical_country.id
            , data_source.id
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF postal_region.id IS NOT NULL OR postal_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postal_code
            , postal_place
            , region_id
            , country_id
            , data_source_id
            , updated_by_user_id
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'postal'
            , NULLIF(NEW.postal_address_part1,'')
            , NULLIF(NEW.postal_address_part2,'')
            , NULLIF(NEW.postal_address_part3,'')
            , NULLIF(NEW.postal_postal_code,'')
            , NULLIF(NEW.postal_postal_place,'')
            , postal_region.id
            , postal_country.id
            , data_source.id
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF primary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , data_source_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'primary'
            , primary_activity_category.id
            , data_source.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF secondary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , data_source_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'secondary'
            , secondary_activity_category.id
            , data_source.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    CALL admin.process_stats_for_unit(
        new_jsonb,
        'legal_unit',
        inserted_legal_unit.id,
        new_typed.valid_from,
        new_typed.valid_to,
        data_source.id
        );

    IF tag.id IS NOT NULL THEN
        INSERT INTO public.tag_for_unit
            ( tag_id
            , legal_unit_id
            , updated_by_user_id
            )
        VALUES
            ( tag.id
            , inserted_legal_unit.id
            , edited_by_user.id
            )
        ON CONFLICT (tag_id, legal_unit_id)
        DO UPDATE SET updated_by_user_id = EXCLUDED.updated_by_user_id
        ;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RETURN NULL;
END;
$$;

\echo admin.generate_import_legal_unit_era()
CREATE PROCEDURE admin.generate_import_legal_unit_era()
LANGUAGE plpgsql AS $generate_import_legal_unit_era$
DECLARE
    result TEXT := '';
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_legal_unit_era WITH (security_invoker=on) AS
SELECT '' AS valid_from,
       '' AS valid_to,
{{ident_type_columns}}
       '' AS name,
       '' AS birth_date,
       '' AS death_date,
       '' AS physical_address_part1,
       '' AS physical_address_part2,
       '' AS physical_address_part3,
       '' AS physical_postal_code,
       '' AS physical_postal_place,
       '' AS physical_region_code,
       '' AS physical_region_path,
       '' AS physical_country_iso_2,
       '' AS postal_address_part1,
       '' AS postal_address_part2,
       '' AS postal_address_part3,
       '' AS postal_postal_code,
       '' AS postal_postal_place,
       '' AS postal_region_code,
       '' AS postal_region_path,
       '' AS postal_country_iso_2,
       '' AS primary_activity_category_code,
       '' AS secondary_activity_category_code,
       '' AS sector_code,
       '' AS data_source_code,
       '' AS legal_form_code,
{{stat_definition_columns}}
       '' AS tag_path
;
    $view_template$;
BEGIN
    SELECT string_agg(format(E'       %L AS %I,', '', code), E'\n')
    INTO ident_type_columns
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT string_agg(format(E'       %L AS %I,', '', code), E'\n')
    INTO stat_definition_columns
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    RAISE NOTICE 'Creating public.import_legal_unit_era';
    EXECUTE view_template;

    CREATE TRIGGER import_legal_unit_era_upsert_trigger
    INSTEAD OF INSERT ON public.import_legal_unit_era
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_legal_unit_era_upsert();
END;
$generate_import_legal_unit_era$;

\echo admin.cleanup_import_legal_unit_era()
CREATE PROCEDURE admin.cleanup_import_legal_unit_era()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_legal_unit_era';
    DROP VIEW public.import_legal_unit_era;
END;
$$;


\echo Add import_legal_unit_era callbacks
CALL lifecycle_callbacks.add(
    'import_legal_unit_era',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_legal_unit_era',
    'admin.cleanup_import_legal_unit_era'
    );
-- Call the generate function once to generate the view with the currently
-- defined external_ident_type's.
\echo Generating public.import_legal_unit_era
CALL admin.generate_import_legal_unit_era();

\echo admin.generate_import_legal_unit_current()
CREATE PROCEDURE admin.generate_import_legal_unit_current()
LANGUAGE plpgsql AS $generate_import_legal_unit_current$
DECLARE
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    ident_type_column_prefix TEXT := '       ';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_legal_unit_current WITH (security_invoker=on) AS
SELECT
{{ident_type_columns}}
     '' AS name,
     '' AS birth_date,
     '' AS death_date,
     '' AS physical_address_part1,
     '' AS physical_address_part2,
     '' AS physical_address_part3,
     '' AS physical_postal_code,
     '' AS physical_postal_place,
     '' AS physical_region_code,
     '' AS physical_region_path,
     '' AS physical_country_iso_2,
     '' AS postal_address_part1,
     '' AS postal_address_part2,
     '' AS postal_address_part3,
     '' AS postal_postal_code,
     '' AS postal_postal_place,
     '' AS postal_region_code,
     '' AS postal_region_path,
     '' AS postal_country_iso_2,
     '' AS primary_activity_category_code,
     '' AS secondary_activity_category_code,
     '' AS sector_code,
     '' AS data_source_code,
     '' AS legal_form_code,
{{stat_definition_columns}}
     '' AS tag_path
FROM public.import_legal_unit_era;
    $view_template$;

    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_legal_unit_current_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_legal_unit_current_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_legal_unit_era(
        valid_from,
        valid_to,
{{ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
        legal_form_code,
{{stats_insert_labels}}
        tag_path
        )
    VALUES(
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
        NEW.legal_form_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_legal_unit_current_upsert$;
    $function_template$;
BEGIN
    SELECT
        string_agg(format(E'     %L AS %I,', '', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,', '', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    function_template := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    RAISE NOTICE 'Creating public.import_legal_unit_current';
    EXECUTE view_template;

    RAISE NOTICE 'Creating admin.import_legal_unit_current_upsert()';
    EXECUTE function_template;

    CREATE TRIGGER import_legal_unit_current_upsert_trigger
    INSTEAD OF INSERT ON public.import_legal_unit_current
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_legal_unit_current_upsert();
END;
$generate_import_legal_unit_current$;

\echo admin.cleanup_import_legal_unit_current()
CREATE PROCEDURE admin.cleanup_import_legal_unit_current()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_legal_unit_current';
    DROP VIEW public.import_legal_unit_current;
    RAISE NOTICE 'Deleting admin.import_legal_unit_current_upsert()';
    DROP FUNCTION admin.import_legal_unit_current_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_legal_unit_current',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_legal_unit_current',
    'admin.cleanup_import_legal_unit_current'
    );

\echo Generating public.import_legal_unit_current
\echo Generating admin.import_legal_unit_current_upsert
CALL admin.generate_import_legal_unit_current();


\echo admin.import_establishment_era_upsert
CREATE FUNCTION admin.import_establishment_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    edited_by_user RECORD;
    tag RECORD;
    physical_region RECORD;
    physical_country RECORD;
    postal_region RECORD;
    postal_country RECORD;
    legal_unit RECORD;
    is_primary_for_legal_unit BOOLEAN;
    enterprise RECORD;
    primary_activity_category RECORD;
    secondary_activity_category RECORD;
    sector RECORD;
    data_source RECORD;
    upsert_data RECORD;
    new_typed RECORD;
    external_idents_to_add public.external_ident[] := ARRAY[]::public.external_ident[];
    prior_establishment_id INTEGER;
    legal_unit_ident_specified BOOL := false;
    inserted_establishment RECORD;
    inserted_location RECORD;
    inserted_activity RECORD;
    stat_def RECORD;
    inserted_stat_for_unit RECORD;
    invalid_codes JSONB := '{}'::jsonb;
    statbus_constraints_already_deferred BOOLEAN;
    stats RECORD;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    -- Ensure that id exists and can be referenced
    -- without getting either error
    --   record "enterprise" is not assigned yet
    --   record "enterprise" has no field "id"
    -- Since it always has the correct fallback of NULL for id
    --
    SELECT NULL::DATE AS birth_date
         , NULL::DATE AS death_date
         , NULL::DATE AS valid_from
         , NULL::DATE AS valid_to
        INTO new_typed;
    SELECT NULL::int AS id INTO tag;
    SELECT NULL::int AS id INTO legal_unit;
    SELECT NULL::int AS id INTO enterprise;
    SELECT NULL::int AS id INTO physical_region;
    SELECT NULL::int AS id INTO physical_country;
    SELECT NULL::int AS id INTO postal_region;
    SELECT NULL::int AS id INTO postal_country;
    SELECT NULL::int AS id INTO primary_activity_category;
    SELECT NULL::int AS id INTO secondary_activity_category;
    SELECT NULL::int AS id INTO sector;
    SELECT NULL::int AS id INTO data_source;
    SELECT NULL::int AS employees
         , NULL::int AS turnover
        INTO stats;

    SELECT * INTO edited_by_user
    FROM public.statbus_user
    -- TODO: Uncomment when going into production
    -- WHERE uuid = auth.uid()
    LIMIT 1;

    SELECT tag_id INTO tag.id FROM admin.import_lookup_tag(new_jsonb);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.birth_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'birth_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.death_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'death_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_from , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_from',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_to   , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_to',invalid_codes);

    CALL admin.validate_stats_for_unit(new_jsonb);

    SELECT country_id          , updated_invalid_codes
    INTO   physical_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'physical', invalid_codes);

    SELECT region_id          , updated_invalid_codes
    INTO   physical_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'physical', invalid_codes);

    SELECT country_id        , updated_invalid_codes
    INTO   postal_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'postal', invalid_codes);

    SELECT region_id        , updated_invalid_codes
    INTO   postal_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'postal', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO primary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'primary', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO secondary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'secondary', invalid_codes);

    SELECT sector_id , updated_invalid_codes
    INTO   sector.id , invalid_codes
    FROM admin.import_lookup_sector(new_jsonb, invalid_codes);

    SELECT data_source_id , updated_invalid_codes
    INTO   data_source.id , invalid_codes
    FROM admin.import_lookup_data_source(new_jsonb, invalid_codes);

    SELECT external_idents        , prior_id
    INTO   external_idents_to_add , prior_establishment_id
    FROM admin.process_external_idents(new_jsonb,'establishment') AS r;

    SELECT r.legal_unit_id, r.linked_ident_specified
    INTO legal_unit.id, legal_unit_ident_specified
    FROM admin.process_linked_legal_unit_external_idents(new_jsonb) AS r;

    IF NOT legal_unit_ident_specified THEN
        SELECT r.enterprise_id, r.legal_unit_id
        INTO     enterprise.id, legal_unit.id
        FROM admin.process_enterprise_connection(
            prior_establishment_id, 'establishment',
            new_typed.valid_from, new_typed.valid_to,
            edited_by_user.id) AS r;
    END IF;

    -- If no legal_unit is specified, but there was an existing entry connected to
    -- a legal unit, then update of values is ok, and we must decide if this is primary.
    IF legal_unit.id IS NOT NULL THEN
        DECLARE
          sql_query TEXT :=  format(
            'SELECT NOT EXISTS(
                  SELECT 1
                  FROM public.establishment
                  WHERE legal_unit_id = %L
                  AND primary_for_legal_unit
                  AND COALESCE(id <> %L,true)
                  AND daterange(valid_from, valid_to, ''[]'')
                  && daterange(%L, %L, ''[]'')
              )',
              legal_unit.id, prior_establishment_id, new_typed.valid_from, new_typed.valid_to
          );
        BEGIN
          RAISE DEBUG 'Executing SQL: %', sql_query;
          EXECUTE sql_query
          INTO is_primary_for_legal_unit;
          RAISE DEBUG 'is_primary_for_legal_unit=%', is_primary_for_legal_unit;
        END;
    END IF;

    SELECT NEW.name AS name
         , new_typed.birth_date AS birth_date
         , new_typed.death_date AS death_date
         , true AS active
         , 'Batch import' AS edit_comment
         , CASE WHEN invalid_codes <@ '{}'::jsonb THEN NULL ELSE invalid_codes END AS invalid_codes
         , enterprise.id AS enterprise_id
         , legal_unit.id AS legal_unit_id
         , is_primary_for_legal_unit AS primary_for_legal_unit
      INTO upsert_data;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    INSERT INTO public.establishment_era
        ( valid_from
        , valid_to
        , id
        , name
        , birth_date
        , death_date
        , active
        , edit_comment
        , sector_id
        , invalid_codes
        , enterprise_id
        , legal_unit_id
        , primary_for_legal_unit
        , data_source_id
        , edit_by_user_id
        )
    VALUES
        ( new_typed.valid_from
        , new_typed.valid_to
        , prior_establishment_id
        , upsert_data.name
        , upsert_data.birth_date
        , upsert_data.death_date
        , upsert_data.active
        , upsert_data.edit_comment
        , sector.id
        , upsert_data.invalid_codes
        , upsert_data.enterprise_id
        , upsert_data.legal_unit_id
        , upsert_data.primary_for_legal_unit
        , data_source.id
        , edited_by_user.id
        )
     RETURNING *
     INTO inserted_establishment;
    RAISE DEBUG 'inserted_establishment %', to_json(inserted_establishment);

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.establishment where id = %', inserted_establishment.id;
                FOR row IN
                    SELECT * FROM public.establishment WHERE id = inserted_establishment.id
                LOOP
                    RAISE DEBUG 'establishment row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF array_length(external_idents_to_add, 1) > 0 THEN
        INSERT INTO public.external_ident
            ( type_id
            , ident
            , establishment_id
            , updated_by_user_id
            )
         SELECT type_id
              , ident
              , inserted_establishment.id
              , edited_by_user.id
         FROM unnest(external_idents_to_add);
    END IF;

    IF physical_region.id IS NOT NULL OR physical_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postal_code
            , postal_place
            , region_id
            , country_id
            , data_source_id
            , updated_by_user_id
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'physical'
            , NULLIF(NEW.physical_address_part1,'')
            , NULLIF(NEW.physical_address_part2,'')
            , NULLIF(NEW.physical_address_part3,'')
            , NULLIF(NEW.physical_postal_code,'')
            , NULLIF(NEW.physical_postal_place,'')
            , physical_region.id
            , physical_country.id
            , data_source.id
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF postal_region.id IS NOT NULL OR postal_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postal_code
            , postal_place
            , region_id
            , country_id
            , data_source_id
            , updated_by_user_id
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'postal'
            , NULLIF(NEW.postal_address_part1,'')
            , NULLIF(NEW.postal_address_part2,'')
            , NULLIF(NEW.postal_address_part3,'')
            , NULLIF(NEW.postal_postal_code,'')
            , NULLIF(NEW.postal_postal_place,'')
            , postal_region.id
            , postal_country.id
            , data_source.id
            , edited_by_user.id
            )
        RETURNING * INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF primary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , category_id
            , data_source_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'primary'
            , primary_activity_category.id
            , data_source.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF secondary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , category_id
            , data_source_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'secondary'
            , secondary_activity_category.id
            , data_source.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    CALL admin.process_stats_for_unit(
        new_jsonb,
        'establishment',
        inserted_establishment.id,
        new_typed.valid_from,
        new_typed.valid_to,
        data_source.id
        );

    IF tag.id IS NOT NULL THEN
        -- UPSERT to avoid multiple tags for different parts of a timeline.
        INSERT INTO public.tag_for_unit
            ( tag_id
            , establishment_id
            , updated_by_user_id
            )
        VALUES
            ( tag.id
            , inserted_establishment.id
            , edited_by_user.id
            )
        ON CONFLICT (tag_id, establishment_id)
        DO UPDATE SET updated_by_user_id = EXCLUDED.updated_by_user_id
        ;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RETURN NULL;
END;
$$;


CREATE PROCEDURE admin.generate_import_establishment_era()
LANGUAGE plpgsql AS $generate_import_establishment_era$
DECLARE
    result TEXT := '';
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    legal_unit_ident_type_columns TEXT := '';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_era
WITH (security_invoker=on) AS
SELECT '' AS valid_from,
       '' AS valid_to,
{{ident_type_columns}}
{{legal_unit_ident_type_columns}}
       '' AS name,
       '' AS birth_date,
       '' AS death_date,
       '' AS physical_address_part1,
       '' AS physical_address_part2,
       '' AS physical_address_part3,
       '' AS physical_postal_code,
       '' AS physical_postal_place,
       '' AS physical_region_code,
       '' AS physical_region_path,
       '' AS physical_country_iso_2,
       '' AS postal_address_part1,
       '' AS postal_address_part2,
       '' AS postal_address_part3,
       '' AS postal_postal_code,
       '' AS postal_postal_place,
       '' AS postal_region_code,
       '' AS postal_region_path,
       '' AS postal_country_iso_2,
       '' AS primary_activity_category_code,
       '' AS secondary_activity_category_code,
       '' AS sector_code,
       '' AS data_source_code,
{{stat_definition_columns}}
       '' AS tag_path
;
    $view_template$;
BEGIN
    SELECT
        string_agg(format(E'       %L AS %I,', '', code), E'\n'),
        string_agg(format(E'       %L AS %I,', '', 'legal_unit_' || code), E'\n')
    INTO
        ident_type_columns,
        legal_unit_ident_type_columns
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,', '', code), E'\n')
    INTO
        stat_definition_columns
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'legal_unit_ident_type_columns', legal_unit_ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    RAISE NOTICE 'Creating public.import_establishment_era';
    EXECUTE view_template;

    COMMENT ON VIEW public.import_establishment_era IS 'Upload of establishment with all available fields';

    CREATE TRIGGER import_establishment_era_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_era
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_era_upsert();
END;
$generate_import_establishment_era$;

\echo admin.cleanup_import_establishment_era()
CREATE PROCEDURE admin.cleanup_import_establishment_era()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_era';
    DROP VIEW public.import_establishment_era;
END;
$$;

\echo Add import_establishment_era callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_era',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_era',
    'admin.cleanup_import_establishment_era'
    );

\echo Generating public.generate_import_establishment_era
CALL admin.generate_import_establishment_era();


\echo admin.generate_import_establishment_current()
CREATE PROCEDURE admin.generate_import_establishment_current()
LANGUAGE plpgsql AS $generate_import_establishment_current$
DECLARE
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current WITH (security_invoker=on) AS
SELECT
{{ident_type_columns}}
       '' AS name,
       '' AS birth_date,
       '' AS death_date,
       '' AS physical_address_part1,
       '' AS physical_address_part2,
       '' AS physical_address_part3,
       '' AS physical_postal_code,
       '' AS physical_postal_place,
       '' AS physical_region_code,
       '' AS physical_region_path,
       '' AS physical_country_iso_2,
       '' AS postal_address_part1,
       '' AS postal_address_part2,
       '' AS postal_address_part3,
       '' AS postal_postal_code,
       '' AS postal_postal_place,
       '' AS postal_region_code,
       '' AS postal_region_path,
       '' AS postal_country_iso_2,
       '' AS primary_activity_category_code,
       '' AS secondary_activity_category_code,
       '' AS sector_code,
       '' AS data_source_code,
       '' AS legal_form_code,
{{stat_definition_columns}}
       '' AS tag_path
FROM public.import_establishment_era;
    $view_template$;

    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
{{ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
        legal_form_code,
{{stats_insert_labels}}
        tag_path
        )
    VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
        NEW.legal_form_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_upsert$;
    $function_template$;
BEGIN
    SELECT
        string_agg(format(E'     %L AS %I,', '', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    function_template := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_insert_labels', stats_insert_labels,
        'stats_value_labels', stats_value_labels
    ));

    RAISE NOTICE 'Creating public.import_establishment_current';
    EXECUTE view_template;

    RAISE NOTICE 'Creating admin.import_establishment_current_upsert()';
    EXECUTE function_template;
END;
$generate_import_establishment_current$;


\echo admin.cleanup_import_establishment_current()
CREATE PROCEDURE admin.cleanup_import_establishment_current()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current';
    DROP VIEW public.import_establishment_current;

    RAISE NOTICE 'Deleting admin.import_establishment_current_upsert()';
    DROP FUNCTION admin.import_establishment_current_upsert();
END;
$$;

\echo Add import_establishment_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_current',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_current',
    'admin.cleanup_import_establishment_current'
    );

\echo Generating public.import_establishment_current
\echo Generating admin.import_establishment_current_upsert
CALL admin.generate_import_establishment_current();


\echo admin.generate_import_establishment_era_for_legal_unit()
CREATE PROCEDURE admin.generate_import_establishment_era_for_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_era_for_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    legal_unit_ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    legal_unit_ident_missing_check TEXT := '';
    ident_insert_labels TEXT := '';
    legal_unit_ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    legal_unit_ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_era_for_legal_unit
WITH (security_invoker=on) AS
SELECT valid_from,
       valid_to,
{{ident_type_columns}}
     -- One of these are required - it must connect to an existing legal_unit
{{legal_unit_ident_type_columns}}
       name,
       birth_date,
       death_date,
       physical_address_part1,
       physical_address_part2,
       physical_address_part3,
       physical_postal_code,
       physical_postal_place,
       physical_region_code,
       physical_region_path,
       physical_country_iso_2,
       postal_address_part1,
       postal_address_part2,
       postal_address_part3,
       postal_postal_code,
       postal_postal_place,
       postal_region_code,
       postal_region_path,
       postal_country_iso_2,
       primary_activity_category_code,
       secondary_activity_category_code,
       data_source_code,
     -- sector_code is Disabled because the legal unit provides the sector_code
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_era_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_era_for_legal_unit_upsert$
BEGIN
    IF {{legal_unit_ident_missing_check}}
    THEN
      RAISE EXCEPTION 'Missing legal_unit identifier for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
        --
{{ident_insert_labels}}
        --
{{legal_unit_ident_insert_labels}}
        --
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        NEW.valid_from,
        NEW.valid_to,
        --
{{ident_value_labels}}
        --
{{legal_unit_ident_value_labels}}
        --
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_era_for_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format('(NEW.%1$I IS NULL OR NEW.%1$I = %2$L)',
                          'legal_unit_' || code, ''), ' AND '),
        string_agg(format(E'       %I,', code), E'\n'),
        string_agg(format(E'       %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', 'legal_unit_' || code), E'\n')
    INTO
        legal_unit_ident_missing_check,
        ident_type_columns,
        legal_unit_ident_type_columns,
        ident_insert_labels,
        legal_unit_ident_insert_labels,
        ident_value_labels,
        legal_unit_ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    -- Process stat_definition_columns and related fields
    SELECT
        string_agg(format(E'       %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'legal_unit_ident_type_columns', legal_unit_ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'legal_unit_ident_missing_check', COALESCE(legal_unit_ident_missing_check,'true'),
        'ident_insert_labels', ident_insert_labels,
        'legal_unit_ident_insert_labels', legal_unit_ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'legal_unit_ident_value_labels', legal_unit_ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_era_for_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_era_for_legal_unit IS 'Upload of establishment era (any timeline) that must connect to a legal_unit';

    RAISE NOTICE 'Creating admin.import_establishment_era_for_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_era_for_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_era_for_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_era_for_legal_unit_upsert();
END;
$generate_import_establishment_era_for_legal_unit$;

\echo admin.cleanup_import_establishment_era_for_legal_unit()
CREATE PROCEDURE admin.cleanup_import_establishment_era_for_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_era_for_legal_unit';
    DROP VIEW public.import_establishment_era_for_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_era_for_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_era_for_legal_unit_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_era_for_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_era_for_legal_unit',
    'admin.cleanup_import_establishment_era_for_legal_unit'
    );

\echo Generating public.generate_import_establishment_era_for_legal_unit
CALL admin.generate_import_establishment_era_for_legal_unit();

\echo admin.generate_import_establishment_current_for_legal_unit()
CREATE PROCEDURE admin.generate_import_establishment_current_for_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_current_for_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    legal_unit_ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    legal_unit_ident_missing_check TEXT := '';
    ident_insert_labels TEXT := '';
    legal_unit_ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    legal_unit_ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current_for_legal_unit
WITH (security_invoker=on) AS
SELECT {{ident_type_columns}}
{{legal_unit_ident_type_columns}}
       name,
       birth_date,
       death_date,
       physical_address_part1,
       physical_address_part2,
       physical_address_part3,
       physical_postal_code,
       physical_postal_place,
       physical_region_code,
       physical_region_path,
       physical_country_iso_2,
       postal_address_part1,
       postal_address_part2,
       postal_address_part3,
       postal_postal_code,
       postal_postal_place,
       postal_region_code,
       postal_region_path,
       postal_country_iso_2,
       primary_activity_category_code,
       secondary_activity_category_code,
       data_source_code,
     -- sector_code is Disabled because the legal unit provides the sector_code
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_for_legal_unit_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    IF {{legal_unit_ident_missing_check}}
    THEN
      RAISE EXCEPTION 'Missing legal_unit identifier for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
{{ident_insert_labels}}
{{legal_unit_ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
{{legal_unit_ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_for_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format('(NEW.%1$I IS NULL OR NEW.%1$I = %2$L)',
                          'legal_unit_' || code, ''), ' AND '),
        string_agg(format(E'     %I,', code), E'\n'),
        string_agg(format(E'     %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', 'legal_unit_' || code), E'\n')
    INTO
        legal_unit_ident_missing_check,
        ident_type_columns,
        legal_unit_ident_type_columns,
        ident_insert_labels,
        legal_unit_ident_insert_labels,
        ident_value_labels,
        legal_unit_ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'legal_unit_ident_type_columns', legal_unit_ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'legal_unit_ident_missing_check', COALESCE(legal_unit_ident_missing_check,'true'),
        'ident_insert_labels', ident_insert_labels,
        'legal_unit_ident_insert_labels', legal_unit_ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'legal_unit_ident_value_labels', legal_unit_ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_current_for_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_current_for_legal_unit IS 'Upload of establishment from today and forwards that must connect to a legal_unit';

    RAISE NOTICE 'Creating admin.import_establishment_current_for_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_current_for_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_current_for_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_current_for_legal_unit_upsert();
END;
$generate_import_establishment_current_for_legal_unit$;

\echo admin.cleanup_import_establishment_current_for_legal_unit()
CREATE PROCEDURE admin.cleanup_import_establishment_current_for_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current_for_legal_unit';
    DROP VIEW public.import_establishment_current_for_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_current_for_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_current_for_legal_unit_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_current_for_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_current_for_legal_unit',
    'admin.cleanup_import_establishment_current_for_legal_unit'
    );

\echo Generating public.generate_import_establishment_current_for_legal_unit
CALL admin.generate_import_establishment_current_for_legal_unit();


\echo admin.generate_import_establishment_era_without_legal_unit()
CREATE PROCEDURE admin.generate_import_establishment_era_without_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_era_without_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_era_without_legal_unit
WITH (security_invoker=on) AS
SELECT valid_from,
       valid_to,
{{ident_type_columns}}
       name,
       birth_date,
       death_date,
       physical_address_part1,
       physical_address_part2,
       physical_address_part3,
       physical_postal_code,
       physical_postal_place,
       physical_region_code,
       physical_region_path,
       physical_country_iso_2,
       postal_address_part1,
       postal_address_part2,
       postal_address_part3,
       postal_postal_code,
       postal_postal_place,
       postal_region_code,
       postal_region_path,
       postal_country_iso_2,
       primary_activity_category_code,
       secondary_activity_category_code,
       sector_code, -- Is allowed, since there is no legal unit to provide it.
       data_source_code,
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_era_without_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_era_without_legal_unit_upsert$
BEGIN
    INSERT INTO public.import_establishment_era (
        valid_from,
        valid_to,
{{ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        NEW.valid_from,
        NEW.valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_era_without_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format(E'     %I,', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_era_without_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_era_without_legal_unit IS 'Upload of establishment without a legal unit for a specified time';

    RAISE NOTICE 'Creating admin.import_establishment_era_without_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_era_without_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_era_without_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_era_without_legal_unit_upsert();

END;
$generate_import_establishment_era_without_legal_unit$;

\echo admin.cleanup_import_establishment_era_without_legal_unit()
CREATE PROCEDURE admin.cleanup_import_establishment_era_without_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_era_without_legal_unit';
    DROP VIEW public.import_establishment_era_without_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_era_without_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_era_without_legal_unit_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_era_without_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_era_without_legal_unit',
    'admin.cleanup_import_establishment_era_without_legal_unit'
    );

\echo Generating admin.generate_import_establishment_era_without_legal_unit
CALL admin.generate_import_establishment_era_without_legal_unit();


\echo admin.generate_import_establishment_current_without_legal_unit()
CREATE PROCEDURE admin.generate_import_establishment_current_without_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_current_without_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current_without_legal_unit
WITH (security_invoker=on) AS
SELECT {{ident_type_columns}}
     -- legal_unit_tax_ident is Disabled because this is an informal sector
       name,
       birth_date,
       death_date,
       physical_address_part1,
       physical_address_part2,
       physical_address_part3,
       physical_postal_code,
       physical_postal_place,
       physical_region_code,
       physical_region_path,
       physical_country_iso_2,
       postal_address_part1,
       postal_address_part2,
       postal_address_part3,
       postal_postal_code,
       postal_postal_place,
       postal_region_code,
       postal_region_path,
       postal_country_iso_2,
       primary_activity_category_code,
       secondary_activity_category_code,
       sector_code, -- Is allowed, since there is no legal unit to provide it.
       data_source_code,
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_without_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_without_legal_unit_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era (
        valid_from,
        valid_to,
{{ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_without_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format(E'     %I,', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_current_without_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_current_without_legal_unit IS 'Upload of establishment without a legal unit for a specified time';

    RAISE NOTICE 'Creating admin.import_establishment_current_without_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_current_without_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_current_without_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_current_without_legal_unit_upsert();

END;
$generate_import_establishment_current_without_legal_unit$;

\echo admin.cleanup_import_establishment_current_without_legal_unit()
CREATE PROCEDURE admin.cleanup_import_establishment_current_without_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current_without_legal_unit';
    DROP VIEW public.import_establishment_current_without_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_current_without_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_current_without_legal_unit_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_current_without_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_current_without_legal_unit',
    'admin.cleanup_import_establishment_current_without_legal_unit'
    );

\echo Generating admin.generate_import_establishment_current_without_legal_unit
CALL admin.generate_import_establishment_current_without_legal_unit();


-- View for insert of Norwegian Legal Unit (Hovedenhet)
\echo public.legal_unit_brreg_view
CREATE VIEW public.legal_unit_brreg_view
WITH (security_invoker=on) AS
SELECT '' AS "organisasjonsnummer"
     , '' AS "navn"
     , '' AS "organisasjonsform.kode"
     , '' AS "organisasjonsform.beskrivelse"
     , '' AS "naeringskode1.kode"
     , '' AS "naeringskode1.beskrivelse"
     , '' AS "naeringskode2.kode"
     , '' AS "naeringskode2.beskrivelse"
     , '' AS "naeringskode3.kode"
     , '' AS "naeringskode3.beskrivelse"
     , '' AS "hjelpeenhetskode.kode"
     , '' AS "hjelpeenhetskode.beskrivelse"
     , '' AS "harRegistrertAntallAnsatte"
     , '' AS "antallAnsatte"
     , '' AS "hjemmeside"
     , '' AS "postadresse.adresse"
     , '' AS "postadresse.poststed"
     , '' AS "postadresse.postnummer"
     , '' AS "postadresse.kommune"
     , '' AS "postadresse.kommunenummer"
     , '' AS "postadresse.land"
     , '' AS "postadresse.landkode"
     , '' AS "forretningsadresse.adresse"
     , '' AS "forretningsadresse.poststed"
     , '' AS "forretningsadresse.postnummer"
     , '' AS "forretningsadresse.kommune"
     , '' AS "forretningsadresse.kommunenummer"
     , '' AS "forretningsadresse.land"
     , '' AS "forretningsadresse.landkode"
     , '' AS "institusjonellSektorkode.kode"
     , '' AS "institusjonellSektorkode.beskrivelse"
     , '' AS "sisteInnsendteAarsregnskap"
     , '' AS "registreringsdatoenhetsregisteret"
     , '' AS "stiftelsesdato"
     , '' AS "registrertIMvaRegisteret"
     , '' AS "frivilligMvaRegistrertBeskrivelser"
     , '' AS "registrertIFrivillighetsregisteret"
     , '' AS "registrertIForetaksregisteret"
     , '' AS "registrertIStiftelsesregisteret"
     , '' AS "konkurs"
     , '' AS "konkursdato"
     , '' AS "underAvvikling"
     , '' AS "underAvviklingDato"
     , '' AS "underTvangsavviklingEllerTvangsopplosning"
     , '' AS "tvangsopplostPgaManglendeDagligLederDato"
     , '' AS "tvangsopplostPgaManglendeRevisorDato"
     , '' AS "tvangsopplostPgaManglendeRegnskapDato"
     , '' AS "tvangsopplostPgaMangelfulltStyreDato"
     , '' AS "tvangsavvikletPgaManglendeSlettingDato"
     , '' AS "overordnetEnhet"
     , '' AS "maalform"
     , '' AS "vedtektsdato"
     , '' AS "vedtektsfestetFormaal"
     , '' AS "aktivitet"
     ;

\echo admin.legal_unit_brreg_view_upsert
CREATE FUNCTION admin.legal_unit_brreg_view_upsert()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."stiftelsesdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."stiftelsesdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.legal_unit
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE legal_unit.tax_ident = upsert_data.tax_ident
          AND legal_unit.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, legal_unit.id
    ),
    insert_outcome AS (
        INSERT INTO public.legal_unit
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Create triggers for the view
CREATE TRIGGER legal_unit_brreg_view_upsert
INSTEAD OF INSERT ON public.legal_unit_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.legal_unit_brreg_view_upsert();

-- time psql <<EOS
-- \copy public.legal_unit_brreg_view FROM 'tmp/enheter.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
-- EOS



-- View for insert of Norwegian Establishment (Underenhet)
\echo public.establishment_brreg_view
CREATE VIEW public.establishment_brreg_view
WITH (security_invoker=on) AS
SELECT '' AS "organisasjonsnummer"
     , '' AS "navn"
     , '' AS "organisasjonsform.kode"
     , '' AS "organisasjonsform.beskrivelse"
     , '' AS "naeringskode1.kode"
     , '' AS "naeringskode1.beskrivelse"
     , '' AS "naeringskode2.kode"
     , '' AS "naeringskode2.beskrivelse"
     , '' AS "naeringskode3.kode"
     , '' AS "naeringskode3.beskrivelse"
     , '' AS "hjelpeenhetskode.kode"
     , '' AS "hjelpeenhetskode.beskrivelse"
     , '' AS "harRegistrertAntallAnsatte"
     , '' AS "antallAnsatte"
     , '' AS "hjemmeside"
     , '' AS "postadresse.adresse"
     , '' AS "postadresse.poststed"
     , '' AS "postadresse.postnummer"
     , '' AS "postadresse.kommune"
     , '' AS "postadresse.kommunenummer"
     , '' AS "postadresse.land"
     , '' AS "postadresse.landkode"
     , '' AS "beliggenhetsadresse.adresse"
     , '' AS "beliggenhetsadresse.poststed"
     , '' AS "beliggenhetsadresse.postnummer"
     , '' AS "beliggenhetsadresse.kommune"
     , '' AS "beliggenhetsadresse.kommunenummer"
     , '' AS "beliggenhetsadresse.land"
     , '' AS "beliggenhetsadresse.landkode"
     , '' AS "registreringsdatoIEnhetsregisteret"
     , '' AS "frivilligMvaRegistrertBeskrivelser"
     , '' AS "registrertIMvaregisteret"
     , '' AS "oppstartsdato"
     , '' AS "datoEierskifte"
     , '' AS "overordnetEnhet"
     , '' AS "nedleggelsesdato"
     ;


\echo admin.upsert_establishment_brreg_view
CREATE FUNCTION admin.upsert_establishment_brreg_view()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."oppstartsdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."oppstartsdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.establishment
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE establishment.tax_ident = upsert_data.tax_ident
          AND establishment.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, establishment.id
    ),
    insert_outcome AS (
        INSERT INTO public.establishment
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Create triggers for the view
CREATE TRIGGER upsert_establishment_brreg_view
INSTEAD OF INSERT ON public.establishment_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_establishment_brreg_view();


CREATE TYPE public.reset_scope AS ENUM('data','getting-started','all');

\echo public.reset(boolean confirmed, scope public.reset_scope)
CREATE FUNCTION public.reset (confirmed boolean, scope public.reset_scope)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        -- Initial pattern application for 'activity'
        WITH deleted AS (
            DELETE FROM public.activity WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'activity', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted)
                )
            ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        -- Apply pattern for 'location'
        WITH deleted_location AS (
            DELETE FROM public.location WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'location', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_location)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Add delete for public.tag where type = 'custom'
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE type = 'custom' RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        -- Apply pattern for 'stat_for_unit'
        WITH deleted_stat_for_unit AS (
            DELETE FROM public.stat_for_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_for_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_for_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Add delete for public.stat_definition WHERE code NOT IN ('employees','turnover')
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition WHERE code NOT IN ('employees','turnover') RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        -- Add delete for public.external_ident_type not added by the system
        WITH deleted_external_ident AS (
            DELETE FROM public.external_ident WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Add delete for public.external_ident_type not added by the system
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type WHERE code NOT IN ('stat_ident','tax_ident') RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_establishment AS (
            DELETE FROM public.establishment WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'establishment', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_establishment)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_legal_unit AS (
            DELETE FROM public.legal_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_enterprise AS (
            DELETE FROM public.enterprise WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'enterprise', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_enterprise)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Special handling for tables with 'custom' attribute
        -- Change any children with `parent_id` pointing to an `id` of a row to be deleted,
        -- to point to a NOT custom row instead.
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.active
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET active = TRUE
            WHERE NOT custom
              AND NOT active
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;


    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Apply pattern for 'sector'
        WITH deleted_sector AS (
            DELETE FROM public.sector WHERE custom RETURNING *
        ), changed_sector AS (
            UPDATE public.sector
               SET active = TRUE
             WHERE NOT custom
               AND NOT active
             RETURNING *
        )
        SELECT jsonb_build_object(
            'sector', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_sector),
                'changed_count', (SELECT COUNT(*) FROM changed_sector)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Apply pattern for 'legal_form'
        WITH deleted_legal_form AS (
            DELETE FROM public.legal_form WHERE custom RETURNING *
        ), changed_legal_form AS (
            UPDATE public.legal_form
               SET active = TRUE
             WHERE NOT custom
               AND NOT active
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_form', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_form),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_form)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    SELECT jsonb_build_object(
        'statistical_unit_refresh_now',jsonb_agg(data.*)
      ) INTO changed
      FROM public.statistical_unit_refresh_now() AS data;
    result := result || changed;

    RETURN result;
END;
$$;


-- time psql <<EOS
-- \copy public.establishment_brreg_view FROM 'tmp/underenheter.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
-- EOS


-- Add helpers
CREATE FUNCTION public.remove_ephemeral_data_from_hierarchy(data JSONB) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
    result JSONB;
    key TEXT;
    value JSONB;
    new_value JSONB;
    ephemeral_keys TEXT[] := ARRAY['id', 'created_at', 'updated_at'];
    ephemeral_patterns TEXT[] := ARRAY['%_id','%_ids'];
BEGIN
    -- Handle both object and array types at the first level
    CASE jsonb_typeof(data)
        WHEN 'object' THEN
            result := '{}';  -- Initialize result as an empty object
            FOR key, value IN SELECT * FROM jsonb_each(data) LOOP
                IF key = ANY(ephemeral_keys) OR key LIKE ANY(ephemeral_patterns) THEN
                    CONTINUE;
                END IF;
                new_value := public.remove_ephemeral_data_from_hierarchy(value);
                result := jsonb_set(result, ARRAY[key], new_value, true);
            END LOOP;
        WHEN 'array' THEN
            -- No need to initialize result as '{}', let the SELECT INTO handle it
            SELECT COALESCE
                ( jsonb_agg(public.remove_ephemeral_data_from_hierarchy(elem))
                , '[]'::JSONB
            )
            INTO result
            FROM jsonb_array_elements(data) AS elem;
        ELSE
            -- If data is neither object nor array, return it as is
            result := data;
    END CASE;

    RETURN result;
END;
$$;



-- Add security.

\echo auth.has_statbus_role
CREATE OR REPLACE FUNCTION auth.has_statbus_role (user_uuid UUID, type public.statbus_role_type)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = $2))
  );
$$;

-- Add security functions
\echo auth.has_one_of_statbus_roles
CREATE OR REPLACE FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, types public.statbus_role_type[])
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = ANY ($2)))
  );
$$;


\echo auth.has_activity_category_access
CREATE OR REPLACE FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.activity_category_role AS acr ON acr.role_id = su.role_id
        WHERE su.uuid = $1
          AND acr.activity_category_id  = $2
   )
$$;


CREATE OR REPLACE FUNCTION auth.has_region_access (user_uuid UUID, region_id integer)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.region_role AS rr ON rr.role_id = su.role_id
        WHERE su.uuid = $1
          AND rr.region_id  = $2
   )
$$;


\echo admin.apply_rls_and_policies
CREATE OR REPLACE FUNCTION admin.apply_rls_and_policies(table_regclass regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    has_custom_and_active boolean;
BEGIN
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = table_regclass;

    -- Check if table has 'custom' and 'active' columns
    SELECT EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = table_regclass
        AND attname IN ('custom', 'active')
        GROUP BY attrelid
        HAVING COUNT(*) = 2
    ) INTO has_custom_and_active;

    RAISE NOTICE '%s.%s: Enabling Row Level Security', schema_name_str, table_name_str;
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name_str, table_name_str);

    RAISE NOTICE '%s.%s: Authenticated users can read', schema_name_str, table_name_str;
    EXECUTE format('CREATE POLICY %s_authenticated_read ON %I.%I FOR SELECT TO authenticated USING (true)', table_name_str, schema_name_str, table_name_str);

    -- The tables with custom and active are managed through views,
    -- where one _system view is used for system updates, and the
    -- _custom view is used for managing custom rows by the super_user.
    IF has_custom_and_active THEN
        RAISE NOTICE '%s.%s: regular_user(s) can read', schema_name_str, table_name_str;
        EXECUTE format('CREATE POLICY %s_regular_user_read ON %I.%I FOR SELECT TO authenticated USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
    ELSE
        RAISE NOTICE '%s.%s: regular_user(s) can manage', schema_name_str, table_name_str;
        EXECUTE format('CREATE POLICY %s_regular_user_manage ON %I.%I FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
    END IF;

    RAISE NOTICE '%s.%s: super_user(s) can manage', schema_name_str, table_name_str;
    EXECUTE format('CREATE POLICY %s_super_user_manage ON %I.%I FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
END;
$$ LANGUAGE plpgsql;



\echo admin.enable_rls_on_public_tables
CREATE OR REPLACE FUNCTION admin.enable_rls_on_public_tables()
RETURNS void AS $$
DECLARE
    table_regclass regclass;
BEGIN
    FOR table_regclass IN
        SELECT c.oid::regclass
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
    LOOP
        PERFORM admin.apply_rls_and_policies(table_regclass);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.enable_rls_on_public_tables();
SET LOCAL client_min_messages TO INFO;

-- Allow access read to the admin schema for all users,
-- as some nested UPSERT queries use views that call functions that require this.
-- This is strange, as there is no specific access to anything inside
-- admin that is requried.
GRANT USAGE ON SCHEMA admin TO authenticated;


\echo admin.grant_type_and_function_access_to_authenticated
CREATE OR REPLACE FUNCTION admin.grant_type_and_function_access_to_authenticated()
RETURNS void AS $$
DECLARE
    rec record;
    query text;
BEGIN
    -- Grant usage on the schema
    query := 'GRANT USAGE ON SCHEMA admin TO authenticated';
    RAISE DEBUG 'Executing query: %', query;
    EXECUTE query;

    -- Grant usage on all enum types in admin schema
    FOR rec IN SELECT typname FROM pg_type JOIN pg_namespace ON pg_type.typnamespace = pg_namespace.oid WHERE nspname = 'admin' AND typtype = 'e'
    LOOP
        query := format('GRANT USAGE ON TYPE admin.%I TO authenticated', rec.typname);
        RAISE DEBUG 'Executing query: %', query;
        EXECUTE query;
    END LOOP;

    -- Grant execute on all functions in admin schema
    FOR rec IN SELECT p.proname, n.nspname, p.oid,
                      pg_catalog.pg_get_function_identity_arguments(p.oid) as func_args
               FROM pg_proc p
               JOIN pg_namespace n ON p.pronamespace = n.oid
               WHERE n.nspname = 'admin'
    LOOP
        query := format('GRANT EXECUTE ON FUNCTION admin.%I(%s) TO authenticated', rec.proname, rec.func_args);
        RAISE DEBUG 'Executing query: %', query;
        EXECUTE query;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- TODO: Remove this if there is no need to grant specific read access to admin objects used by nested triggers.
--SET LOCAL client_min_messages TO DEBUG;
--SELECT admin.grant_type_and_function_access_to_authenticated();
--SET LOCAL client_min_messages TO INFO;


-- The employees can only update the tables designated by their assigned region or activity_category
CREATE POLICY activity_employee_manage ON public.activity FOR ALL TO authenticated
USING (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      )
WITH CHECK (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      );

--CREATE POLICY "premium and admin view access" ON premium_records FOR ALL TO authenticated USING (has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[]));

-- Activate era handling
SELECT sql_saga.add_era('public.enterprise_group', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['id']);

SELECT sql_saga.add_era('public.legal_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['id']);
-- TODO: Use a scoped sql_saga unique key for enterprise_id below.
-- SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['enterprise_id'], WHERE 'primary_for_enterprise');

SELECT sql_saga.add_era('public.establishment', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['id']);
-- TODO: Extend sql_saga with support for predicates by using unique indices instead of constraints.
--SELECT sql_saga.add_unique_key('public.establishment', ARRAY['legal_unit_id'], WHERE 'primary_for_legal_unit');
SELECT sql_saga.add_foreign_key('public.establishment', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.activity', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.activity', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.stat_for_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['stat_definition_id', 'establishment_id']);
SELECT sql_saga.add_foreign_key('public.stat_for_unit', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');

SELECT sql_saga.add_era('public.location', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.location', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.location', ARRAY['type', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.location', ARRAY['type', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.location', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.location', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

TABLE sql_saga.era;
TABLE sql_saga.unique_keys;
TABLE sql_saga.foreign_keys;


NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

END;
