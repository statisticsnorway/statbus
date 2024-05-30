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
--ALTER DATABASE "statbus" SET datestyle TO 'ISO, DMY';
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


\echo public.activity_category_standard
CREATE TABLE public.activity_category_standard (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code character varying(16) UNIQUE NOT NULL,
    name character varying UNIQUE NOT NULL,
    obsolete boolean NOT NULL DEFAULT false
);

INSERT INTO public.activity_category_standard(code, name)
VALUES ('isic_v4','ISIC Version 4')
     , ('nace_v2.1','NACE Version 2 Revision 1');

CREATE EXTENSION ltree SCHEMA public;

\echo public.activity_category
CREATE TABLE public.activity_category (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    path public.ltree NOT NULL,
    parent_id integer REFERENCES public.activity_category(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (regexp_replace(regexp_replace(path::text, '[^0-9]', '', 'g'),'^([0-9]{2})(.+)$','\1.\2','')) STORED,
    name character varying(256) NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(standard_id, path, active)
);
CREATE INDEX ix_activity_category_parent_id ON public.activity_category USING btree (parent_id);


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
     , acp.code AS parent_code
     , ac.label
     , ac.code
     , ac.name
     , ac.description
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


-- import structures
\echo public.import_strategy
CREATE TYPE public.import_strategy AS ENUM ('create_or_replace','update_existing');
\echo public.import_type
CREATE TYPE public.import_type AS ENUM ('establishment','legal_unit','enterprise','enterprise_group','activities');

\echo public.import_definition
CREATE TABLE public.import_definition (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type public.import_type NOT NULL,
    name text NOT NULL,
    description text,
    strategy public.import_strategy NOT NULL,
    delete_missing BOOL,
    source_column_names text[],
    csv_delimiter text,
    csv_skip_count integer CHECK(csv_skip_count >= 0),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    CHECK(CASE strategy
        WHEN 'create_or_replace' THEN delete_missing IS NOT NULL
        WHEN 'update_existing' THEN delete_missing IS NULL
        END
        )
);
CREATE UNIQUE INDEX ix_import_definition_name ON public.import_definition USING btree (name);
CREATE INDEX ix_import_definition_user_id ON public.import_definition USING btree (user_id);

\echo public.import_mapping
CREATE TABLE public.import_mapping (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_definition_id integer REFERENCES public.import_definition(id) ON DELETE CASCADE,
    source_name TEXT,
    source_value TEXT,
    target_name TEXT NOT NULL,
    CHECK( source_name IS NOT NULL AND source_value IS NULL
        OR source_name IS NULL AND source_value IS NOT NULL
        )
);

\echo public.import_job_status
CREATE TYPE public.import_job_status AS ENUM ('in_queue', 'loading', 'data_load_completed', 'data_load_completed_partially', 'data_load_failed');
\echo public.import_job
CREATE TABLE public.import_job (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    start_at timestamp with time zone,
    stop_at timestamp with time zone,
    import_file_path_and_name text NOT NULL,
    description text,
    status public.import_job_status NOT NULL,
    note text,
    import_definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    skip_lines_count integer NOT NULL
);
CREATE INDEX ix_import_job_import_definition_id ON public.import_job USING btree (import_definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);

\echo public.import_log_status
CREATE TYPE public.import_log_status AS ENUM ('done', 'warning', 'error');
\echo public.import_log
CREATE TABLE public.import_log (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    start_at timestamp with time zone,
    stop_at timestamp with time zone,
    target_stat_ident text,
    stat_unit_name text,
    serialized_unit JSONB, -- Uses system names.
    import_job_id integer NOT NULL REFERENCES public.import_job(id) ON DELETE CASCADE,
    status public.import_log_status NOT NULL,
    note text,
    errors text,
    summary text
);
CREATE INDEX ix_import_log_import_job_id ON public.import_log USING btree (import_job_id);


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


\echo public.relative_period_type
CREATE TYPE public.relative_period_type AS ENUM (
    -- For data entry with context_valid_from and context_valid_to. context_valid_on should be context_valid_from when infinity, else context_valid_to
    'today',
    'year_prev_until_infinity',
    'year_prev_only',
    'year_curr_until_infinity',
    'year_curr_only',

    -- For data search with context_valid_on only, no context_valid_from and context_valid_to
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

CREATE TABLE public.relative_period (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name character varying(256) NOT NULL,
    type public.relative_period_type UNIQUE,
    active boolean NOT NULL DEFAULT true
);

\echo public.relative_period_with_time
CREATE VIEW public.relative_period_with_time AS
SELECT *,
       CASE type -- context_valid_on
           WHEN 'today' THEN current_date
           --
           WHEN 'year_prev_until_infinity' THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_prev_only'           THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_curr_until_infinity' THEN current_date
           WHEN 'year_curr_only'           THEN current_date
            --
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
       CASE type
           WHEN 'today' THEN current_date
           --
           WHEN 'year_prev_until_infinity' THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_prev_only'           THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_curr_until_infinity' THEN date_trunc('year', current_date)::DATE
           WHEN 'year_curr_only'           THEN date_trunc('year', current_date)::DATE
           --
           ELSE NULL
       END::DATE AS valid_from,
       CASE type
           WHEN 'today'                    THEN 'infinity'::DATE
           WHEN 'year_prev_until_infinity' THEN 'infinity'::DATE
           WHEN 'year_curr_until_infinity' THEN 'infinity'::DATE
           WHEN 'year_prev_only' THEN date_trunc('year', current_date)::DATE - interval '1 day'
           WHEN 'year_curr_only' THEN date_trunc('year', current_date + interval '1 year')::DATE - interval '1 day'
           ELSE NULL
       END::DATE as valid_to
FROM public.relative_period;


DO $$
DECLARE
    parent_id integer;
BEGIN
    INSERT INTO public.relative_period (name, type, active)
    VALUES
        ('Today', 'today', true),
        --
        ('Previous Year until Infinity', 'year_prev_until_infinity', true),
        ('Only Previous Year', 'year_prev_only', true),
        ('Current Year until Infinity', 'year_curr_until_infinity', true),
        ('Only Current Year', 'year_curr_only', true),
        --
        ('Start of Current Week', 'start_of_week_curr', true),
        ('End of Previous Week', 'stop_of_week_prev', true),
        ('Start of Previous Week', 'start_of_week_prev', true),
        ('Start of Current Month', 'start_of_month_curr', true),
        ('End of Previous Month', 'stop_of_month_prev', true),
        ('Start of Previous Month', 'start_of_month_prev', true),
        ('Start of Current Quarter', 'start_of_quarter_curr', true),
        ('End of Previous Quarter', 'stop_of_quarter_prev', true),
        ('Start of Previous Quarter', 'start_of_quarter_prev', true),
        ('Start of Current Semester', 'start_of_semester_curr', true),
        ('End of Previous Semester', 'stop_of_semester_prev', true),
        ('Start of Previous Semester', 'start_of_semester_prev', true),
        ('Start of Current Year', 'start_of_year_curr', true),
        ('End of Previous Year', 'stop_of_year_prev', true),
        ('Start of Previous Year', 'start_of_year_prev', true),
        ('Start of Current Five-Year Period', 'start_of_quinquennial_curr', true),
        ('End of Previous Five-Year Period', 'stop_of_quinquennial_prev', true),
        ('Start of Previous Five-Year Period', 'start_of_quinquennial_prev', true),
        ('Start of Current Decade', 'start_of_decade_curr', true),
        ('End of Previous Decade', 'stop_of_decade_prev', true),
        ('Start of Previous Decade', 'start_of_decade_prev', true)
    ;
END $$;



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
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident text,
    external_ident text,
    external_ident_type text,
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
CREATE FUNCTION admin.enterprise_group_id_exists(fk_id integer) RETURNS boolean AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.enterprise_group WHERE id = fk_id);
$$ LANGUAGE sql IMMUTABLE;

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
CREATE UNIQUE INDEX ix_sector ON public.sector USING btree (code) WHERE active;
CREATE INDEX ix_sector_parent_id ON public.sector USING btree (parent_id);


\echo public.enterprise
CREATE TABLE public.enterprise (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    stat_ident character varying(15) UNIQUE,
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
CREATE UNIQUE INDEX ix_legal_form_code ON public.legal_form USING btree (code) WHERE active;

\echo public.legal_unit
CREATE TABLE public.legal_unit (
    id SERIAL NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident character varying(15),
    tax_ident character varying(50),
    external_ident character varying(50),
    external_ident_type character varying(50),
    by_tag_id integer REFERENCES public.tag(id) ON DELETE RESTRICT,
    by_tag_id_unique_ident varchar(64),
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
    invalid_codes jsonb,
    seen_in_import_at timestamp with time zone DEFAULT statement_timestamp(),
    CONSTRAINT "by_tag_id and by_tag_id_unique_ident are all or nothing"
    CHECK( by_tag_id IS     NULL AND by_tag_id_unique_ident IS     NULL
        OR by_tag_id IS NOT NULL AND by_tag_id_unique_ident IS NOT NULL
         )
);

-- TODO: Use a scoped sql_saga unique key for enterprise_id below.
CREATE UNIQUE INDEX "Only one primary legal_unit per enterprise" ON public.legal_unit(enterprise_id) WHERE primary_for_enterprise;
CREATE INDEX legal_unit_valid_to_idx ON public.legal_unit(tax_ident) WHERE valid_to = 'infinity';
CREATE INDEX legal_unit_active_idx ON public.legal_unit(active);
CREATE INDEX ix_legal_unit_data_source_id ON public.legal_unit USING btree (data_source_id);
CREATE INDEX ix_legal_unit_enterprise_id ON public.legal_unit USING btree (enterprise_id);
CREATE INDEX ix_legal_unit_foreign_participation_id ON public.legal_unit USING btree (foreign_participation_id);
CREATE INDEX ix_legal_unit_sector_id ON public.legal_unit USING btree (sector_id);
CREATE INDEX ix_legal_unit_legal_form_id ON public.legal_unit USING btree (legal_form_id);
CREATE INDEX ix_legal_unit_name ON public.legal_unit USING btree (name);
CREATE INDEX ix_legal_unit_reorg_type_id ON public.legal_unit USING btree (reorg_type_id);
CREATE INDEX ix_legal_unit_short_name_reg_ident_stat_ident_tax ON public.legal_unit USING btree (short_name, stat_ident, tax_ident);
CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (unit_size_id);
CREATE INDEX ix_legal_unit_stat_ident ON public.legal_unit USING btree (stat_ident);


\echo admin.legal_unit_id_exists
CREATE FUNCTION admin.legal_unit_id_exists(fk_id integer) RETURNS boolean AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.legal_unit WHERE id = fk_id);
$$ LANGUAGE sql IMMUTABLE;

\echo public.establishment
CREATE TABLE public.establishment (
    id SERIAL NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident character varying(15),
    tax_ident character varying(50),
    external_ident character varying(50),
    external_ident_type character varying(50),
    by_tag_id integer REFERENCES public.tag(id) ON DELETE RESTRICT,
    by_tag_id_unique_ident varchar(64),
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
    seen_in_import_at timestamp with time zone DEFAULT statement_timestamp(),
    CONSTRAINT "Must have either legal_unit_id or enterprise_id"
    CHECK( enterprise_id IS NOT NULL AND legal_unit_id IS     NULL
        OR enterprise_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    CONSTRAINT "primary_for_legal_unit and legal_unit_id must be defined together"
    CHECK( legal_unit_id IS NOT NULL AND primary_for_legal_unit IS NOT NULL
        OR legal_unit_id IS     NULL AND primary_for_legal_unit IS     NULL
        ),
    CONSTRAINT "enterprise_id enables sector_id"
    CHECK( CASE WHEN enterprise_id IS NULL THEN sector_id IS NULL END),
    CONSTRAINT "by_tag_id and by_tag_id_unique_ident are all or nothing"
    CHECK( by_tag_id IS     NULL AND by_tag_id_unique_ident IS     NULL
        OR by_tag_id IS NOT NULL AND by_tag_id_unique_ident IS NOT NULL
         )

);

CREATE INDEX establishment_valid_to_idx ON public.establishment(tax_ident) WHERE valid_to = 'infinity';
CREATE INDEX establishment_active_idx ON public.establishment(active);
CREATE INDEX ix_establishment_data_source_id ON public.establishment USING btree (data_source_id);
CREATE INDEX ix_establishment_sector_id ON public.establishment USING btree (sector_id);
CREATE INDEX ix_establishment_enterprise_id ON public.establishment USING btree (enterprise_id);
CREATE INDEX ix_establishment_legal_unit_id ON public.establishment USING btree (legal_unit_id);
CREATE INDEX ix_establishment_name ON public.establishment USING btree (name);
CREATE INDEX ix_establishment_reorg_type_id ON public.establishment USING btree (reorg_type_id);
CREATE INDEX ix_establishment_short_name_reg_ident_stat_ident_tax ON public.establishment USING btree (short_name, stat_ident, tax_ident);
CREATE INDEX ix_establishment_size_id ON public.establishment USING btree (unit_size_id);
CREATE INDEX ix_establishment_stat_ident ON public.establishment USING btree (stat_ident);


\echo admin.establishment_id_exists
CREATE OR REPLACE FUNCTION admin.establishment_id_exists(fk_id integer) RETURNS boolean AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.establishment WHERE id = fk_id);
$$ LANGUAGE sql IMMUTABLE;



CREATE TYPE public.activity_type AS ENUM ('primary', 'secondary', 'ancilliary');

\echo public.activity
CREATE TABLE public.activity (
    id SERIAL NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    type public.activity_type NOT NULL,
    category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
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
CREATE INDEX ix_activity_establishment_id_id ON public.activity USING btree (establishment_id);
CREATE INDEX ix_activity_legal_unit_id_id ON public.activity USING btree (legal_unit_id);
CREATE INDEX ix_activity_updated_by_user_id ON public.activity USING btree (updated_by_user_id);


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
    CONSTRAINT "parent_id is required for child"
      CHECK(public.nlevel(path) = 1 OR parent_id IS NOT NULL)
);
CREATE INDEX ix_region_parent_id ON public.region USING btree (parent_id);
CREATE TYPE public.location_type AS ENUM ('physical', 'postal');

\echo public.location
CREATE TABLE public.location (
    id SERIAL NOT NULL,
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
    latitude double precision,
    longitude double precision,
    establishment_id integer,
    legal_unit_id integer,
    updated_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE RESTRICT,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_address_region_id ON public.location USING btree (region_id);
CREATE INDEX ix_location_establishment_id_id ON public.location USING btree (establishment_id);
CREATE INDEX ix_location_legal_unit_id_id ON public.location USING btree (legal_unit_id);
CREATE INDEX ix_location_updated_by_user_id ON public.location USING btree (updated_by_user_id);


-- Create a view for region upload using path and name
\echo public.region_upload
CREATE VIEW public.region_upload
WITH (security_invoker=on) AS
SELECT path, name
FROM public.region
ORDER BY path;
COMMENT ON VIEW public.region_upload IS 'Upload of region by path,name that automatically connects parent_id';

\echo admin.region_upload_upsert
CREATE FUNCTION admin.region_upload_upsert()
RETURNS TRIGGER AS $$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.region
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.region (path, parent_id, name)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name)
    ON CONFLICT (path)
    DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name
    WHERE region.id = EXCLUDED.id;
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
CREATE TYPE admin.view_type_enum AS ENUM ('system', 'custom');


\echo admin.generate_view
CREATE FUNCTION admin.generate_view(table_name regclass, view_type admin.view_type_enum)
RETURNS regclass AS $generate_view$
DECLARE
    view_sql text;
    view_name_str text;
    view_name regclass;
    custom_condition text;
    schema_name_str text;
    table_name_str text;
BEGIN
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view name without duplicating the schema
    view_name_str := table_name_str || '_' || view_type::text;

    -- Determine custom condition based on view type
    IF view_type = 'system' THEN
        custom_condition := 'false';
    ELSIF view_type = 'custom' THEN
        custom_condition := 'true';
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- Construct the SQL statement for the view
    view_sql := format('CREATE VIEW public.%I WITH (security_invoker=on) AS SELECT * FROM %I.%I WHERE custom = %s',
                       view_name_str, schema_name_str, table_name_str, custom_condition);

    EXECUTE view_sql;

    view_name := format('public.%I', view_name_str)::regclass;
    RAISE NOTICE 'Created view: %', view_name;

    RETURN view_name;
END;
$generate_view$ LANGUAGE plpgsql;


\echo admin.generate_active_code_custom_unique_constraint
CREATE FUNCTION admin.generate_active_code_custom_unique_constraint(table_name regclass)
RETURNS VOID AS $generate_active_code_custom_unique_constraint$
-- Construct the SQL constraint for the upsert function
    DECLARE
        table_name_str text;
        constraint_sql text;
    BEGIN
        SELECT relname INTO table_name_str
        FROM pg_catalog.pg_class
        WHERE oid = table_name;

        constraint_sql := format($$
            CREATE UNIQUE INDEX ix_%1$s_active_code_custom ON public.%1$I USING btree (active, code, custom);
        $$, table_name_str);
        EXECUTE constraint_sql;
        RAISE NOTICE 'Created unique constraint on %(active, code, custom)', table_name_str;
    END;
$generate_active_code_custom_unique_constraint$ LANGUAGE plpgsql;


\echo admin.generate_code_upsert_function
CREATE FUNCTION admin.generate_code_upsert_function(table_name regclass, view_type admin.view_type_enum)
RETURNS regprocedure AS $generate_code_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
    content_columns text := 'name';
    content_values text := 'NEW.name';
    content_update_sets text := 'name = NEW.name';
    has_description boolean;
BEGIN
    -- Extract table name without schema
    SELECT relname INTO table_name_str
    FROM pg_catalog.pg_class
    WHERE oid = table_name;

    -- Check if table has 'description' column
    SELECT EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = table_name
        AND attname = 'description'
    ) INTO has_description;
    IF has_description THEN
        content_columns := content_columns || ', description';
        content_values := content_values || ', NEW.description';
        content_update_sets := content_update_sets || ', description = NEW.description';
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

    -- Construct the SQL statement for the upsert function
    function_sql := format($$CREATE FUNCTION %I.%I()
                            RETURNS TRIGGER AS $body$
                            BEGIN
                                INSERT INTO %s (code, %s, active, custom, updated_at)
                                VALUES (NEW.code, %s, %L, %L, statement_timestamp())
                                ON CONFLICT (active, code, custom) DO UPDATE SET
                                    %s,
                                    custom = %L,
                                    updated_at = statement_timestamp()
                                WHERE %I.id = EXCLUDED.id;
                                RETURN NULL;
                            END;
                            $body$ LANGUAGE plpgsql;$$,
                            function_schema, function_name_str, table_name, content_columns, content_values, not custom_value, custom_value, content_update_sets, custom_value, table_name_str);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created code-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_code_upsert_function$ LANGUAGE plpgsql;




\echo admin.generate_path_upsert_function
CREATE FUNCTION admin.generate_path_upsert_function(table_name regclass, view_type admin.view_type_enum)
RETURNS regprocedure AS $generate_path_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
BEGIN
    -- Extract table name without schema
    SELECT relname INTO table_name_str
    FROM pg_catalog.pg_class
    WHERE oid = table_name;

    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- Construct the SQL statement for the upsert function
    function_sql := format($$CREATE FUNCTION %I.%I()
                            RETURNS TRIGGER AS $body$
                            BEGIN
                                WITH parent AS (
                                    SELECT id
                                    FROM %s
                                    WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
                                )
                                INSERT INTO %s (path, parent_id, name, active, custom, updated_at)
                                VALUES (NEW.path, (SELECT id FROM parent), NEW.name, %L, %L, statement_timestamp())
                                ON CONFLICT (path) DO UPDATE SET
                                    parent_id = (SELECT id FROM parent),
                                    name = EXCLUDED.name,
                                    custom = %L,
                                    updated_at = statement_timestamp()
                                WHERE %I.id = EXCLUDED.id;
                                RETURN NULL;
                            END;
                            $body$ LANGUAGE plpgsql;$$,
                            function_schema, function_name_str, table_name, table_name, not custom_value, custom_value, custom_value, table_name_str);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created path-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_path_upsert_function$ LANGUAGE plpgsql;



\echo admin.generate_delete_function
CREATE FUNCTION admin.generate_delete_function(table_name regclass, view_type admin.view_type_enum)
RETURNS regprocedure AS $generate_delete_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
BEGIN
    -- Extract table name without schema
    SELECT relname INTO table_name_str
    FROM pg_catalog.pg_class
    WHERE oid = table_name;

    function_name_str := 'delete_stale_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- Construct the SQL statement for the delete function
    function_sql := format($$CREATE FUNCTION %I.%I()
                            RETURNS TRIGGER AS $body$
                            BEGIN
                                DELETE FROM %s
                                WHERE custom = %L AND updated_at < statement_timestamp();
                                RETURN NULL;
                            END;
                            $body$ LANGUAGE plpgsql;$$,
                            function_schema, function_name_str, table_name, custom_value);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created delete function: %', function_name;

    RETURN function_name;
END;
$generate_delete_function$ LANGUAGE plpgsql;



\echo admin.generate_view_triggers
CREATE FUNCTION admin.generate_view_triggers(view_name regclass, upsert_function_name regprocedure, delete_function_name regprocedure)
RETURNS text[] AS $generate_triggers$
DECLARE
    view_name_str text;
    upsert_trigger_sql text;
    delete_trigger_sql text;
    upsert_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    upsert_trigger_name text;
    delete_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    delete_trigger_name text;
BEGIN
    -- Lookup view_name_str
    SELECT relname INTO view_name_str
    FROM pg_catalog.pg_class
    WHERE oid = view_name;

    upsert_trigger_name_str := 'upsert_' || view_name_str;
    delete_trigger_name_str := 'delete_stale_' || view_name_str;

    -- Construct the SQL statement for the upsert trigger
    upsert_trigger_sql := format($$CREATE TRIGGER %I
                                  INSTEAD OF INSERT ON %s
                                  FOR EACH ROW
                                  EXECUTE FUNCTION %s;$$,
                                  upsert_trigger_name_str, view_name::text, upsert_function_name::text);

    -- Construct the SQL statement for the delete trigger
    delete_trigger_sql := format($$CREATE TRIGGER %I
                                  AFTER INSERT ON %s
                                  FOR EACH STATEMENT
                                  EXECUTE FUNCTION %s;$$,
                                  delete_trigger_name_str, view_name::text, delete_function_name::text);

    -- Log and execute
    EXECUTE upsert_trigger_sql;
    EXECUTE delete_trigger_sql;

    upsert_trigger_name := format('public.%I',upsert_trigger_name_str);
    delete_trigger_name := format('public.%I',delete_trigger_name_str);

    RAISE NOTICE 'Created upsert trigger: %', upsert_trigger_name;
    RAISE NOTICE 'Created delete trigger: %', delete_trigger_name;

    -- Return the regclass identifiers of the created triggers
    RETURN ARRAY[upsert_trigger_name, delete_trigger_name];
END;
$generate_triggers$ LANGUAGE plpgsql;



CREATE TYPE admin.table_type_enum AS ENUM ('code', 'path');

\echo admin.generate_table_views_for_batch_api
CREATE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass, table_type admin.table_type_enum)
RETURNS void AS $$
DECLARE
    view_name_system regclass;
    view_name_custom regclass;
    upsert_function_name_system regprocedure;
    upsert_function_name_custom regprocedure;
    delete_function_name_system regprocedure;
    delete_function_name_custom regprocedure;
    triggers_name_system text[];
    triggers_name_custom text[];
BEGIN
    view_name_system := admin.generate_view(table_name, 'system');
    view_name_custom := admin.generate_view(table_name, 'custom');

    PERFORM admin.generate_active_code_custom_unique_constraint(table_name);

    IF table_type = 'code' THEN
        upsert_function_name_system := admin.generate_code_upsert_function(table_name,'system');
        upsert_function_name_custom := admin.generate_code_upsert_function(table_name,'custom');
    ELSIF table_type = 'path' THEN
        upsert_function_name_system := admin.generate_path_upsert_function(table_name,'system');
        upsert_function_name_custom := admin.generate_path_upsert_function(table_name,'custom');
    ELSE
        RAISE EXCEPTION 'Invalid table type: %', table_type;
    END IF;

    delete_function_name_system := admin.generate_delete_function(table_name, 'system');
    delete_function_name_custom := admin.generate_delete_function(table_name, 'custom');

    triggers_name_system := admin.generate_view_triggers(view_name_system, upsert_function_name_system, delete_function_name_system);
    triggers_name_custom := admin.generate_view_triggers(view_name_custom, upsert_function_name_custom, delete_function_name_custom);
END;
$$ LANGUAGE plpgsql;


\echo admin.drop_table_views_for_batch_api
CREATE OR REPLACE FUNCTION admin.drop_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    view_name_system text;
    view_name_custom text;
    upsert_function_name_system text;
    upsert_function_name_custom text;
    delete_function_name_system text;
    delete_function_name_custom text;
BEGIN
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view and function names
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';
    delete_function_name_system := 'admin.delete_stale_' || table_name_str || '_system';
    delete_function_name_custom := 'admin.delete_stale_' || table_name_str || '_custom';

    -- Drop views
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_custom;

    -- Drop functions
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_custom || '()';
    EXECUTE 'DROP FUNCTION ' || delete_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || delete_function_name_custom || '()';
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
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('employees','int','yearly','Number of people employed','The number of people receiving an official salary with government reporting.',2),
  ('turnover','int','yearly','Turnover','The amount (EUR)',3);

\echo public.stat_for_unit
CREATE TABLE public.stat_for_unit (
    id SERIAL NOT NULL,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE RESTRICT,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    establishment_id integer NOT NULL,
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


-- Functions to manage connections between enterprise <-> legal_unit <-> establishment
CREATE OR REPLACE FUNCTION public.set_primary_legal_unit_for_enterprise(
    legal_unit_id integer,
    valid_from date DEFAULT current_date,
    valid_to date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_enterprise_id integer;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT enterprise_id INTO v_enterprise_id FROM public.legal_unit WHERE id = legal_unit_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Legal unit does not exist.';
    END IF;

    -- Unset all legal units of the enterprise from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = false
        WHERE primary_for_enterprise
          AND enterprise_id = v_enterprise_id
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'legal_unit', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified legal unit as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.legal_unit
        SET primary_for_enterprise = true
        WHERE id = legal_unit_id
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


CREATE OR REPLACE FUNCTION public.set_primary_establishment_for_legal_unit(
    establishment_id integer,
    valid_from date DEFAULT current_date,
    valid_to date DEFAULT 'infinity'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_legal_unit_id integer;
    v_unset_ids jsonb := '[]';
    v_set_id jsonb := 'null';
BEGIN
    SELECT legal_unit_id INTO v_legal_unit_id FROM public.establishment WHERE id = establishment_id;
    IF v_legal_unit_id IS NULL THEN
        RAISE EXCEPTION 'Establishment does not exist or is not linked to a legal unit.';
    END IF;

    -- Unset all establishments of the legal unit from being primary and capture their ids and table name
    WITH updated_rows AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = false
        WHERE primary_for_legal_unit
          AND legal_unit_id = v_legal_unit_id
        RETURNING id
    )
    SELECT jsonb_agg(jsonb_build_object('table', 'establishment', 'id', id)) INTO v_unset_ids FROM updated_rows;

    -- Set the specified establishment as primary, capture its id and table name
    WITH updated_row AS (
        UPDATE public.establishment
        SET primary_for_legal_unit = true
        WHERE id = establishment_id
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
        'updated_legal_unit', updated_legal_unit_ids,
        'old_enterprise', old_enterprise_id,
        'new_enterprise', enterprise_id,
        'deleted_enterprise', deleted_enterprise_id
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

\echo public.statistical_unit_def
CREATE VIEW public.statistical_unit_def
    ( valid_from
    , valid_to
    , unit_type
    , unit_id
    , stat_ident
    , tax_ident
    , external_ident
    , external_ident_type
    , by_tag_id
    , by_tag_id_unique_ident
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
    , aggregated_establishment_ids
    , aggregated_legal_unit_ids
    , aggregated_enterprise_ids
    , employees
    , turnover
    , tag_paths
    -- TODO: Generate SQL to provide these columns:
    -- legal_form_id integer,
    -- sector_ids integer[],
    -- activity_category_ids integer[],
    -- unit_size_id integer REFERENCES public.unit_size(id),
    -- short_name character varying(200),
    -- tax_ident character varying(50),
    -- external_ident character varying(50),
    -- external_ident_type character varying(50),
    -- data_source character varying(200),
    -- web_address character varying(200),
    -- telephone_no character varying(50),
    -- email_address character varying(50),
    -- free_econ_zone boolean NOT NULL,
    -- liq_date timestamp with time zone,
    -- liq_reason character varying(200),
    -- user_id character varying(100) NOT NULL,
    -- edit_comment character varying(500),
    -- data_source_id integer REFERENCES public.data_source(id),
    -- reorg_type_id integer REFERENCES public.reorg_type(id),
    -- active boolean,
    )
    AS
    WITH data AS (
    -- Establishment
    SELECT valid_from
         , valid_to
         , unit_type
         , unit_id
         , stat_ident
         , tax_ident
         , external_ident
         , external_ident_type
         , by_tag_id
         , by_tag_id_unique_ident
         , name
         , birth_date
         , death_date
         , search
         --
         , primary_activity_category_id
         , primary_activity_category_path
         --
         , secondary_activity_category_id
         , secondary_activity_category_path
         --
         , activity_category_paths
         --
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postal_code
         , physical_postal_place
         , physical_region_id
         , physical_region_path
         , physical_country_id
         , physical_country_iso_2
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postal_code
         , postal_postal_place
         , postal_region_id
         , postal_region_path
         , postal_country_id
         , postal_country_iso_2
         --
         , invalid_codes
         --
         , array_agg(distinct establishment_id) filter (where establishment_id is not null) AS aggregated_establishment_ids
         , array_agg(distinct legal_unit_id) filter (where legal_unit_id is not null) AS aggregated_legal_unit_ids
         , array_agg(distinct enterprise_id) filter (where enterprise_id is not null) AS aggregated_enterprise_ids
         , sum(employees) AS employees
         , sum(turnover) AS turnover
    FROM (
      SELECT greatest(es.valid_from, pa.valid_from, sa.valid_from, phl.valid_from, sfu1.valid_from, sfu2.valid_from) AS valid_from
           , least(es.valid_to, pa.valid_to, sa.valid_to, phl.valid_to, sfu1.valid_to, sfu2.valid_to) AS valid_to
           , 'establishment'::public.statistical_unit_type AS unit_type
           , es.id AS unit_id
           , es.id AS establishment_id
           , NULL::INTEGER AS legal_unit_id
           , NULL::INTEGER AS enterprise_id
           , NULL::INTEGER AS enterprise_group_id
           , es.stat_ident AS stat_ident
           , es.tax_ident AS tax_ident
           , es.external_ident AS external_ident
           , es.external_ident_type AS external_ident_type
           , es.by_tag_id    AS by_tag_id
           , es.by_tag_id_unique_ident AS by_tag_id_unique_ident
           , es.name AS name
           , es.birth_date AS birth_date
           , es.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , -- to_tsvector('norwegian', es.name) ||
             -- to_tsvector('english', es.name) ||
             -- to_tsvector('arabic', es.name) ||
             -- to_tsvector('greek', es.name) ||
             -- to_tsvector('russian', es.name) ||
             -- to_tsvector('french', es.name) ||
             to_tsvector('simple', es.name) AS search
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
           , sfu1.value_int AS employees
           , sfu2.value_int AS turnover
      FROM public.establishment AS es
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = es.id
             AND pa.type = 'primary'
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(pa.valid_from, pa.valid_to, '[]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = es.id
             AND sa.type = 'secondary'
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(sa.valid_from, sa.valid_to, '[]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON es.sector_id = s.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.establishment_id = es.id
             AND phl.type = 'physical'
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(phl.valid_from, phl.valid_to, '[]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = es.id
             AND pol.type = 'postal'
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(pol.valid_from, pol.valid_to, '[]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      --
      LEFT OUTER JOIN public.stat_definition AS sd1
              ON sd1.code = 'employees'
      LEFT OUTER JOIN public.stat_for_unit AS sfu1
              ON sfu1.stat_definition_id = sd1.id
             AND sfu1.establishment_id = es.id
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(sfu1.valid_from, sfu1.valid_to, '[]')
      --
      LEFT OUTER JOIN public.stat_definition AS sd2
              ON sd2.code = 'turnover'
      LEFT OUTER JOIN public.stat_for_unit AS sfu2
              ON sfu2.stat_definition_id = sd2.id
             AND sfu2.establishment_id = es.id
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(sfu2.valid_from, sfu2.valid_to, '[]')
    ) as source
    GROUP BY valid_from
           , valid_to
           , unit_type
           , unit_id
           , stat_ident
           , tax_ident
           , external_ident
           , external_ident_type
           , by_tag_id
           , by_tag_id_unique_ident
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           --
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , legal_form_id
           , legal_form_code
           , legal_form_name
           --
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           --
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           --
           , invalid_codes
           --
           , employees
           , turnover
    UNION ALL
    -- Legal Unit with establishments
    SELECT valid_from
         , valid_to
         , unit_type
         , unit_id
         , stat_ident
         , tax_ident
         , external_ident
         , external_ident_type
         , by_tag_id
         , by_tag_id_unique_ident
         , name
         , birth_date
         , death_date
         , search
         --
         , primary_activity_category_id
         , primary_activity_category_path
         --
         , secondary_activity_category_id
         , secondary_activity_category_path
         --
         , activity_category_paths
         --
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postal_code
         , physical_postal_place
         , physical_region_id
         , physical_region_path
         , physical_country_id
         , physical_country_iso_2
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postal_code
         , postal_postal_place
         , postal_region_id
         , postal_region_path
         , postal_country_id
         , postal_country_iso_2
         --
         , invalid_codes
         --
         , array_agg(distinct establishment_id) filter (where establishment_id is not null) AS aggregated_establishment_ids
         , array_agg(distinct legal_unit_id) filter (where legal_unit_id is not null) AS aggregated_legal_unit_ids
         , array_agg(distinct enterprise_id) filter (where enterprise_id is not null) AS aggregated_enterprise_ids
         , sum(employees) AS employees
         , sum(turnover) AS turnover
      FROM (
        SELECT greatest(lu.valid_from, pa.valid_from, sa.valid_from, phl.valid_from, es.valid_from, sfu1.valid_from, sfu2.valid_from) AS valid_from
             , least(lu.valid_to, pa.valid_to, sa.valid_to, phl.valid_to, es.valid_to, sfu1.valid_to, sfu2.valid_to) AS valid_to
             , 'legal_unit'::public.statistical_unit_type AS unit_type
             , lu.id AS unit_id
             , es.id AS establishment_id
             , lu.id AS legal_unit_id
             , NULL::INTEGER AS enterprise_id
             , NULL::INTEGER AS enterprise_group_id
             , lu.stat_ident AS stat_ident
             , lu.tax_ident AS tax_ident
             , lu.external_ident AS external_ident
             , lu.external_ident_type AS external_ident_type
             , lu.by_tag_id    AS by_tag_id
             , lu.by_tag_id_unique_ident AS by_tag_id_unique_ident
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
             , s.id   AS sector_id
             , s.path AS sector_path
             , s.code AS sector_code
             , s.name AS sector_name
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
             , sfu1.value_int AS employees
             , sfu2.value_int AS turnover
        FROM public.legal_unit AS lu
        --
        LEFT OUTER JOIN public.activity AS pa
                ON pa.legal_unit_id = lu.id
               AND pa.type = 'primary'
               AND daterange(lu.valid_from, lu.valid_to, '[]')
                && daterange(pa.valid_from, pa.valid_to, '[]')
        LEFT JOIN public.activity_category AS pac
                ON pa.category_id = pac.id
        --
        LEFT OUTER JOIN public.activity AS sa
                ON sa.legal_unit_id = lu.id
               AND sa.type = 'secondary'
               AND daterange(lu.valid_from, lu.valid_to, '[]')
                && daterange(sa.valid_from, sa.valid_to, '[]')
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
               AND daterange(lu.valid_from, lu.valid_to, '[]')
                && daterange(phl.valid_from, phl.valid_to, '[]')
        LEFT JOIN public.region AS phr
                ON phl.region_id = phr.id
        LEFT JOIN public.country AS phc
                ON phl.country_id = phc.id
        --
        LEFT OUTER JOIN public.location AS pol
                ON pol.legal_unit_id = lu.id
               AND pol.type = 'postal'
               AND daterange(lu.valid_from, lu.valid_to, '[]')
                && daterange(pol.valid_from, pol.valid_to, '[]')
        LEFT JOIN public.region AS por
                ON pol.region_id = por.id
        LEFT JOIN public.country AS poc
                ON pol.country_id = poc.id
        --
        LEFT OUTER JOIN public.establishment AS es
                ON lu.id = es.legal_unit_id
               AND daterange(lu.valid_from, lu.valid_to, '[]')
                && daterange(es.valid_from, es.valid_to, '[]')
        LEFT OUTER JOIN public.stat_definition AS sd1
                ON sd1.code = 'employees'
        LEFT OUTER JOIN public.stat_for_unit AS sfu1
                ON sfu1.stat_definition_id = sd1.id
               AND sfu1.establishment_id = es.id
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(sfu1.valid_from, sfu1.valid_to, '[]')
        LEFT OUTER JOIN public.stat_definition AS sd2
                ON sd2.code = 'turnover'
        LEFT OUTER JOIN public.stat_for_unit AS sfu2
                ON sfu2.stat_definition_id = sd2.id
               AND sfu2.establishment_id = es.id
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(sfu2.valid_from, sfu2.valid_to, '[]')
    ) AS source
    GROUP BY valid_from
           , valid_to
           , unit_type
           , unit_id
           , stat_ident
           , tax_ident
           , external_ident
           , external_ident_type
           , by_tag_id
           , by_tag_id_unique_ident
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           --
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , legal_form_id
           , legal_form_code
           , legal_form_name
           --
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           --
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
    UNION ALL
    -- Enterprise with legal_unit with establishment
    SELECT valid_from
         , valid_to
         , unit_type
         , unit_id
         , stat_ident
         , tax_ident
         , external_ident
         , external_ident_type
         , by_tag_id
         , by_tag_id_unique_ident
         , name
         , birth_date
         , death_date
         , search
         --
         , primary_activity_category_id
         , primary_activity_category_path
         --
         , secondary_activity_category_id
         , secondary_activity_category_path
         --
         , activity_category_paths
         --
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postal_code
         , physical_postal_place
         , physical_region_id
         , physical_region_path
         , physical_country_id
         , physical_country_iso_2
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postal_code
         , postal_postal_place
         , postal_region_id
         , postal_region_path
         , postal_country_id
         , postal_country_iso_2
         --
         , NULL::JSONB AS invalid_codes
         --
         , array_agg(distinct establishment_id) filter (where establishment_id is not null) AS aggregated_establishment_ids
         , array_agg(distinct legal_unit_id) filter (where legal_unit_id is not null) AS aggregated_legal_unit_ids
         , array_agg(distinct enterprise_id) filter (where enterprise_id is not null) AS aggregated_enterprise_ids
         , sum(employees) AS employees
         , sum(turnover) AS turnover
    FROM (
      SELECT greatest(plu.valid_from, lu.valid_from, pa.valid_from, sa.valid_from, phl.valid_from, es.valid_from, sfu1.valid_from, sfu2.valid_from) AS valid_from
           , least(plu.valid_to, lu.valid_to, pa.valid_to, sa.valid_to, phl.valid_to, es.valid_to, sfu1.valid_to, sfu2.valid_to) AS valid_to
           , 'enterprise'::public.statistical_unit_type AS unit_type
           , en.id AS unit_id
           , es.id AS establishment_id
           , lu.id AS legal_unit_id
           , en.id AS enterprise_id
           , NULL::INTEGER AS enterprise_group_id
           , plu.stat_ident AS stat_ident
           , plu.tax_ident AS tax_ident
           , plu.external_ident AS external_ident
           , plu.external_ident_type AS external_ident_type
           , plu.by_tag_id    AS by_tag_id
           , plu.by_tag_id_unique_ident AS by_tag_id_unique_ident
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
           , sfu1.value_int AS employees
           , sfu2.value_int AS turnover
      FROM public.enterprise AS en
      INNER JOIN public.legal_unit AS plu
              ON plu.enterprise_id = en.id
              AND plu.primary_for_enterprise
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = plu.id
             AND pa.type = 'primary'
             AND daterange(plu.valid_from, plu.valid_to, '[]')
              && daterange(pa.valid_from, pa.valid_to, '[]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = plu.id
             AND sa.type = 'secondary'
             AND daterange(plu.valid_from, plu.valid_to, '[]')
              && daterange(sa.valid_from, sa.valid_to, '[]')
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
             AND daterange(plu.valid_from, plu.valid_to, '[]')
              && daterange(phl.valid_from, phl.valid_to, '[]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = plu.id
             AND pol.type = 'postal'
             AND daterange(plu.valid_from, plu.valid_to, '[]')
              && daterange(pol.valid_from, pol.valid_to, '[]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      --
      LEFT OUTER JOIN public.legal_unit AS lu
              ON lu.enterprise_id = en.id
      LEFT OUTER JOIN public.establishment AS es
              ON lu.id = es.legal_unit_id
             AND daterange(lu.valid_from, lu.valid_to, '[]')
              && daterange(es.valid_from, es.valid_to, '[]')
      LEFT OUTER JOIN public.stat_definition AS sd1
              ON sd1.code = 'employees'
      LEFT OUTER JOIN public.stat_for_unit AS sfu1
              ON sfu1.stat_definition_id = sd1.id
             AND sfu1.establishment_id = es.id
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(sfu1.valid_from, sfu1.valid_to, '[]')
      LEFT OUTER JOIN public.stat_definition AS sd2
              ON sd2.code = 'turnover'
      LEFT OUTER JOIN public.stat_for_unit AS sfu2
              ON sfu2.stat_definition_id = sd2.id
             AND sfu2.establishment_id = es.id
             AND daterange(es.valid_from, es.valid_to, '[]')
              && daterange(sfu2.valid_from, sfu2.valid_to, '[]')
    ) AS source
    GROUP BY valid_from
           , valid_to
           , unit_type
           , unit_id
           , stat_ident
           , tax_ident
           , external_ident
           , external_ident_type
           , by_tag_id
           , by_tag_id_unique_ident
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           --
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , legal_form_id
           , legal_form_code
           , legal_form_name
           --
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           --
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
    UNION ALL
    -- Enterprise with establishment
    SELECT valid_from
         , valid_to
         , unit_type
         , unit_id
         , stat_ident
         , tax_ident
         , external_ident
         , external_ident_type
         , by_tag_id
         , by_tag_id_unique_ident
         , name
         , birth_date
         , death_date
         , search
         --
         , primary_activity_category_id
         , primary_activity_category_path
         --
         , secondary_activity_category_id
         , secondary_activity_category_path
         --
         , activity_category_paths
         --
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postal_code
         , physical_postal_place
         , physical_region_id
         , physical_region_path
         , physical_country_id
         , physical_country_iso_2
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postal_code
         , postal_postal_place
         , postal_region_id
         , postal_region_path
         , postal_country_id
         , postal_country_iso_2
         --
         , NULL::JSONB AS invalid_codes
         --
         , array_agg(distinct establishment_id) filter (where establishment_id is not null) AS aggregated_establishment_ids
         , array_agg(distinct legal_unit_id) filter (where legal_unit_id is not null) AS aggregated_legal_unit_ids
         , array_agg(distinct enterprise_id) filter (where enterprise_id is not null) AS aggregated_enterprise_ids
         , sum(employees) AS employees
         , sum(turnover) AS turnover
      FROM (
        SELECT greatest(es.valid_from, pa.valid_from, sa.valid_from, phl.valid_from, sfu1.valid_from, sfu2.valid_from) AS valid_from
             , least(es.valid_to, pa.valid_to, sa.valid_to, phl.valid_to, sfu1.valid_to, sfu2.valid_to) AS valid_to
             , 'enterprise'::public.statistical_unit_type AS unit_type
             , en.id AS unit_id
             , es.id AS establishment_id
             , NULL::INTEGER AS legal_unit_id
             , en.id AS enterprise_id
             , NULL::INTEGER AS enterprise_group_id
             , es.stat_ident AS stat_ident
             , es.tax_ident AS tax_ident
             , es.external_ident AS external_ident
             , es.external_ident_type AS external_ident_type
             , es.by_tag_id    AS by_tag_id
             , es.by_tag_id_unique_ident AS by_tag_id_unique_ident
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
             , sfu1.value_int AS employees
             , sfu2.value_int AS turnover
        FROM public.enterprise AS en
        INNER JOIN public.establishment AS es
                ON es.enterprise_id = en.id
        --
        LEFT OUTER JOIN public.activity AS pa
                ON pa.legal_unit_id = es.id
               AND pa.type = 'primary'
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(pa.valid_from, pa.valid_to, '[]')
        LEFT JOIN public.activity_category AS pac
                ON pa.category_id = pac.id
        --
        LEFT OUTER JOIN public.activity AS sa
                ON sa.legal_unit_id = es.id
               AND sa.type = 'secondary'
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(sa.valid_from, sa.valid_to, '[]')
        LEFT JOIN public.activity_category AS sac
                ON sa.category_id = sac.id
        --
        LEFT OUTER JOIN public.sector AS s
                ON es.sector_id = s.id
        --
        LEFT OUTER JOIN public.location AS phl
                ON phl.legal_unit_id = es.id
               AND phl.type = 'physical'
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(phl.valid_from, phl.valid_to, '[]')
        LEFT JOIN public.region AS phr
                ON phl.region_id = phr.id
        LEFT JOIN public.country AS phc
                ON phl.country_id = phc.id
        --
        LEFT OUTER JOIN public.location AS pol
                ON pol.legal_unit_id = es.id
               AND pol.type = 'postal'
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(pol.valid_from, pol.valid_to, '[]')
        LEFT JOIN public.region AS por
                ON pol.region_id = por.id
        LEFT JOIN public.country AS poc
                ON pol.country_id = poc.id
        --
        LEFT OUTER JOIN public.stat_definition AS sd1
                ON sd1.code = 'employees'
        LEFT OUTER JOIN public.stat_for_unit AS sfu1
                ON sfu1.stat_definition_id = sd1.id
               AND sfu1.establishment_id = es.id
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(sfu1.valid_from, sfu1.valid_to, '[]')
        LEFT OUTER JOIN public.stat_definition AS sd2
                ON sd2.code = 'turnover'
        LEFT OUTER JOIN public.stat_for_unit AS sfu2
                ON sfu2.stat_definition_id = sd2.id
               AND sfu2.establishment_id = es.id
               AND daterange(es.valid_from, es.valid_to, '[]')
                && daterange(sfu2.valid_from, sfu2.valid_to, '[]')
    ) AS source
    GROUP BY valid_from
           , valid_to
           , unit_type
           , unit_id
           , stat_ident
           , tax_ident
           , external_ident
           , external_ident_type
           , by_tag_id
           , by_tag_id_unique_ident
           , name
           , birth_date
           , death_date
           , search
           , primary_activity_category_id
           , primary_activity_category_path
           , secondary_activity_category_id
           , secondary_activity_category_path
           , activity_category_paths
           --
           , sector_id
           , sector_path
           , sector_code
           , sector_name
           , legal_form_id
           , legal_form_code
           , legal_form_name
           --
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postal_code
           , physical_postal_place
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           --
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postal_code
           , postal_postal_place
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
    UNION ALL
    -- Enterprise Group
    SELECT valid_from
         , valid_to
         , 'enterprise_group'::public.statistical_unit_type AS unit_type
         , id AS unit_id
         , NULL::TEXT AS stat_ident
         , NULL::TEXT AS tax_ident
         , NULL::TEXT AS external_ident
         , NULL::TEXT AS external_ident_type
         , NULL::INTEGER AS by_tag_id
         , NULL::TEXT    AS by_tag_id_unique_ident
         , NULL::TEXT AS name
         , NULL::DATE AS birth_date
         , NULL::DATE AS death_date
         , NULL::TSVECTOR AS search
         , NULL::INTEGER AS primary_activity_category_id
         , NULL::public.ltree AS primary_activity_category_path
         , NULL::INTEGER AS secondary_activity_category_id
         , NULL::public.ltree AS secondary_activity_category_path
         , NULL::public.ltree[] AS activity_category_paths
         --
         , NULL::INTEGER AS sector_id
         , NULL::public.ltree AS sector_path
         , NULL::TEXT    AS sector_code
         , NULL::TEXT    AS sector_name
         , NULL::INTEGER AS legal_unit_id
         , NULL::TEXT    AS legal_unit_code
         , NULL::TEXT    AS legal_unit_name
         --
         , NULL::TEXT AS physical_address_part1
         , NULL::TEXT AS physical_address_part2
         , NULL::TEXT AS physical_address_part3
         , NULL::TEXT AS physical_postal_code
         , NULL::TEXT AS physical_postal_place
         , NULL::INTEGER AS physical_region_id
         , NULL::public.ltree AS physical_region_path
         , NULL::INTEGER AS physical_country_id
         , NULL::TEXT AS physical_country_iso_2
         --
         , NULL::TEXT AS postal_address_part1
         , NULL::TEXT AS postal_address_part2
         , NULL::TEXT AS postal_address_part3
         , NULL::TEXT AS postal_postal_code
         , NULL::TEXT AS postal_postal_place
         , NULL::INTEGER AS postal_region_id
         , NULL::public.ltree AS postal_region_path
         , NULL::INTEGER AS postal_country_id
         , NULL::TEXT AS postal_country_iso_2
         --
         , NULL::JSONB AS invalid_codes
         --
         , NULL::INT[] AS aggregated_establishment_ids
         , NULL::INT[] AS aggregated_legal_unit_ids
         , NULL::INT[] AS aggregated_enterprise_ids
         , NULL::int AS employees
         , NULL::int AS turnover
      FROM public.enterprise_group
    )
    SELECT data.*
         , (
          SELECT array_agg(DISTINCT t.path)
          FROM public.tag_for_unit AS tfu
          JOIN public.tag AS t ON t.id = tfu.tag_id
          WHERE
            CASE data.unit_type
            WHEN 'enterprise' THEN tfu.enterprise_id = data.unit_id
            WHEN 'legal_unit' THEN tfu.legal_unit_id = data.unit_id
            WHEN 'establishment' THEN tfu.establishment_id = data.unit_id
            WHEN 'enterprise_group' THEN tfu.enterprise_group_id = data.unit_id
            END
          ) AS tag_paths
    FROM data;
;

\echo public.statistical_unit
CREATE MATERIALIZED VIEW public.statistical_unit AS
SELECT * FROM public.statistical_unit_def;

CREATE UNIQUE INDEX "statistical_unit_key"
    ON public.statistical_unit
    (valid_from
    ,valid_to
    ,unit_type
    ,unit_id
    );
CREATE INDEX idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
CREATE INDEX idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
CREATE INDEX idx_statistical_unit_by_tag_id ON public.statistical_unit (by_tag_id);
CREATE INDEX idx_statistical_unit_by_tag_id_unique_ident ON public.statistical_unit (by_tag_id_unique_ident);
CREATE INDEX idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
CREATE INDEX idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
CREATE INDEX idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
CREATE INDEX idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
CREATE INDEX idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
CREATE INDEX idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);

CREATE INDEX idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
CREATE INDEX idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

CREATE INDEX idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);
CREATE INDEX idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
CREATE INDEX idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

CREATE INDEX idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

CREATE INDEX idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

CREATE INDEX idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
CREATE INDEX idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

CREATE INDEX idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
CREATE INDEX idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

CREATE INDEX idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
CREATE INDEX idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);


\echo public.activity_category_used
CREATE MATERIALIZED VIEW public.activity_category_used AS
SELECT acs.code AS standard_code
     , ac.id
     , ac.path
     , acp.code AS parent_code
     , ac.label
     , ac.code
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
ORDER BY path;

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
     , sum(employees) AS employees
     , sum(turnover) AS turnover
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

CREATE INDEX statistical_unit_facet_valid_from ON public.statistical_unit_facet(valid_from);
CREATE INDEX statistical_unit_facet_valid_to ON public.statistical_unit_facet(valid_to);
CREATE INDEX statistical_unit_facet_unit_type ON public.statistical_unit_facet(unit_type);

CREATE INDEX statistical_unit_facet_physical_region_path_btree ON public.statistical_unit_facet USING BTREE (physical_region_path);
CREATE INDEX statistical_unit_facet_physical_region_path_gist ON public.statistical_unit_facet USING GIST (physical_region_path);

CREATE INDEX statistical_unit_facet_primary_activity_category_path_btree ON public.statistical_unit_facet USING BTREE (primary_activity_category_path);
CREATE INDEX statistical_unit_facet_primary_activity_category_path_gist ON public.statistical_unit_facet USING GIST (primary_activity_category_path);

CREATE INDEX statistical_unit_facet_sector_path_btree ON public.statistical_unit_facet USING BTREE (sector_path);
CREATE INDEX statistical_unit_facet_sector_path_gist ON public.statistical_unit_facet USING GIST (sector_path);

CREATE INDEX statistical_unit_facet_legal_form_id_btree ON public.statistical_unit_facet USING BTREE (legal_form_id);
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
             , employees
             , turnover
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
             , COALESCE(SUM(af.employees), 0) AS employees
             , COALESCE(SUM(af.turnover), 0) AS turnover
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
             , COALESCE(SUM(suf.employees), 0) AS employees
             , COALESCE(SUM(suf.turnover), 0) AS turnover
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
             , COALESCE(SUM(suf.employees), 0) AS employees
             , COALESCE(SUM(suf.turnover), 0) AS turnover
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
             , COALESCE(SUM(suf.employees), 0) AS employees
             , COALESCE(SUM(suf.turnover), 0) AS turnover
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
             , COALESCE(SUM(suf.employees), 0) AS employees
             , COALESCE(SUM(suf.turnover), 0) AS turnover
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
             , COALESCE(SUM(suf.employees), 0) AS employees
             , COALESCE(SUM(suf.turnover), 0) AS turnover
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
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_facet_stats AS source),
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



CREATE TYPE public.statistical_history_type AS ENUM('year','year-month');


\echo public.statistical_history_def
SELECT pg_catalog.set_config('search_path', 'public', false);
CREATE VIEW public.statistical_history_def AS
WITH year_range AS (
  SELECT min(valid_from) AS start_year
       , least(max(valid_to),current_date) AS stop_year
  FROM public.statistical_unit
), year_in_range AS (
    SELECT generate_series(
        date_trunc('year', start_year)::date,
        date_trunc('year', stop_year)::date,
        '1 year'::interval
    )::date AS time_start,
    (date_trunc('year', start_year)::date + '1 year'::interval - '1 day'::interval)::date AS time_stop
    FROM year_range
), year_and_month_in_range AS (
    SELECT generate_series(
        date_trunc('month', start_year)::date,
        date_trunc('month', stop_year)::date,
        '1 month'::interval
    )::date AS time_start,
    (date_trunc('month', start_year)::date + '1 month'::interval - '1 day'::interval)::date AS time_stop
    FROM year_range
), year_with_unit_basis AS (
    SELECT COALESCE(su_start.unit_type,su_stop.unit_type) AS unit_type
         , EXTRACT(YEAR FROM range.time_start)::INT AS year
         --
         , COALESCE(su_start.unit_id, su_stop.unit_id) AS unit_id
         , su_start.unit_id IS NOT NULL AND su_stop.unit_id IS NOT NULL AS track_changes
         --
         , COALESCE(su_stop.birth_date, su_start.birth_date) AS birth_date
         , COALESCE(su_stop.death_date, su_start.death_date) AS death_date
         --
         , COALESCE(range.time_start <= COALESCE(su_stop.birth_date, su_start.birth_date),false) AS born
         , COALESCE(COALESCE(su_stop.death_date, su_start.death_date) <= range.time_stop ,false) AS died
         --
         , su_start.primary_activity_category_path   AS start_primary_activity_category_path
         , su_start.secondary_activity_category_path AS start_secondary_activity_category_path
         , su_start.sector_path                      AS start_sector_path
         , su_start.legal_form_id                    AS start_legal_form_id
         , su_start.physical_region_path             AS start_physical_region_path
         , su_start.physical_country_id              AS start_physical_country_id
         --
         , su_stop.primary_activity_category_path    AS stop_primary_activity_category_path
         , su_stop.secondary_activity_category_path  AS stop_secondary_activity_category_path
         , su_stop.sector_path                       AS stop_sector_path
         , su_stop.legal_form_id                     AS stop_legal_form_id
         , su_stop.physical_region_path              AS stop_physical_region_path
         , su_stop.physical_country_id               AS stop_physical_country_id
         --
         , COALESCE(su_stop.primary_activity_category_path  , su_start.primary_activity_category_path)   AS primary_activity_category_path
         , COALESCE(su_stop.secondary_activity_category_path, su_start.secondary_activity_category_path) AS secondary_activity_category_path
         , COALESCE(su_stop.sector_path                     , su_start.sector_path)                      AS sector_path
         , COALESCE(su_stop.legal_form_id                   , su_start.legal_form_id)                    AS legal_form_id
         , COALESCE(su_stop.physical_region_path            , su_start.physical_region_path)             AS physical_region_path
         , COALESCE(su_stop.physical_country_id             , su_start.physical_country_id)              AS physical_country_id
         --
         , su_start.employees AS start_employees
         , su_stop.employees  AS stop_employees
         , su_start.turnover  AS start_turnover
         , su_stop.turnover   AS stop_turnover
         --
         , COALESCE(su_stop.employees , su_start.employees) AS employees
         , COALESCE(su_stop.turnover  , su_start.turnover)  AS turnover
         --
    FROM year_in_range AS range
    LEFT JOIN public.statistical_unit AS su_start
           ON su_start.valid_from <= range.time_start AND range.time_start <= su_start.valid_to
    LEFT JOIN public.statistical_unit AS su_stop
           ON su_stop.valid_from <= range.time_stop AND range.time_stop <= su_stop.valid_to
    WHERE su_start.unit_type IS NULL
       OR su_stop.unit_type IS NULL
       OR su_start.unit_type = su_stop.unit_type AND su_start.unit_id = su_stop.unit_id
), year_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND start_primary_activity_category_path   IS DISTINCT FROM stop_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_secondary_activity_category_path IS DISTINCT FROM stop_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_sector_path                      IS DISTINCT FROM stop_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND start_legal_form_id                    IS DISTINCT FROM stop_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND start_physical_region_path             IS DISTINCT FROM stop_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND start_physical_country_id              IS DISTINCT FROM stop_physical_country_id              AS physical_country_changed
         --
         , CASE WHEN track_changes THEN stop_employees - start_employees ELSE NULL END AS employees_change
         , CASE WHEN track_changes THEN stop_turnover  - start_turnover  ELSE NULL END AS turnover_change
         --
    FROM year_with_unit_basis AS basis
), year_and_month_with_unit_basis AS (
    SELECT COALESCE(su_start.unit_type,su_stop.unit_type) AS unit_type
         , EXTRACT(YEAR FROM range.time_start)::INT AS year
         , EXTRACT(MONTH FROM range.time_start)::INT AS month
         --
         , COALESCE(su_start.unit_id, su_stop.unit_id) AS unit_id
         , su_start.unit_id IS NOT NULL AND su_stop.unit_id IS NOT NULL AS track_changes
         --
         , COALESCE(su_stop.birth_date, su_start.birth_date) AS birth_date
         , COALESCE(su_stop.death_date, su_start.death_date) AS death_date
         --
         , COALESCE(range.time_start <= COALESCE(su_stop.birth_date, su_start.birth_date),false) AS born
         , COALESCE(COALESCE(su_stop.death_date, su_start.death_date) <= range.time_stop ,false) AS died
         --
         , su_start.primary_activity_category_path   AS start_primary_activity_category_path
         , su_start.secondary_activity_category_path AS start_secondary_activity_category_path
         , su_start.sector_path                      AS start_sector_path
         , su_start.legal_form_id                    AS start_legal_form_id
         , su_start.physical_region_path             AS start_physical_region_path
         , su_start.physical_country_id              AS start_physical_country_id
         --
         , su_stop.primary_activity_category_path    AS stop_primary_activity_category_path
         , su_stop.secondary_activity_category_path  AS stop_secondary_activity_category_path
         , su_stop.sector_path                       AS stop_sector_path
         , su_stop.legal_form_id                     AS stop_legal_form_id
         , su_stop.physical_region_path              AS stop_physical_region_path
         , su_stop.physical_country_id               AS stop_physical_country_id
         --
         , COALESCE(su_stop.primary_activity_category_path  , su_start.primary_activity_category_path)   AS primary_activity_category_path
         , COALESCE(su_stop.secondary_activity_category_path, su_start.secondary_activity_category_path) AS secondary_activity_category_path
         , COALESCE(su_stop.sector_path                     , su_start.sector_path)                      AS sector_path
         , COALESCE(su_stop.legal_form_id                   , su_start.legal_form_id)                    AS legal_form_id
         , COALESCE(su_stop.physical_region_path            , su_start.physical_region_path)             AS physical_region_path
         , COALESCE(su_stop.physical_country_id             , su_start.physical_country_id)              AS physical_country_id
         --
         , su_start.employees AS start_employees
         , su_stop.employees  AS stop_employees
         , su_start.turnover  AS start_turnover
         , su_stop.turnover   AS stop_turnover
         --
         , COALESCE(su_stop.employees , su_start.employees) AS employees
         , COALESCE(su_stop.turnover  , su_start.turnover)  AS turnover
         --
    FROM year_in_range AS range
    LEFT JOIN public.statistical_unit AS su_start
           ON su_start.valid_from <= range.time_start AND range.time_start <= su_start.valid_to
    LEFT JOIN public.statistical_unit AS su_stop
           ON su_stop.valid_from <= range.time_stop AND range.time_stop <= su_stop.valid_to
    WHERE su_start.unit_type IS NULL
       OR su_stop.unit_type IS NULL
       OR su_start.unit_type = su_stop.unit_type AND su_start.unit_id = su_stop.unit_id
), year_and_month_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND start_primary_activity_category_path   IS DISTINCT FROM stop_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_secondary_activity_category_path IS DISTINCT FROM stop_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_sector_path                      IS DISTINCT FROM stop_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND start_legal_form_id                    IS DISTINCT FROM stop_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND start_physical_region_path             IS DISTINCT FROM stop_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND start_physical_country_id              IS DISTINCT FROM stop_physical_country_id              AS physical_country_changed
         --
         , CASE WHEN track_changes THEN stop_employees - start_employees ELSE NULL END AS employees_change
         , CASE WHEN track_changes THEN stop_turnover  - start_turnover  ELSE NULL END AS turnover_change
         --
    FROM year_and_month_with_unit_basis AS basis
), year_with_unit AS (
    SELECT 'year'::public.statistical_history_type AS type
         , source.year                             AS year
         , NULL::INTEGER                           AS month
         , source.unit_type                        AS unit_type
         --
         , COUNT(source.*)                            AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         --
         , SUM(source.employees) AS employees
         , SUM(source.turnover)  AS turnover
    FROM year_with_unit_derived AS source
    GROUP BY year, unit_type
), year_and_month_with_unit AS (
    SELECT 'year-month'::public.statistical_history_type AS type
         , source.year                             AS year
         , source.month                            AS month
         , source.unit_type                        AS unit_type
         --
         , COUNT(source.*)                         AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         --
         , SUM(source.employees) AS employees
         , SUM(source.turnover)  AS turnover
    FROM year_and_month_with_unit_derived AS source
    GROUP BY year, month, unit_type
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

CREATE INDEX idx_statistical_history_type ON public.statistical_history (type);
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
CREATE INDEX idx_statistical_history_employees ON public.statistical_history (employees);
CREATE INDEX idx_statistical_history_turnover ON public.statistical_history (turnover);


\echo public.statistical_history_facet_def
SELECT pg_catalog.set_config('search_path', 'public', false);
CREATE VIEW public.statistical_history_facet_def AS
WITH year_range AS (
  SELECT min(valid_from) AS start_year
       , least(max(valid_to),current_date) AS stop_year
  FROM public.statistical_unit
), year_in_range AS (
    SELECT generate_series(
        date_trunc('year', start_year)::date,
        date_trunc('year', stop_year)::date,
        '1 year'::interval
    )::date AS time_start,
    (date_trunc('year', start_year)::date + '1 year'::interval - '1 day'::interval)::date AS time_stop
    FROM year_range
), year_and_month_in_range AS (
    SELECT generate_series(
        date_trunc('month', start_year)::date,
        date_trunc('month', stop_year)::date,
        '1 month'::interval
    )::date AS time_start,
    (date_trunc('month', start_year)::date + '1 month'::interval - '1 day'::interval)::date AS time_stop
    FROM year_range
), year_with_unit_basis AS (
    SELECT COALESCE(su_start.unit_type,su_stop.unit_type) AS unit_type
         , EXTRACT(YEAR FROM range.time_start)::INT AS year
         --
         , COALESCE(su_start.unit_id, su_stop.unit_id) AS unit_id
         , su_start.unit_id IS NOT NULL AND su_stop.unit_id IS NOT NULL AS track_changes
         --
         , COALESCE(su_stop.birth_date, su_start.birth_date) AS birth_date
         , COALESCE(su_stop.death_date, su_start.death_date) AS death_date
         --
         , COALESCE(range.time_start <= COALESCE(su_stop.birth_date, su_start.birth_date),false) AS born
         , COALESCE(COALESCE(su_stop.death_date, su_start.death_date) <= range.time_stop ,false) AS died
         --
         , su_start.primary_activity_category_path   AS start_primary_activity_category_path
         , su_start.secondary_activity_category_path AS start_secondary_activity_category_path
         , su_start.sector_path                      AS start_sector_path
         , su_start.legal_form_id                    AS start_legal_form_id
         , su_start.physical_region_path             AS start_physical_region_path
         , su_start.physical_country_id              AS start_physical_country_id
         --
         , su_stop.primary_activity_category_path    AS stop_primary_activity_category_path
         , su_stop.secondary_activity_category_path  AS stop_secondary_activity_category_path
         , su_stop.sector_path                       AS stop_sector_path
         , su_stop.legal_form_id                     AS stop_legal_form_id
         , su_stop.physical_region_path              AS stop_physical_region_path
         , su_stop.physical_country_id               AS stop_physical_country_id
         --
         , COALESCE(su_stop.primary_activity_category_path  , su_start.primary_activity_category_path)   AS primary_activity_category_path
         , COALESCE(su_stop.secondary_activity_category_path, su_start.secondary_activity_category_path) AS secondary_activity_category_path
         , COALESCE(su_stop.sector_path                     , su_start.sector_path)                      AS sector_path
         , COALESCE(su_stop.legal_form_id                   , su_start.legal_form_id)                    AS legal_form_id
         , COALESCE(su_stop.physical_region_path            , su_start.physical_region_path)             AS physical_region_path
         , COALESCE(su_stop.physical_country_id             , su_start.physical_country_id)              AS physical_country_id
         --
         , su_start.employees AS start_employees
         , su_stop.employees  AS stop_employees
         , su_start.turnover  AS start_turnover
         , su_stop.turnover   AS stop_turnover
         --
         , COALESCE(su_stop.employees , su_start.employees) AS employees
         , COALESCE(su_stop.turnover  , su_start.turnover)  AS turnover
         --
    FROM year_in_range AS range
    LEFT JOIN public.statistical_unit AS su_start
           ON su_start.valid_from <= range.time_start AND range.time_start <= su_start.valid_to
    LEFT JOIN public.statistical_unit AS su_stop
           ON su_stop.valid_from <= range.time_stop AND range.time_stop <= su_stop.valid_to
    WHERE su_start.unit_type IS NULL
       OR su_stop.unit_type IS NULL
       OR su_start.unit_type = su_stop.unit_type AND su_start.unit_id = su_stop.unit_id
), year_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND start_primary_activity_category_path   IS DISTINCT FROM stop_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_secondary_activity_category_path IS DISTINCT FROM stop_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_sector_path                      IS DISTINCT FROM stop_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND start_legal_form_id                    IS DISTINCT FROM stop_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND start_physical_region_path             IS DISTINCT FROM stop_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND start_physical_country_id              IS DISTINCT FROM stop_physical_country_id              AS physical_country_changed
         --
         , CASE WHEN track_changes THEN stop_employees - start_employees ELSE NULL END AS employees_change
         , CASE WHEN track_changes THEN stop_turnover  - start_turnover  ELSE NULL END AS turnover_change
         --
    FROM year_with_unit_basis AS basis
), year_and_month_with_unit_basis AS (
    SELECT COALESCE(su_start.unit_type,su_stop.unit_type) AS unit_type
         , EXTRACT(YEAR FROM range.time_start)::INT AS year
         , EXTRACT(MONTH FROM range.time_start)::INT AS month
         --
         , COALESCE(su_start.unit_id, su_stop.unit_id) AS unit_id
         , su_start.unit_id IS NOT NULL AND su_stop.unit_id IS NOT NULL AS track_changes
         --
         , COALESCE(su_stop.birth_date, su_start.birth_date) AS birth_date
         , COALESCE(su_stop.death_date, su_start.death_date) AS death_date
         --
         , COALESCE(range.time_start <= COALESCE(su_stop.birth_date, su_start.birth_date),false) AS born
         , COALESCE(COALESCE(su_stop.death_date, su_start.death_date) <= range.time_stop ,false) AS died
         --
         , su_start.primary_activity_category_path   AS start_primary_activity_category_path
         , su_start.secondary_activity_category_path AS start_secondary_activity_category_path
         , su_start.sector_path                      AS start_sector_path
         , su_start.legal_form_id                    AS start_legal_form_id
         , su_start.physical_region_path             AS start_physical_region_path
         , su_start.physical_country_id              AS start_physical_country_id
         --
         , su_stop.primary_activity_category_path    AS stop_primary_activity_category_path
         , su_stop.secondary_activity_category_path  AS stop_secondary_activity_category_path
         , su_stop.sector_path                       AS stop_sector_path
         , su_stop.legal_form_id                     AS stop_legal_form_id
         , su_stop.physical_region_path              AS stop_physical_region_path
         , su_stop.physical_country_id               AS stop_physical_country_id
         --
         , COALESCE(su_stop.primary_activity_category_path  , su_start.primary_activity_category_path)   AS primary_activity_category_path
         , COALESCE(su_stop.secondary_activity_category_path, su_start.secondary_activity_category_path) AS secondary_activity_category_path
         , COALESCE(su_stop.sector_path                     , su_start.sector_path)                      AS sector_path
         , COALESCE(su_stop.legal_form_id                   , su_start.legal_form_id)                    AS legal_form_id
         , COALESCE(su_stop.physical_region_path            , su_start.physical_region_path)             AS physical_region_path
         , COALESCE(su_stop.physical_country_id             , su_start.physical_country_id)              AS physical_country_id
         --
         , su_start.employees AS start_employees
         , su_stop.employees  AS stop_employees
         , su_start.turnover  AS start_turnover
         , su_stop.turnover   AS stop_turnover
         --
         , COALESCE(su_stop.employees , su_start.employees) AS employees
         , COALESCE(su_stop.turnover  , su_start.turnover)  AS turnover
         --
    FROM year_in_range AS range
    LEFT JOIN public.statistical_unit AS su_start
           ON su_start.valid_from <= range.time_start AND range.time_start <= su_start.valid_to
    LEFT JOIN public.statistical_unit AS su_stop
           ON su_stop.valid_from <= range.time_stop AND range.time_stop <= su_stop.valid_to
    WHERE su_start.unit_type IS NULL
       OR su_stop.unit_type IS NULL
       OR su_start.unit_type = su_stop.unit_type AND su_start.unit_id = su_stop.unit_id
), year_and_month_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND start_primary_activity_category_path   IS DISTINCT FROM stop_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_secondary_activity_category_path IS DISTINCT FROM stop_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND start_sector_path                      IS DISTINCT FROM stop_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND start_legal_form_id                    IS DISTINCT FROM stop_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND start_physical_region_path             IS DISTINCT FROM stop_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND start_physical_country_id              IS DISTINCT FROM stop_physical_country_id              AS physical_country_changed
         --
         , CASE WHEN track_changes THEN stop_employees - start_employees ELSE NULL END AS employees_change
         , CASE WHEN track_changes THEN stop_turnover  - start_turnover  ELSE NULL END AS turnover_change
         --
    FROM year_and_month_with_unit_basis AS basis
), year_with_unit_per_facet AS (
    SELECT 'year'::public.statistical_history_type AS type
         , source.year                             AS year
         , NULL::INTEGER                          AS month
         , source.unit_type                        AS unit_type
         --
         , source.primary_activity_category_path   AS primary_activity_category_path
         , source.secondary_activity_category_path AS secondary_activity_category_path
         , source.sector_path                      AS sector_path
         , source.legal_form_id                    AS legal_form_id
         , source.physical_region_path             AS physical_region_path
         , source.physical_country_id              AS physical_country_id
         --
         , COUNT(source.*)                         AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         --
         , SUM(source.employees) AS employees
         , SUM(source.turnover) AS turnover
    FROM year_with_unit_derived AS source
    GROUP BY year, unit_type
           , primary_activity_category_path
           , secondary_activity_category_path
           , sector_path
           , legal_form_id
           , physical_region_path
           , physical_country_id
), year_and_month_with_unit_per_facet AS (
    SELECT 'year-month'::public.statistical_history_type AS type
         , source.year                             AS year
         , source.month                            AS month
         , source.unit_type                        AS unit_type
         --
         , source.primary_activity_category_path   AS primary_activity_category_path
         , source.secondary_activity_category_path AS secondary_activity_category_path
         , source.sector_path                      AS sector_path
         , source.legal_form_id                    AS legal_form_id
         , source.physical_region_path             AS physical_region_path
         , source.physical_country_id              AS physical_country_id
         --
         , COUNT(source.*)                         AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         --
         , SUM(source.employees) AS employees
         , SUM(source.turnover) AS turnover
    FROM year_and_month_with_unit_derived AS source
    GROUP BY year, month, unit_type
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

CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
CREATE INDEX idx_statistical_history_facet_births ON public.statistical_history_facet (births);
CREATE INDEX idx_statistical_history_facet_deaths ON public.statistical_history_facet (deaths);

CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet USING GIST (primary_activity_category_path);

CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet USING GIST (secondary_activity_category_path);

CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);

CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);

CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);

CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
CREATE INDEX idx_statistical_history_facet_count ON public.statistical_history_facet (count);
CREATE INDEX idx_statistical_history_facet_employees ON public.statistical_history_facet (employees);
CREATE INDEX idx_statistical_history_facet_turnover ON public.statistical_history_facet (turnover);


\echo public.statistical_history_drilldown
CREATE FUNCTION public.statistical_history_drilldown(
    unit_type public.statistical_unit_type DEFAULT 'enterprise',
    type public.statistical_history_type DEFAULT 'year',
    year INTEGER DEFAULT NULL,
    region_path public.ltree DEFAULT NULL,
    activity_category_path public.ltree DEFAULT NULL,
    sector_path public.ltree DEFAULT NULL,
    legal_form_id INTEGER DEFAULT NULL,
    country_id INTEGER DEFAULT NULL
)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.type = type' is always true.
    WITH params AS (
        SELECT
            unit_type AS param_unit_type,
            type AS param_type,
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
          AND (param_type IS NULL OR sh.type = param_type)
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
             , COALESCE(SUM(ah.count), 0) AS count
            --
             , COALESCE(SUM(ah.employees), 0) AS employees
             , COALESCE(SUM(ah.turnover) , 0) AS turnover
             --
             , COALESCE(SUM(ah.births), 0) AS births
             , COALESCE(SUM(ah.deaths), 0) AS deaths
             --
             , COALESCE(SUM(ah.primary_activity_category_change_count) , 0) AS primary_activity_category_change_count
             , COALESCE(SUM(ah.sector_change_count)                    , 0) AS sector_change_count
             , COALESCE(SUM(ah.legal_form_change_count)                , 0) AS legal_form_change_count
             , COALESCE(SUM(ah.physical_region_change_count)           , 0) AS physical_region_change_count
             , COALESCE(SUM(ah.physical_country_change_count)          , 0) AS physical_country_change_count
             --
        FROM available_history AS ah
        GROUP BY year, month
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
             , COALESCE(SUM(sh.employees), 0) AS employees
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
             , COALESCE(SUM(sh.employees), 0) AS employees
             , COALESCE(bool_or(true) FILTER (WHERE sh.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_history AS sh ON sh.primary_activity_category_path OPERATOR(public.<@) aac.path
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
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(SUM(sh.employees), 0) AS employees
             , COALESCE(bool_or(true) FILTER (WHERE sh.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_history AS sh ON sh.sector_path OPERATOR(public.<@) "as".path
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
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(SUM(sh.employees), 0) AS employees
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_history AS sh ON sh.legal_form_id = lf.id
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
             , COALESCE(SUM(sh.count), 0) AS count
             , COALESCE(SUM(sh.employees), 0) AS employees
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_history AS sh ON sh.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
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
            'type',param_type,
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




\echo public.stat_for_unit_hierarchy
CREATE OR REPLACE FUNCTION public.stat_for_unit_hierarchy(
  parent_establishment_id INTEGER,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB AS $$
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
           END AS data
    FROM public.stat_for_unit AS sfu
    JOIN public.stat_definition AS sd ON sd.id = sfu.stat_definition_id
    WHERE parent_establishment_id IS NOT NULL AND sfu.establishment_id = parent_establishment_id
      AND sfu.valid_from <= valid_on AND valid_on <= sfu.valid_to
    ORDER BY sd.code
), data_list AS (
    SELECT jsonb_agg(data) AS data FROM ordered_data
)
SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('stat_for_unit',data)
    END
  FROM data_list;
$$ LANGUAGE sql IMMUTABLE;


\echo public.tag_for_unit_hierarchy
CREATE FUNCTION public.tag_for_unit_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  parent_enterprise_id INTEGER DEFAULT NULL,
  parent_enterprise_group_id INTEGER DEFAULT NULL
) RETURNS JSONB AS $$
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
$$ LANGUAGE sql IMMUTABLE;


\echo public.region_hierarchy
CREATE OR REPLACE FUNCTION public.region_hierarchy(region_id INTEGER)
RETURNS JSONB AS $$
    WITH data AS (
        SELECT jsonb_build_object('region', to_jsonb(s.*)) AS data
          FROM public.region AS s
         WHERE region_id IS NOT NULL AND s.id = region_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$ LANGUAGE sql IMMUTABLE;

\echo public.country_hierarchy
CREATE OR REPLACE FUNCTION public.country_hierarchy(country_id INTEGER)
RETURNS JSONB AS $$
    WITH data AS (
        SELECT jsonb_build_object('country', to_jsonb(s.*)) AS data
          FROM public.country AS s
         WHERE country_id IS NOT NULL AND s.id = country_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$ LANGUAGE sql IMMUTABLE;


\echo public.location_hierarchy
CREATE OR REPLACE FUNCTION public.location_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(l.*)
        || (SELECT public.region_hierarchy(l.region_id))
        || (SELECT public.country_hierarchy(l.country_id))
        AS data
      FROM public.location AS l
     WHERE l.valid_from <= valid_on AND valid_on <= l.valid_to
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
$$ LANGUAGE sql IMMUTABLE;


\echo public.activity_category_standard_hierarchy
CREATE OR REPLACE FUNCTION public.activity_category_standard_hierarchy(standard_id INTEGER)
RETURNS JSONB AS $$
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
$$ LANGUAGE sql IMMUTABLE;


\echo public.activity_category_hierarchy
CREATE OR REPLACE FUNCTION public.activity_category_hierarchy(activity_category_id INTEGER)
RETURNS JSONB AS $$
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
$$ LANGUAGE sql IMMUTABLE;


\echo public.activity_hierarchy
CREATE OR REPLACE FUNCTION public.activity_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB AS $$
    WITH ordered_data AS (
        SELECT to_jsonb(a.*)
               || (SELECT public.activity_category_hierarchy(a.category_id))
               AS data
          FROM public.activity AS a
         WHERE a.valid_from <= valid_on AND valid_on <= a.valid_to
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
$$ LANGUAGE sql IMMUTABLE;


\echo public.sector_hierarchy
CREATE OR REPLACE FUNCTION public.sector_hierarchy(sector_id INTEGER)
RETURNS JSONB AS $$
    WITH data AS (
        SELECT jsonb_build_object('sector', to_jsonb(s.*)) AS data
          FROM public.sector AS s
         WHERE sector_id IS NOT NULL AND s.id = sector_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$ LANGUAGE sql IMMUTABLE;


\echo public.legal_form_hierarchy
CREATE OR REPLACE FUNCTION public.legal_form_hierarchy(legal_form_id INTEGER)
RETURNS JSONB AS $$
    WITH data AS (
        SELECT jsonb_build_object('legal_form', to_jsonb(lf.*)) AS data
          FROM public.legal_form AS lf
         WHERE legal_form_id IS NOT NULL AND lf.id = legal_form_id
         ORDER BY lf.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$ LANGUAGE sql IMMUTABLE;


\echo public.establishment_hierarchy
CREATE OR REPLACE FUNCTION public.establishment_hierarchy(
    parent_legal_unit_id INTEGER DEFAULT NULL,
    parent_enterprise_id INTEGER DEFAULT NULL,
    valid_on DATE DEFAULT current_date
) RETURNS JSONB AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.stat_for_unit_hierarchy(es.id,valid_on))
        || (SELECT public.sector_hierarchy(es.sector_id))
        || (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL))
        AS data
    FROM public.establishment AS es
   WHERE (  (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_from <= valid_on AND valid_on <= es.valid_to
   ORDER BY es.primary_for_legal_unit DESC, es.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('establishment',data)
    END
  FROM data_list;
$$ LANGUAGE sql IMMUTABLE;

\echo public.legal_unit_hierarchy
CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(parent_enterprise_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.establishment_hierarchy(lu.id, NULL, valid_on))
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.sector_hierarchy(lu.sector_id))
        || (SELECT public.legal_form_hierarchy(lu.legal_form_id))
        || (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL))
        AS data
    FROM public.legal_unit AS lu
   WHERE parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id
     AND lu.valid_from <= valid_on AND valid_on <= lu.valid_to
   ORDER BY lu.primary_for_enterprise DESC, lu.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('legal_unit',data)
    END
  FROM data_list;
$$ LANGUAGE sql IMMUTABLE;

\echo public.enterprise_hierarchy
CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.legal_unit_hierarchy(en.id, valid_on))
                 || (SELECT public.establishment_hierarchy(NULL, en.id, valid_on))
                 || (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL))
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$ LANGUAGE sql IMMUTABLE;


\echo public.statistical_unit_enterprise_id
CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS INTEGER AS $$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_from <= valid_on AND valid_on <= es.valid_to
            )
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_from <= valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'legal_unit' THEN (
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_from <= valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'enterprise' THEN (
             SELECT en.id
               FROM public.enterprise AS en
              WHERE en.id = unit_id
         )
         WHEN 'enterprise_group' THEN NULL --TODO
         END
  ;
$$ LANGUAGE sql IMMUTABLE;


\echo public.statistical_unit_hierarchy
CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB AS $$
  SELECT --jsonb_strip_nulls(
            public.enterprise_hierarchy(
              public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
              , valid_on
            )
        --)
;
$$ LANGUAGE sql IMMUTABLE;


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
\echo public.custom_view_def_target_table
CREATE TABLE public.custom_view_def_target_table(
    id serial PRIMARY KEY,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    name text UNIQUE NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (schema_name, table_name)
);
INSERT INTO public.custom_view_def_target_table (schema_name,table_name, name)
VALUES
    ('public','legal_unit', 'Legal Unit')
   ,('public','establishment', 'Establishment')
   ,('public','enterprise', 'Enterprise')
   ,('public','enterprise_group', 'Enterprise Group')
   ;

\echo public.custom_view_def_target_column
CREATE TABLE public.custom_view_def_target_column(
    id serial PRIMARY KEY,
    target_table_id int REFERENCES public.custom_view_def_target_table(id),
    column_name text NOT NULL,
    uniquely_identifying boolean NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
WITH cols AS (
  SELECT tt.id AS target_table_id
       , column_name
       , data_type
       , is_nullable
       , column_name like '%_ident' AS uniquely_identifying
       , ROW_NUMBER() OVER (PARTITION BY tt.id ORDER BY ordinal_position) AS priority
  FROM information_schema.columns AS c
  JOIN public.custom_view_def_target_table AS tt
    ON c.table_schema = tt.schema_name
    AND c.table_name = tt.table_name
  ORDER BY ordinal_position
) INSERT INTO public.custom_view_def_target_column(target_table_id, column_name, uniquely_identifying)
  SELECT target_table_id, column_name, uniquely_identifying
  FROM cols
  ;

\echo public.custom_view_def
CREATE TABLE public.custom_view_def(
    id serial PRIMARY KEY,
    target_table_id int REFERENCES public.custom_view_def_target_table(id),
    slug text UNIQUE NOT NULL,
    name text NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);

\echo public.custom_view_def_source_column
CREATE TABLE public.custom_view_def_source_column(
    id serial PRIMARY KEY,
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    column_name text NOT NULL,
    priority int NOT NULL, -- The ordering of the columns in the CSV file.
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);

\echo public.custom_view_def_mapping
CREATE TABLE public.custom_view_def_mapping(
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    source_column_id int REFERENCES public.custom_view_def_source_column(id),
    target_column_id int REFERENCES public.custom_view_def_target_column(id),
    CONSTRAINT unique_source_column_mapping UNIQUE (custom_view_def_id, source_column_id),
    CONSTRAINT unique_target_column_mapping UNIQUE (custom_view_def_id, target_column_id),
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);


\echo admin.custom_view_def_expanded
CREATE VIEW admin.custom_view_def_expanded AS
    SELECT cvd.id AS view_def_id,
           cvd.slug AS view_def_slug,
           cvd.name AS view_def_name,
           cvd.note AS view_def_note,
           cvdtt.schema_name AS target_schema_name,
           cvdtt.table_name AS target_table_name,
           cvdsc.column_name AS source_column,
           cvdtc.column_name AS target_column,
           cvdtc.uniquely_identifying AS uniquely_identifying,
           cvdsc.priority AS source_column_priority
    FROM public.custom_view_def cvd,
         public.custom_view_def_target_table cvdtt,
         public.custom_view_def_mapping cvdm,
         public.custom_view_def_source_column cvdsc,
         public.custom_view_def_target_column cvdtc
    WHERE cvd.target_table_id = cvdtt.id
      AND cvd.id = cvdm.custom_view_def_id
      AND cvdm.source_column_id = cvdsc.id
      AND cvdm.target_column_id = cvdtc.id
    ORDER BY cvd.id ASC, cvdsc.priority ASC NULLS LAST, cvdsc.id ASC, cvdtc.id ASC
;


CREATE TYPE admin.custom_view_def_names AS (
    table_name text,
    view_name text,
    upsert_function_name text,
    delete_function_name text,
    upsert_trigger_name text,
    delete_trigger_name text
);

\echo admin.custom_view_def_generate_names
CREATE FUNCTION admin.custom_view_def_generate_names(record public.custom_view_def)
RETURNS admin.custom_view_def_names AS $$
DECLARE
    result admin.custom_view_def_names;
    table_name text;
BEGIN
    SELECT INTO table_name cvdtt.table_name
    FROM public.custom_view_def_target_table AS cvdtt
    WHERE id = record.target_table_id;

    result.table_name := table_name;
    result.view_name := table_name || '_' || record.slug || '_view';
    result.upsert_function_name := result.view_name || '_upsert';
    result.delete_function_name := result.view_name || '_delete';
    result.upsert_trigger_name := result.view_name || '_upsert_trigger';
    result.delete_trigger_name := result.view_name || '_delete_trigger';

    RAISE NOTICE 'Generated Names for table %: View Name: %, Upsert Function: %, Delete Function: %, Upsert Trigger: %, Delete Trigger: %',
                 table_name, result.view_name, result.upsert_function_name, result.delete_function_name,
                 result.upsert_trigger_name, result.delete_trigger_name;

    RETURN result;
END;
$$ LANGUAGE plpgsql;


\echo admin.custom_view_def_generate
CREATE OR REPLACE FUNCTION admin.custom_view_def_generate(record public.custom_view_def)
RETURNS void AS $custom_view_def_generate$
DECLARE
    names admin.custom_view_def_names;
    upsert_function_stmt text;
    delete_function_stmt text;
    select_stmt text := 'SELECT ';
    add_separator boolean := false;
    mapping RECORD;
BEGIN
    names := admin.custom_view_def_generate_names(record);
    RAISE NOTICE 'Generating view %', names.view_name;

    -- Build a VIEW suitable for extraction from columns of the target_table
    -- and into the columns of the source.
    -- This allows a query of the target_table that returns the expected columns
    -- of the source.
    -- Example:
    --    CREATE VIEW public.legal_unit_brreg_view
    --    WITH (security_invoker=on) AS
    --    SELECT
    --        COALESCE(t."$target_column1",'') AS "source column 1"
    --        , '' AS "source column 2"
    --        COALESCE(t."$target_column2",'') AS "source column 3"
    --        , '' AS "source column 4"
    --        ...
    --    FROM public.legal_unit AS t;
    --
    FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
    LOOP
        --RAISE NOTICE 'Processing mapping for source column: %, target column: %', mapping.source_column, mapping.target_column;
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            select_stmt := select_stmt || ', ';
        END IF;
        IF mapping.target_column IS NULL THEN
            select_stmt := select_stmt || format(
                '%L AS %I'
                , '', mapping.source_column
            );
        ELSE
            select_stmt := select_stmt || format(
                'COALESCE(target.%I::text, %L) AS %I'
                , mapping.target_column, '', mapping.source_column
            );
        END IF;
    END LOOP;
    select_stmt := select_stmt || format(' FROM public.%I AS target', names.table_name);

    EXECUTE 'CREATE VIEW public.' || names.view_name || ' WITH (security_invoker=on) AS ' || select_stmt;

    -- Create Upsert Function
    RAISE NOTICE 'Generating upsert function % for view %', names.upsert_function_name, names.view_name;

    -- Create an UPSERT function that takes data found in the view,
    -- and upserts them into the target table, using the defined column
    -- mappings.
    upsert_function_stmt :=
    'CREATE FUNCTION admin.' || names.upsert_function_name || '() RETURNS TRIGGER AS $$
DECLARE
    result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT ';

    add_separator := false;
    FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
    LOOP
        --RAISE NOTICE 'Processing mapping for source column: %, target column: %', mapping.source_column, mapping.target_column;
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            upsert_function_stmt := upsert_function_stmt || ', ';
        END IF;
        -- TODO: Support setting NOW as a source in the mapping, instead of a column.
        --   , statement_timestamp() AS updated_at
        -- TODO: Support setting a value as a source in the mapping, instead of a column.
        --   , '2023-01-01'::date AS valid_from
        --   , 'infinity'::date AS valid_to
        -- TODO: Interpret empty string as NULL date.
        --  , CASE NEW."stiftelsesdato"
        --    WHEN NULL THEN NULL
        --    WHEN '' THEN NULL
        --    ELSE NEW."stiftelsesdato"::date
        --    END AS birth_date
        upsert_function_stmt := upsert_function_stmt || format(
            'NEW.%I AS %I'
            , mapping.source_column, mapping.target_column
        );
    END LOOP;
    BEGIN -- Handle fixed columns
        upsert_function_stmt := upsert_function_stmt ||
        ', true AS active' ||
        ', statement_timestamp() AS seen_in_import_at' ||
        ', ''Batch import'' AS edit_comment' ||
        ', (SELECT id FROM su) AS edit_by_user_id';
    END;
    upsert_function_stmt := upsert_function_stmt || format(
    '), update_outcome AS (
        UPDATE public.%I AS target SET ', names.table_name);
        add_separator := false;
        FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
        LOOP
            IF NOT add_separator THEN
                add_separator := true;
            ELSE
                upsert_function_stmt := upsert_function_stmt || ', ';
            END IF;
            upsert_function_stmt := upsert_function_stmt || format(
                '%I = upsert_data.%I'
                , mapping.target_column, mapping.target_column
            );
        END LOOP;
        -- TODO: Add mapping expression to support
        -- , valid_from = upsert_data.valid_from
        -- , valid_to = upsert_data.valid_to
        -- , birth_date = upsert_data.birth_date
        upsert_function_stmt := upsert_function_stmt ||
          ', active = upsert_data.active' ||
          ', seen_in_import_at = upsert_data.seen_in_import_at' ||
          ', edit_comment = upsert_data.edit_comment' ||
          ', edit_by_user_id = upsert_data.edit_by_user_id' ||
        ' FROM upsert_data WHERE ';
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
                  AND uniquely_identifying
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ' AND ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    'target.%I = upsert_data.%I'
                    , mapping.target_column, mapping.target_column
                );
            END LOOP;
            upsert_function_stmt := upsert_function_stmt ||
            -- TODO: Improve handling of valid_to/valid_from by using custom_view_def
            ' AND legal_unit.valid_to = ''infinity''::date' ||
        ' RETURNING ''update''::text AS action, target.id' ||
    '), insert_outcome AS (';
    upsert_function_stmt := upsert_function_stmt || format(
    'INSERT INTO public.%I(', names.table_name);
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
                  AND uniquely_identifying
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ', ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    '%I'
                    , mapping.target_column
                );
            END LOOP;
            -- TODO: Add mapping expression to support
            --   , valid_from
            --   , valid_to
            --   , birth_date
            upsert_function_stmt := upsert_function_stmt ||
            ', active' ||
            ', seen_in_import_at' ||
            ', edit_comment' ||
            ', edit_by_user_id' ||
            ') SELECT ';
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ', ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    'upsert_data.%I'
                    , mapping.target_column
                );
            END LOOP;
            -- TODO: Add mapping expression to support
            --  , upsert_data.valid_from
            --  , upsert_data.valid_to
            --  , upsert_data.birth_date
            upsert_function_stmt := upsert_function_stmt ||
            ', upsert_data.active' ||
            ', upsert_data.seen_in_import_at' ||
            ', upsert_data.edit_comment' ||
            ', upsert_data.edit_by_user_id' ||
        ' FROM upsert_data' ||
        ' WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING ''insert''::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;';

    RAISE NOTICE 'upsert_function_stmt = %', upsert_function_stmt;
    EXECUTE upsert_function_stmt;

    -- Create Delete Function
    delete_function_stmt := format(
    'CREATE FUNCTION admin.%I() RETURNS TRIGGER AS $$
    BEGIN
        WITH su AS (
            SELECT *
            FROM statbus_user
            WHERE uuid = auth.uid()
            LIMIT 1
        )
        UPDATE public.%I
        SET valid_to = statement_timestamp()
          , edit_comment = ''Absent from upload''
          , edit_by_user_id = (SELECT id FROM su)
          , active = false
        WHERE seen_in_import_at < statement_timestamp();
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql', names.delete_function_name, names.table_name);

    RAISE NOTICE 'delete_function_stmt = %', delete_function_stmt;
    EXECUTE delete_function_stmt;

    -- Create triggers for the view
    -- Create Triggers
    EXECUTE format(
        'CREATE TRIGGER %I
        INSTEAD OF INSERT ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION admin.%I(NEW)', names.upsert_trigger_name, names.view_name, names.upsert_function_name);
    EXECUTE format(
        'CREATE TRIGGER %I
        AFTER INSERT ON public.%I
        FOR EACH STATEMENT
        EXECUTE FUNCTION admin.%I()', names.delete_trigger_name, names.view_name, names.delete_function_name);
END;
$custom_view_def_generate$ LANGUAGE plpgsql;

\echo admin.custom_view_def_destroy
CREATE OR REPLACE FUNCTION admin.custom_view_def_destroy(record public.custom_view_def)
RETURNS void AS $custom_view_def_destroy$
DECLARE
    names admin.custom_view_def_names;
BEGIN
    names := admin.custom_view_def_generate_names(record);

    IF names IS NULL THEN
        RAISE NOTICE 'names is NULL for record id %', record.id;
        RETURN;
    ELSE
        RAISE NOTICE 'View name: %', names.view_name;
    END IF;

    -- Drop Upsert and Delete Functions and Triggers
    EXECUTE format('DROP TRIGGER %I ON public.%I', names.upsert_trigger_name, names.view_name);
    EXECUTE format('DROP TRIGGER %I ON public.%I', names.delete_trigger_name, names.view_name);
    EXECUTE format('DROP FUNCTION admin.%I', names.upsert_function_name);
    EXECUTE format('DROP FUNCTION admin.%I', names.delete_function_name);

    -- Drop view
    EXECUTE format('DROP VIEW public.%I', names.view_name);

END;
$custom_view_def_destroy$ LANGUAGE plpgsql;

-- Before trigger for custom_view_def
\echo admin.custom_view_def_before
CREATE OR REPLACE FUNCTION admin.custom_view_def_before()
RETURNS trigger AS $$
BEGIN
    PERFORM admin.custom_view_def_destroy(OLD);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_view_def_before_trigger
BEFORE UPDATE OR DELETE ON public.custom_view_def
FOR EACH ROW EXECUTE FUNCTION admin.custom_view_def_before();

-- After trigger for custom_view_def
\echo admin.custom_view_def_after
CREATE OR REPLACE FUNCTION admin.custom_view_def_after()
RETURNS trigger AS $$
BEGIN
    PERFORM admin.custom_view_def_generate(NEW);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_view_def_after_trigger
AFTER INSERT OR UPDATE ON public.custom_view_def
FOR EACH ROW EXECUTE FUNCTION admin.custom_view_def_after();





WITH tt AS (
    SELECT * FROM public.custom_view_def_target_table
    WHERE schema_name = 'public'
      AND table_name = 'legal_unit'
), def AS (
    INSERT INTO public.custom_view_def(target_table_id, slug, name, note)
    SELECT id, 'brreg_hovedenhet', 'Import of BRREG Hovedenhet', 'Easy upload of the CSV file found at brreg.'
    FROM tt
    RETURNING *
), source(priority, column_name) AS (
VALUES (1, 'organisasjonsnummer')
    , ( 2, 'navn')
    , ( 3, 'organisasjonsform.kode')
    , ( 4, 'organisasjonsform.beskrivelse')
    , ( 5, 'naeringskode1.kode')
    , ( 6, 'naeringskode1.beskrivelse')
    , ( 7, 'naeringskode2.kode')
    , ( 8, 'naeringskode2.beskrivelse')
    , ( 9, 'naeringskode3.kode')
    , (10, 'naeringskode3.beskrivelse')
    , (11, 'hjelpeenhetskode.kode')
    , (12, 'hjelpeenhetskode.beskrivelse')
    , (13, 'harRegistrertAntallAnsatte')
    , (14, 'antallAnsatte')
    , (15, 'hjemmeside')
    , (16, 'postadresse.adresse')
    , (17, 'postadresse.poststed')
    , (18, 'postadresse.postnummer')
    , (19, 'postadresse.kommune')
    , (20, 'postadresse.kommunenummer')
    , (21, 'postadresse.land')
    , (22, 'postadresse.landkode')
    , (23, 'forretningsadresse.adresse')
    , (24, 'forretningsadresse.poststed')
    , (25, 'forretningsadresse.postnummer')
    , (26, 'forretningsadresse.kommune')
    , (27, 'forretningsadresse.kommunenummer')
    , (28, 'forretningsadresse.land')
    , (29, 'forretningsadresse.landkode')
    , (30, 'institusjonellSektorkode.kode')
    , (31, 'institusjonellSektorkode.beskrivelse')
    , (32, 'sisteInnsendteAarsregnskap')
    , (33, 'registreringsdatoenhetsregisteret')
    , (34, 'stiftelsesdato')
    , (35, 'registrertIMvaRegisteret')
    , (36, 'frivilligMvaRegistrertBeskrivelser')
    , (37, 'registrertIFrivillighetsregisteret')
    , (38, 'registrertIForetaksregisteret')
    , (39, 'registrertIStiftelsesregisteret')
    , (40, 'konkurs')
    , (41, 'konkursdato')
    , (42, 'underAvvikling')
    , (43, 'underAvviklingDato')
    , (44, 'underTvangsavviklingEllerTvangsopplosning')
    , (45, 'tvangsopplostPgaManglendeDagligLederDato')
    , (46, 'tvangsopplostPgaManglendeRevisorDato')
    , (47, 'tvangsopplostPgaManglendeRegnskapDato')
    , (48, 'tvangsopplostPgaMangelfulltStyreDato')
    , (49, 'tvangsavvikletPgaManglendeSlettingDato')
    , (50, 'overordnetEnhet')
    , (51, 'maalform')
    , (52, 'vedtektsdato')
    , (53, 'vedtektsfestetFormaal')
    , (54, 'aktivitet')
), inserted_source_column AS (
    INSERT INTO public.custom_view_def_source_column (custom_view_def_id,column_name, priority)
    SELECT def.id, source.column_name, source.priority
    FROM def, source
   RETURNING *
), mapping AS (
    SELECT def.id
         , (SELECT id FROM inserted_source_column
            WHERE column_name = 'organisasjonsnummer'
            )
         , (SELECT id
            FROM public.custom_view_def_target_column
            WHERE column_name = 'tax_ident'
              AND target_table_id = def.target_table_id
            )
    FROM def
    UNION ALL
    SELECT def.id
         , (SELECT id FROM inserted_source_column
            WHERE column_name = 'stiftelsesdato'
            )
         , (SELECT id
            FROM public.custom_view_def_target_column
            WHERE column_name = 'birth_date'
              AND target_table_id = def.target_table_id
            )
    FROM def
    UNION ALL
    SELECT def.id
         , (SELECT id FROM inserted_source_column
            WHERE column_name = 'navn'
            )
         , (SELECT id
            FROM public.custom_view_def_target_column
            WHERE column_name = 'name'
              AND target_table_id = def.target_table_id
            )
    FROM def
)
INSERT INTO public.custom_view_def_mapping
    ( custom_view_def_id
    , source_column_id
    , target_column_id
    )
SELECT * FROM mapping;
;


--


\echo public.generate_mermaid_er_diagram
CREATE OR REPLACE FUNCTION public.generate_mermaid_er_diagram()
RETURNS text AS $$
DECLARE
    rec RECORD;
    result text := 'erDiagram';
BEGIN
    -- First part of the query (tables and columns)
    FOR rec IN
        SELECT format(E'\t%s{\n%s\n}',
            c.relname,
            string_agg(format(E'\t\t%s %s',
                format_type(t.oid, a.atttypmod),
                a.attname
            ), E'\n')
        )
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute a ON c.oid = a.attrelid AND a.attnum > 0 AND NOT a.attisdropped
        LEFT JOIN pg_type t ON a.atttypid = t.oid
        WHERE c.relkind IN ('r', 'p')
          AND NOT c.relispartition
          AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
        GROUP BY c.relname
    LOOP
        result := result || E'\n' || rec.format;
    END LOOP;

    -- Second part of the query (foreign key constraints)
    FOR rec IN
        SELECT format('%s }|..|| %s : %s', c1.relname, c2.relname, c.conname)
        FROM pg_constraint c
        JOIN pg_class c1 ON c.conrelid = c1.oid AND c.contype = 'f'
        JOIN pg_class c2 ON c.confrelid = c2.oid
        WHERE NOT c1.relispartition AND NOT c2.relispartition
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
RETURNS TRIGGER AS $$
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
       WHERE sector.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


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
SELECT admin.generate_table_views_for_batch_api('public.sector', 'path');
SET LOCAL client_min_messages TO INFO;

\copy public.sector_system(path, name) FROM 'dbseed/sector.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.legal_form', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.legal_form_system(code, name) FROM 'dbseed/legal_form.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.reorg_type', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.reorg_type_system(code, name, description) FROM 'dbseed/reorg_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.foreign_participation', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.foreign_participation_system(code, name) FROM 'dbseed/foreign_participation.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.data_source', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.data_source_system(code, name) FROM 'dbseed/data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.unit_size', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.unit_size_system(code, name) FROM 'dbseed/unit_size.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.person_type', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.person_type_system(code, name) FROM 'dbseed/person_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_type', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.enterprise_group_type_system(code, name) FROM 'dbseed/enterprise_group_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_role', 'code');
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
  existing_id integer;
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
  IF NEW.id IS NULL THEN
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
            'id',
            'stat_ident',
            'tax_ident',
            jsonb_build_array('external_ident', 'external_ident_type'),
            jsonb_build_array('by_tag_id', 'by_tag_id_unique_ident')
        );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY['seen_in_import_at'];
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
            'id',
            'stat_ident',
            'tax_ident',
            jsonb_build_array('external_ident', 'external_ident_type'),
            jsonb_build_array('by_tag_id', 'by_tag_id_unique_ident')
        );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY['seen_in_import_at'];
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

\echo public.import_legal_unit_era
CREATE VIEW public.import_legal_unit_era
WITH (security_invoker=on) AS
SELECT '' AS valid_from
     , '' AS valid_to
     , '' AS tax_ident
     , '' AS name
     , '' AS birth_date
     , '' AS death_date
     , '' AS physical_address_part1
     , '' AS physical_address_part2
     , '' AS physical_address_part3
     , '' AS physical_postal_code
     , '' AS physical_postal_place
     , '' AS physical_region_code
     , '' AS physical_country_iso_2
     , '' AS postal_address_part1
     , '' AS postal_address_part2
     , '' AS postal_address_part3
     , '' AS postal_postal_code
     , '' AS postal_postal_place
     , '' AS postal_region_code
     , '' AS postal_country_iso_2
     , '' AS primary_activity_category_code
     , '' AS secondary_activity_category_code
     , '' AS sector_code
     , '' AS legal_form_code
     , '' AS tag_path
;

\echo admin.import_legal_unit_era_upsert
CREATE FUNCTION admin.import_legal_unit_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    edited_by_user RECORD;
    tag RECORD;
    physical_region RECORD;
    physical_country RECORD;
    postal_region RECORD;
    postal_country RECORD;
    primary_activity_category RECORD;
    secondary_activity_category RECORD;
    sector RECORD;
    legal_form RECORD;
    upsert_data RECORD;
    new_typed RECORD;
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
    SELECT NULL::int AS id INTO tag;
    SELECT NULL::int AS id INTO enterprise;
    SELECT NULL::int AS id INTO physical_region;
    SELECT NULL::int AS id INTO physical_country;
    SELECT NULL::int AS id INTO postal_region;
    SELECT NULL::int AS id INTO postal_country;
    SELECT NULL::int AS id INTO primary_activity_category;
    SELECT NULL::int AS id INTO secondary_activity_category;
    SELECT NULL::int AS id INTO sector;
    SELECT NULL::int AS id INTO legal_form;

    SELECT * INTO edited_by_user
    FROM public.statbus_user
    -- TODO: Uncomment when going into production
    -- WHERE uuid = auth.uid()
    LIMIT 1;

    IF NEW.tag_path IS NOT NULL AND NEW.tag_path <> '' THEN
        SELECT * INTO tag
        FROM public.tag
        WHERE active
          AND path = NEW.tag_path::public.ltree;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid tag_path for row %', to_json(NEW);
        END IF;
    END IF;

    IF NEW.physical_country_iso_2 IS NOT NULL AND NEW.physical_country_iso_2 <> '' THEN
      SELECT * INTO physical_country
      FROM public.country
      WHERE iso_2 = NEW.physical_country_iso_2;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find physical_country_iso_2 for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{physical_country_iso_2}', to_jsonb(NEW.physical_country_iso_2), true);
      END IF;
    END IF;

    IF NEW.physical_region_code IS NOT NULL AND NEW.physical_region_code <> '' THEN
      SELECT * INTO physical_region
      FROM public.region
      WHERE code = NEW.physical_region_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find physical_region_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{physical_region_code}', to_jsonb(NEW.physical_region_code), true);
      END IF;
    END IF;

    IF NEW.postal_country_iso_2 IS NOT NULL AND NEW.postal_country_iso_2 <> '' THEN
      SELECT * INTO postal_country
      FROM public.country
      WHERE iso_2 = NEW.postal_country_iso_2;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find postal_country_iso_2 for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{postal_country_iso_2}', to_jsonb(NEW.postal_country_iso_2), true);
      END IF;
    END IF;

    IF NEW.postal_region_code IS NOT NULL AND NEW.postal_region_code <> '' THEN
      SELECT * INTO postal_region
      FROM public.region
      WHERE code = NEW.postal_region_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find postal_region_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{postal_region_code}', to_jsonb(NEW.postal_region_code), true);
      END IF;
    END IF;

    IF NEW.primary_activity_category_code IS NOT NULL AND NEW.primary_activity_category_code <> '' THEN
      SELECT * INTO primary_activity_category
      FROM public.activity_category_available
      WHERE code = NEW.primary_activity_category_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find primary_activity_category_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{primary_activity_category_code}', to_jsonb(NEW.primary_activity_category_code), true);
      END IF;
    END IF;

    IF NEW.secondary_activity_category_code IS NOT NULL AND NEW.secondary_activity_category_code <> '' THEN
      SELECT * INTO secondary_activity_category
      FROM public.activity_category_available
      WHERE code = NEW.secondary_activity_category_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find secondary_activity_category_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{secondary_activity_category_code}', to_jsonb(NEW.secondary_activity_category_code), true);
      END IF;
    END IF;

    IF NEW.sector_code IS NOT NULL AND NEW.sector_code <> '' THEN
      SELECT * INTO sector
      FROM public.sector
      WHERE code = NEW.sector_code
        AND active;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find sector_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{sector_code}', to_jsonb(NEW.sector_code), true);
      END IF;
    END IF;

    IF NEW.legal_form_code IS NOT NULL AND NEW.legal_form_code <> '' THEN
      SELECT * INTO legal_form
      FROM public.legal_form
      WHERE code = NEW.legal_form_code
        AND active;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find legal_form_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{legal_form_code}', to_jsonb(NEW.legal_form_code), true);
      END IF;
    END IF;

    IF NEW.birth_date IS NOT NULL AND NEW.birth_date <> '' THEN
        BEGIN
            new_typed.birth_date := NEW.birth_date::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid birth_date for row %', to_json(NEW);
        END;
    END IF;

    IF NEW.death_date IS NOT NULL AND NEW.death_date <> '' THEN
        BEGIN
            new_typed.death_date := NEW.death_date::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid death_date for row %', to_json(NEW);
        END;
    END IF;

    BEGIN
        new_typed.valid_from := NEW.valid_from::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid valid_from for row %', to_json(NEW);
    END;

    BEGIN
        new_typed.valid_to := NEW.valid_to::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid valid_to for row %', to_json(NEW);
    END;

    SELECT NEW.tax_ident AS tax_ident
         , NEW.name AS name
         , new_typed.birth_date AS birth_date
         , new_typed.death_date AS death_date
         , true AS active
         , statement_timestamp() AS seen_in_import_at
         , 'Batch import' AS edit_comment
         , CASE WHEN invalid_codes <@ '{}'::jsonb THEN NULL ELSE invalid_codes END AS invalid_codes
      INTO upsert_data;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- TODO: Lookup any existing enterprise and re-use it
    -- SELECT * INTO enterprise
    -- FROM public.enterprise
    -- WHERE

    -- Create an enterprise and connect to it.
    INSERT INTO public.enterprise
        ( active
        , edit_by_user_id
        , edit_comment
        )
    VALUES
        ( true
        , edited_by_user.id
        , 'Batch import'
        ) RETURNING *
     INTO enterprise;
    is_primary_for_enterprise := true;

    INSERT INTO public.legal_unit_era
        ( tax_ident
        , valid_from
        , valid_to
        , name
        , birth_date
        , death_date
        , active
        , seen_in_import_at
        , edit_comment
        , sector_id
        , legal_form_id
        , invalid_codes
        , enterprise_id
        , primary_for_enterprise
        , edit_by_user_id
        )
    VALUES
        ( upsert_data.tax_ident
        , new_typed.valid_from
        , new_typed.valid_to
        , upsert_data.name
        , upsert_data.birth_date
        , upsert_data.death_date
        , upsert_data.active
        , upsert_data.seen_in_import_at
        , upsert_data.edit_comment
        , sector.id
        , legal_form.id
        , upsert_data.invalid_codes
        , enterprise.id
        , is_primary_for_enterprise
        , edited_by_user.id
        )
     RETURNING *
     INTO inserted_legal_unit;
    RAISE DEBUG 'inserted_legal_unit %', to_json(inserted_legal_unit);

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
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
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
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF primary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'primary'
            , primary_activity_category.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF secondary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'secondary'
            , secondary_activity_category.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

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

CREATE TRIGGER import_legal_unit_era_upsert_trigger
INSTEAD OF INSERT ON public.import_legal_unit_era
FOR EACH ROW
EXECUTE FUNCTION admin.import_legal_unit_era_upsert();



\echo public.import_legal_unit_current
CREATE VIEW public.import_legal_unit_current
WITH (security_invoker=on) AS
SELECT tax_ident
     , name
     , birth_date
     , death_date
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_code
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_code
     , postal_country_iso_2
     , primary_activity_category_code
     , secondary_activity_category_code
     , sector_code
     , legal_form_code
     , tag_path
FROM public.import_legal_unit_era;

\echo admin.import_legal_unit_current_upsert
CREATE FUNCTION admin.import_legal_unit_current_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_legal_unit_current_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_legal_unit_era
        ( valid_from
        , valid_to
        , tax_ident
        , name
        , birth_date
        , death_date
        , physical_address_part1
        , physical_address_part2
        , physical_address_part3
        , physical_postal_code
        , physical_postal_place
        , physical_region_code
        , physical_country_iso_2
        , postal_address_part1
        , postal_address_part2
        , postal_address_part3
        , postal_postal_code
        , postal_postal_place
        , postal_region_code
        , postal_country_iso_2
        , primary_activity_category_code
        , secondary_activity_category_code
        , sector_code
        , legal_form_code
        , tag_path
        )
    VALUES
        ( new_valid_from
        , new_valid_to
        , NEW.tax_ident
        , NEW.name
        , NEW.birth_date
        , NEW.death_date
        , NEW.physical_address_part1
        , NEW.physical_address_part2
        , NEW.physical_address_part3
        , NEW.physical_postal_code
        , NEW.physical_postal_place
        , NEW.physical_region_code
        , NEW.physical_country_iso_2
        , NEW.postal_address_part1
        , NEW.postal_address_part2
        , NEW.postal_address_part3
        , NEW.postal_postal_code
        , NEW.postal_postal_place
        , NEW.postal_region_code
        , NEW.postal_country_iso_2
        , NEW.primary_activity_category_code
        , NEW.secondary_activity_category_code
        , NEW.sector_code
        , NEW.legal_form_code
        , NEW.tag_path
        );
    RETURN NULL;
END;
$import_legal_unit_current_upsert$;


CREATE TRIGGER import_legal_unit_current_upsert_trigger
INSTEAD OF INSERT ON public.import_legal_unit_current
FOR EACH ROW
EXECUTE FUNCTION admin.import_legal_unit_current_upsert();


\echo public.import_legal_unit_with_delete_current
CREATE VIEW public.import_legal_unit_with_delete_current
WITH (security_invoker=on) AS
SELECT * FROM public.import_legal_unit_current;

\echo admin.import_legal_unit_with_delete_current
CREATE FUNCTION admin.import_legal_unit_with_delete_current()
RETURNS TRIGGER AS $$
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    )
    UPDATE public.legal_unit
    SET valid_to = current_date
      , edit_comment = 'Absent from upload'
      , edit_by_user_id = (SELECT id FROM su)
      , active = false
    WHERE seen_in_import_at < statement_timestamp()
      AND valid_to = 'infinity'::date
      AND active
    ;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER import_legal_unit_with_delete_current_trigger
AFTER INSERT ON public.import_legal_unit_with_delete_current
FOR EACH STATEMENT
EXECUTE FUNCTION admin.import_legal_unit_with_delete_current();


\echo public.import_establishment_era
CREATE VIEW public.import_establishment_era
WITH (security_invoker=on) AS
SELECT '' AS valid_from
     , '' AS valid_to
     , '' AS tax_ident
     , '' AS legal_unit_tax_ident
     , '' AS name
     , '' AS birth_date
     , '' AS death_date
     , '' AS physical_address_part1
     , '' AS physical_address_part2
     , '' AS physical_address_part3
     , '' AS physical_postal_code
     , '' AS physical_postal_place
     , '' AS physical_region_code
     , '' AS physical_country_iso_2
     , '' AS postal_address_part1
     , '' AS postal_address_part2
     , '' AS postal_address_part3
     , '' AS postal_postal_code
     , '' AS postal_postal_place
     , '' AS postal_region_code
     , '' AS postal_country_iso_2
     , '' AS primary_activity_category_code
     , '' AS secondary_activity_category_code
     , '' AS sector_code
     , '' AS employees
     , '' AS turnover
     , '' AS tag_path
;
COMMENT ON VIEW public.import_establishment_era IS 'Upload of establishment with all available fields';

\echo admin.import_establishment_era_upsert
CREATE FUNCTION admin.import_establishment_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
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
    upsert_data RECORD;
    new_typed RECORD;
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
    SELECT NULL::int AS employees
         , NULL::int AS turnover
        INTO stats;

    SELECT * INTO edited_by_user
    FROM public.statbus_user
    -- TODO: Uncomment when going into production
    -- WHERE uuid = auth.uid()
    LIMIT 1;

    IF NEW.tag_path IS NOT NULL AND NEW.tag_path <> '' THEN
        SELECT * INTO tag
        FROM public.tag
        WHERE active
          AND path = NEW.tag_path::public.ltree;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid tag_path for row %', to_json(NEW);
        END IF;
    END IF;

    IF NEW.birth_date IS NOT NULL AND NEW.birth_date <> '' THEN
        BEGIN
            new_typed.birth_date := NEW.birth_date::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid birth_date for row %', to_json(NEW);
        END;
    END IF;

    IF NEW.death_date IS NOT NULL AND NEW.death_date <> '' THEN
        BEGIN
            new_typed.death_date := NEW.death_date::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid death_date for row %', to_json(NEW);
        END;
    END IF;

    BEGIN
        new_typed.valid_from := NEW.valid_from::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid valid_from for row %', to_json(NEW);
    END;

    BEGIN
        new_typed.valid_to := NEW.valid_to::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid valid_to for row %', to_json(NEW);
    END;

    IF NEW.legal_unit_tax_ident IS NULL OR NEW.legal_unit_tax_ident = '' THEN
        -- TODO: Reuse any existing enterprise connection.
        -- Create an enterprise and connect to it.
        INSERT INTO public.enterprise
            ( active
            , edit_by_user_id
            , edit_comment
            ) VALUES
            ( true
            , edited_by_user.id
            , 'Batch import'
            ) RETURNING *
            INTO enterprise;
    ELSE -- Lookup the legal_unit - it must exist.
        SELECT lu.* INTO legal_unit
        FROM public.legal_unit AS lu
        WHERE lu.tax_ident = NEW.legal_unit_tax_ident
          AND daterange(lu.valid_from, lu.valid_to, '[]')
            && daterange(new_typed.valid_from, new_typed.valid_to, '[]')
        ;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find legal_unit_tax_ident for row %', to_json(NEW);
        END IF;
        PERFORM *
        FROM public.establishment AS es
        WHERE es.legal_unit_id = legal_unit.id
          AND daterange(es.valid_from, es.valid_to, '[]')
            && daterange(new_typed.valid_from, new_typed.valid_to, '[]')
        LIMIT 1;
        IF NOT FOUND THEN
            is_primary_for_legal_unit := true;
        ELSE
            is_primary_for_legal_unit := false;
        END IF;
    END IF;

    IF NEW.physical_country_iso_2 IS NOT NULL AND NEW.physical_country_iso_2 <> '' THEN
      SELECT * INTO physical_country
      FROM public.country
      WHERE iso_2 = NEW.physical_country_iso_2;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find physical_country_iso_2 for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{physical_country_iso_2}', to_jsonb(NEW.physical_country_iso_2), true);
      END IF;
    END IF;

    IF NEW.physical_region_code IS NOT NULL AND NEW.physical_region_code <> '' THEN
      SELECT * INTO physical_region
      FROM public.region
      WHERE code = NEW.physical_region_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find physical_region_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{physical_region_code}', to_jsonb(NEW.physical_region_code), true);
      END IF;
    END IF;

    IF NEW.postal_country_iso_2 IS NOT NULL AND NEW.postal_country_iso_2 <> '' THEN
      SELECT * INTO postal_country
      FROM public.country
      WHERE iso_2 = NEW.postal_country_iso_2;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find postal_country_iso_2 for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{postal_country_iso_2}', to_jsonb(NEW.postal_country_iso_2), true);
      END IF;
    END IF;

    IF NEW.postal_region_code IS NOT NULL AND NEW.postal_region_code <> '' THEN
      SELECT * INTO postal_region
      FROM public.region
      WHERE code = NEW.postal_region_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find postal_region_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{postal_region_code}', to_jsonb(NEW.postal_region_code), true);
      END IF;
    END IF;

    IF NEW.primary_activity_category_code IS NOT NULL AND NEW.primary_activity_category_code <> '' THEN
      SELECT * INTO primary_activity_category
      FROM public.activity_category_available
      WHERE code = NEW.primary_activity_category_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find primary_activity_category_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{primary_activity_category_code}', to_jsonb(NEW.primary_activity_category_code), true);
      END IF;
    END IF;

    IF NEW.secondary_activity_category_code IS NOT NULL AND NEW.secondary_activity_category_code <> '' THEN
      SELECT * INTO secondary_activity_category
      FROM public.activity_category_available
      WHERE code = NEW.secondary_activity_category_code;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find secondary_activity_category_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{secondary_activity_category_code}', to_jsonb(NEW.secondary_activity_category_code), true);
      END IF;
    END IF;

    IF NEW.sector_code IS NOT NULL AND NEW.sector_code <> '' THEN
      SELECT * INTO sector
      FROM public.sector
      WHERE code = NEW.sector_code
        AND active;
      IF NOT FOUND THEN
        RAISE WARNING 'Could not find sector_code for row %', to_json(NEW);
        invalid_codes := jsonb_set(invalid_codes, '{sector_code}', to_jsonb(NEW.sector_code), true);
      END IF;
    END IF;

    SELECT NEW.tax_ident AS tax_ident
         , NEW.name AS name
         , new_typed.birth_date AS birth_date
         , new_typed.death_date AS death_date
         , true AS active
         , statement_timestamp() AS seen_in_import_at
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
        ( tax_ident
        , valid_from
        , valid_to
        , name
        , birth_date
        , death_date
        , active
        , seen_in_import_at
        , edit_comment
        , sector_id
        , invalid_codes
        , enterprise_id
        , legal_unit_id
        , primary_for_legal_unit
        , edit_by_user_id
        )
    VALUES
        ( upsert_data.tax_ident
        , new_typed.valid_from
        , new_typed.valid_to
        , upsert_data.name
        , upsert_data.birth_date
        , upsert_data.death_date
        , upsert_data.active
        , upsert_data.seen_in_import_at
        , upsert_data.edit_comment
        , sector.id
        , upsert_data.invalid_codes
        , upsert_data.enterprise_id
        , upsert_data.legal_unit_id
        , upsert_data.primary_for_legal_unit
        , edited_by_user.id
        )
     RETURNING *
     INTO inserted_establishment;
    RAISE DEBUG 'inserted_establishment %', to_json(inserted_establishment);

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
            , edited_by_user.id
            )
        RETURNING *
        INTO inserted_location;
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
            , edited_by_user.id
            )
        RETURNING * INTO inserted_location;
    END IF;

    IF primary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , category_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'primary'
            , primary_activity_category.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF secondary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , establishment_id
            , type
            , category_id
            , updated_by_user_id
            , updated_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , 'secondary'
            , secondary_activity_category.id
            , edited_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NEW.employees IS NOT NULL AND NEW.employees <> '' THEN
        BEGIN
            stats.employees := NEW.employees::INTEGER;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid employees integer for row %', to_json(NEW);
        END;

        SELECT * INTO stat_def
        FROM stat_definition
        WHERE code = 'employees';

        INSERT INTO public.stat_for_unit_era
            ( stat_definition_id
            , valid_from
            , valid_to
            , establishment_id
            , value_int
            )
        VALUES
            ( stat_def.id
            , new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , stats.employees
            )
        RETURNING *
        INTO inserted_stat_for_unit;
    END IF;

    IF NEW.turnover IS NOT NULL AND NEW.turnover <> '' THEN
        BEGIN
            stats.turnover := NEW.turnover::INTEGER;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid turnover integer for row %', to_json(NEW);
        END;

        SELECT * INTO stat_def
        FROM stat_definition
        WHERE code = 'turnover';

        INSERT INTO public.stat_for_unit_era
            ( stat_definition_id
            , valid_from
            , valid_to
            , establishment_id
            , value_int
            )
        VALUES
            ( stat_def.id
            , new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
            , stats.turnover
            )
        RETURNING * INTO inserted_stat_for_unit;
    END IF;

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

CREATE TRIGGER import_establishment_era_upsert_trigger
INSTEAD OF INSERT ON public.import_establishment_era
FOR EACH ROW
EXECUTE FUNCTION admin.import_establishment_era_upsert();


\echo public.import_establishment_era_for_legal_unit
CREATE VIEW public.import_establishment_era_for_legal_unit
WITH (security_invoker=on) AS
SELECT valid_from
     , valid_to
     , tax_ident
     -- Required - it must connect to an existing legal_unit
     , legal_unit_tax_ident
     , name
     , birth_date
     , death_date
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_code
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_code
     , postal_country_iso_2
     , primary_activity_category_code
     , secondary_activity_category_code
     -- sector_code is Disabled because the legal unit provides the sector_code
     , employees
     , turnover
     , tag_path
FROM public.import_establishment_era;
COMMENT ON VIEW public.import_establishment_era_for_legal_unit IS 'Upload of establishment era (any timeline) that must connect to a legal_unit';

\echo admin.import_establishment_era_for_legal_unit_upsert
CREATE FUNCTION admin.import_establishment_era_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.legal_unit_tax_ident IS NULL OR NEW.legal_unit_tax_ident = '' THEN
      RAISE EXCEPTION 'Missing legal_unit_tax_ident for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era
        ( valid_from
        , valid_to
        , tax_ident
        , legal_unit_tax_ident
        , name
        , birth_date
        , death_date
        , physical_address_part1
        , physical_address_part2
        , physical_address_part3
        , physical_postal_code
        , physical_postal_place
        , physical_region_code
        , physical_country_iso_2
        , postal_address_part1
        , postal_address_part2
        , postal_address_part3
        , postal_postal_code
        , postal_postal_place
        , postal_region_code
        , postal_country_iso_2
        , primary_activity_category_code
        , secondary_activity_category_code
        , employees
        , turnover
        , tag_path
        )
    VALUES
        ( NEW.valid_from
        , NEW.valid_to
        , NEW.tax_ident
        , NEW.legal_unit_tax_ident
        , NEW.name
        , NEW.birth_date
        , NEW.death_date
        , NEW.physical_address_part1
        , NEW.physical_address_part2
        , NEW.physical_address_part3
        , NEW.physical_postal_code
        , NEW.physical_postal_place
        , NEW.physical_region_code
        , NEW.physical_country_iso_2
        , NEW.postal_address_part1
        , NEW.postal_address_part2
        , NEW.postal_address_part3
        , NEW.postal_postal_code
        , NEW.postal_postal_place
        , NEW.postal_region_code
        , NEW.postal_country_iso_2
        , NEW.primary_activity_category_code
        , NEW.secondary_activity_category_code
        , NEW.employees
        , NEW.turnover
        , NEW.tag_path
        );
    RETURN NULL;
END;
$$;

CREATE TRIGGER import_establishment_era_for_legal_unit_upsert_trigger
INSTEAD OF INSERT ON public.import_establishment_era_for_legal_unit
FOR EACH ROW
EXECUTE FUNCTION admin.import_establishment_era_for_legal_unit_upsert();

\echo public.import_establishment_current_for_legal_unit
CREATE VIEW public.import_establishment_current_for_legal_unit
WITH (security_invoker=on) AS
SELECT tax_ident
     , legal_unit_tax_ident
     , name
     , birth_date
     , death_date
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_code
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_code
     , postal_country_iso_2
     , primary_activity_category_code
     , secondary_activity_category_code
     -- sector_code is Disabled because the legal unit provides the sector_code
     , employees
     , turnover
     , tag_path
FROM public.import_establishment_era;
COMMENT ON VIEW public.import_establishment_current_for_legal_unit IS 'Upload of establishment from today and forwards that must connect to a legal_unit';


\echo admin.import_establishment_current_for_legal_unit_upsert
CREATE FUNCTION admin.import_establishment_current_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    IF NEW.legal_unit_tax_ident IS NULL OR NEW.legal_unit_tax_ident = '' THEN
      RAISE EXCEPTION 'Missing legal_unit_tax_ident for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era
        ( valid_from
        , valid_to
        , tax_ident
        , legal_unit_tax_ident
        , name
        , birth_date
        , death_date
        , physical_address_part1
        , physical_address_part2
        , physical_address_part3
        , physical_postal_code
        , physical_postal_place
        , physical_region_code
        , physical_country_iso_2
        , postal_address_part1
        , postal_address_part2
        , postal_address_part3
        , postal_postal_code
        , postal_postal_place
        , postal_region_code
        , postal_country_iso_2
        , primary_activity_category_code
        , secondary_activity_category_code
        , employees
        , turnover
        , tag_path
        )
    VALUES
        ( new_valid_from
        , new_valid_to
        , NEW.tax_ident
        , NEW.legal_unit_tax_ident
        , NEW.name
        , NEW.birth_date
        , NEW.death_date
        , NEW.physical_address_part1
        , NEW.physical_address_part2
        , NEW.physical_address_part3
        , NEW.physical_postal_code
        , NEW.physical_postal_place
        , NEW.physical_region_code
        , NEW.physical_country_iso_2
        , NEW.postal_address_part1
        , NEW.postal_address_part2
        , NEW.postal_address_part3
        , NEW.postal_postal_code
        , NEW.postal_postal_place
        , NEW.postal_region_code
        , NEW.postal_country_iso_2
        , NEW.primary_activity_category_code
        , NEW.secondary_activity_category_code
        , NEW.employees
        , NEW.turnover
        , NEW.tag_path
        );
    RETURN NULL;
END;
$$;

CREATE TRIGGER import_establishment_current_for_legal_unit_upsert_trigger
INSTEAD OF INSERT ON public.import_establishment_current_for_legal_unit
FOR EACH ROW
EXECUTE FUNCTION admin.import_establishment_current_for_legal_unit_upsert();


\echo public.import_establishment_era_without_legal_unit
CREATE VIEW public.import_establishment_era_without_legal_unit
WITH (security_invoker=on) AS
SELECT valid_from
     , valid_to
     , tax_ident
     -- legal_unit_tax_ident is Disabled because this is an informal sector
     , name
     , birth_date
     , death_date
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_code
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_code
     , postal_country_iso_2
     , primary_activity_category_code
     , secondary_activity_category_code
     , sector_code -- Is allowed, since there is no legal unit to provide it.
     , employees
     , turnover
     , tag_path
FROM public.import_establishment_era;


\echo admin.import_establishment_era_without_legal_unit_upsert
CREATE FUNCTION admin.import_establishment_era_without_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.import_establishment_era
        ( valid_from
        , valid_to
        , tax_ident
        , name
        , birth_date
        , death_date
        , physical_address_part1
        , physical_address_part2
        , physical_address_part3
        , physical_postal_code
        , physical_postal_place
        , physical_region_code
        , physical_country_iso_2
        , postal_address_part1
        , postal_address_part2
        , postal_address_part3
        , postal_postal_code
        , postal_postal_place
        , postal_region_code
        , postal_country_iso_2
        , primary_activity_category_code
        , secondary_activity_category_code
        , sector_code
        , employees
        , turnover
        , tag_path
        )
    VALUES
        ( NEW.valid_from
        , NEW.valid_to
        , NEW.tax_ident
        , NEW.name
        , NEW.birth_date
        , NEW.death_date
        , NEW.physical_address_part1
        , NEW.physical_address_part2
        , NEW.physical_address_part3
        , NEW.physical_postal_code
        , NEW.physical_postal_place
        , NEW.physical_region_code
        , NEW.physical_country_iso_2
        , NEW.postal_address_part1
        , NEW.postal_address_part2
        , NEW.postal_address_part3
        , NEW.postal_postal_code
        , NEW.postal_postal_place
        , NEW.postal_region_code
        , NEW.postal_country_iso_2
        , NEW.primary_activity_category_code
        , NEW.secondary_activity_category_code
        , NEW.sector_code
        , NEW.employees
        , NEW.turnover
        , NEW.tag_path
        );
    RETURN NULL;
END;
$$;

CREATE TRIGGER import_establishment_era_without_legal_unit_upsert_trigger
INSTEAD OF INSERT ON public.import_establishment_era_without_legal_unit
FOR EACH ROW
EXECUTE FUNCTION admin.import_establishment_era_without_legal_unit_upsert();

\echo public.import_establishment_current_without_legal_unit
CREATE VIEW public.import_establishment_current_without_legal_unit
WITH (security_invoker=on) AS
SELECT tax_ident
     -- legal_unit_tax_ident is Disabled because this is an informal sector
     , name
     , birth_date
     , death_date
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_code
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_code
     , postal_country_iso_2
     , primary_activity_category_code
     , secondary_activity_category_code
     , sector_code -- Is allowed, since there is no legal unit to provide it.
     , employees
     , turnover
     , tag_path
FROM public.import_establishment_era;


\echo admin.import_establishment_current_without_legal_unit_upsert
CREATE FUNCTION admin.import_establishment_current_without_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era
        ( valid_from
        , valid_to
        , tax_ident
        , name
        , birth_date
        , death_date
        , physical_address_part1
        , physical_address_part2
        , physical_address_part3
        , physical_postal_code
        , physical_postal_place
        , physical_region_code
        , physical_country_iso_2
        , postal_address_part1
        , postal_address_part2
        , postal_address_part3
        , postal_postal_code
        , postal_postal_place
        , postal_region_code
        , postal_country_iso_2
        , primary_activity_category_code
        , secondary_activity_category_code
        , sector_code
        , employees
        , turnover
        , tag_path
        )
    VALUES
        ( new_valid_from
        , new_valid_to
        , NEW.tax_ident
        , NEW.name
        , NEW.birth_date
        , NEW.death_date
        , NEW.physical_address_part1
        , NEW.physical_address_part2
        , NEW.physical_address_part3
        , NEW.physical_postal_code
        , NEW.physical_postal_place
        , NEW.physical_region_code
        , NEW.physical_country_iso_2
        , NEW.postal_address_part1
        , NEW.postal_address_part2
        , NEW.postal_address_part3
        , NEW.postal_postal_code
        , NEW.postal_postal_place
        , NEW.postal_region_code
        , NEW.postal_country_iso_2
        , NEW.primary_activity_category_code
        , NEW.secondary_activity_category_code
        , NEW.sector_code
        , NEW.employees
        , NEW.turnover
        , NEW.tag_path
        );
    RETURN NULL;
END;
$$;

CREATE TRIGGER import_establishment_current_without_legal_unit_upsert_trigger
INSTEAD OF INSERT ON public.import_establishment_current_without_legal_unit
FOR EACH ROW
EXECUTE FUNCTION admin.import_establishment_current_without_legal_unit_upsert();


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
        , statement_timestamp() AS seen_in_import_at
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
          , seen_in_import_at = upsert_data.seen_in_import_at
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
          , seen_in_import_at
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
          , upsert_data.seen_in_import_at
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

\echo admin.legal_unit_brreg_view_delete_stale
CREATE FUNCTION admin.legal_unit_brreg_view_delete_stale()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    )
    UPDATE public.legal_unit
    SET valid_to = statement_timestamp()
      , edit_comment = 'Absent from upload'
      , edit_by_user_id = (SELECT id FROM su)
      , active = false
    WHERE seen_in_import_at < statement_timestamp();
    RETURN NULL;
END;
$$;

-- Create triggers for the view
CREATE TRIGGER legal_unit_brreg_view_upsert
INSTEAD OF INSERT ON public.legal_unit_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.legal_unit_brreg_view_upsert();

CREATE TRIGGER legal_unit_brreg_view_delete_stale
AFTER INSERT ON public.legal_unit_brreg_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.legal_unit_brreg_view_delete_stale();


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
        , statement_timestamp() AS seen_in_import_at
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
          , seen_in_import_at = upsert_data.seen_in_import_at
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
          , seen_in_import_at
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
          , upsert_data.seen_in_import_at
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

-- Create function for deleting stale countries
\echo admin.delete_stale_establishment_brreg_view
CREATE FUNCTION admin.delete_stale_establishment_brreg_view()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    )
    UPDATE public.establishment
    SET valid_to = statement_timestamp()
      , edit_comment = 'Absent from upload'
      , edit_by_user_id = (SELECT id FROM su)
      , active = false
    WHERE seen_in_import_at < statement_timestamp();
    RETURN NULL;
END;
$$;

-- Create triggers for the view
CREATE TRIGGER upsert_establishment_brreg_view
INSTEAD OF INSERT ON public.establishment_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_establishment_brreg_view();

CREATE TRIGGER delete_stale_establishment_brreg_view
AFTER INSERT ON public.establishment_brreg_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_establishment_brreg_view();


\echo public.reset_all_data(boolean confirmed)
CREATE FUNCTION public.reset_all_data (confirmed boolean)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

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

    -- Repeating the pattern for each remaining table...

    WITH deleted_establishment AS (
        DELETE FROM public.establishment WHERE id > 0 RETURNING *
    )
    SELECT jsonb_build_object(
        'establishment', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_establishment)
        )
    ) INTO changed;
    result := result || changed;

    WITH deleted_legal_unit AS (
        DELETE FROM public.legal_unit WHERE id > 0 RETURNING *
    )
    SELECT jsonb_build_object(
        'legal_unit', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_legal_unit)
        )
    ) INTO changed;
    result := result || changed;

    WITH deleted_enterprise AS (
        DELETE FROM public.enterprise WHERE id > 0 RETURNING *
    )
    SELECT jsonb_build_object(
        'enterprise', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_enterprise)
        )
    ) INTO changed;
    result := result || changed;

    WITH deleted_region AS (
        DELETE FROM public.region WHERE id > 0 RETURNING *
    )
    SELECT jsonb_build_object(
        'region', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_region)
        )
    ) INTO changed;
    result := result || changed;

    WITH deleted_settings AS (
        DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
    )
    SELECT jsonb_build_object(
        'settings', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
        )
    ) INTO changed;
    result := result || changed;

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
          -- How to ensure updated_child runs before this query?
        RETURNING *
    )
    SELECT changed || jsonb_build_object(
        'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
    ) INTO changed;
    SELECT jsonb_build_object('activity_category', changed) INTO changed;
    result := result || changed;

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
SELECT sql_saga.add_era('public.enterprise_group', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['stat_ident']);
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['external_ident', 'external_ident_type']);

SELECT sql_saga.add_era('public.legal_unit', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['stat_ident']);
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['tax_ident']);
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['external_ident', 'external_ident_type']);
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['by_tag_id', 'by_tag_id_unique_ident']);
-- TODO: Use a scoped sql_saga unique key for enterprise_id below.
-- SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['enterprise_id'], WHERE 'primary_for_enterprise');

SELECT sql_saga.add_era('public.establishment', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['stat_ident']);
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['tax_ident']);
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['external_ident', 'external_ident_type']);
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['by_tag_id', 'by_tag_id_unique_ident']);
-- TODO: Extend sql_saga with support for predicates by using unique indices instead of constraints.
--SELECT sql_saga.add_unique_key('public.establishment', ARRAY['legal_unit_id'], WHERE 'primary_for_legal_unit');
SELECT sql_saga.add_foreign_key('public.establishment', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.activity', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.activity', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.stat_for_unit', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['stat_definition_id', 'establishment_id']);
SELECT sql_saga.add_foreign_key('public.stat_for_unit', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');

SELECT sql_saga.add_era('public.location', 'valid_from', 'valid_to');
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
