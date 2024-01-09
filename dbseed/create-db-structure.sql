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

CREATE TYPE public.statbus_role_type AS ENUM('super_user', 'restricted_user', 'external_user');

CREATE TABLE public.statbus_role (
    id SERIAL PRIMARY KEY NOT NULL,
    role_type public.statbus_role_type NOT NULL,
    name character varying(256) NOT NULL UNIQUE,
    description text
);
-- There can only ever be one role for super_user and external_user,
-- while there can be many different restricted_user roles, depending on the actual restrictions.
CREATE UNIQUE INDEX statbus_role_role_type ON public.statbus_role(role_type) WHERE role_type = 'super_user' OR role_type = 'external_user';

CREATE TABLE public.statbus_user (
  id SERIAL PRIMARY KEY,
  uuid uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
  UNIQUE (uuid)
);


-- inserts a row into public.profiles
CREATE FUNCTION public.create_new_statbus_user()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  role_id INTEGER;
BEGIN
  -- Start with a minimal set of rights upon auto creation by trigger.
  SELECT id INTO role_id FROM public.statbus_role WHERE role_type = 'external_user';
  INSERT INTO public.statbus_user (uuid, role_id) VALUES (new.id, role_id);
  RETURN new;
END;
$$;

-- trigger the function every time a user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.create_new_statbus_user();

INSERT INTO public.statbus_role(role_type, name, description) VALUES ('super_user', 'Super User', 'Can do everything in the Web interface and manage role rights.');
INSERT INTO public.statbus_role(role_type, name, description) VALUES ('restricted_user', 'Restricted User', 'Can see everything and edit according to assigned region and/or activity');
INSERT INTO public.statbus_role(role_type, name, description) VALUES ('external_user', 'External User', 'Can see selected information');

-- Add a super user role for select users
INSERT INTO public.statbus_user (uuid, role_id)
SELECT id, (SELECT id FROM public.statbus_role WHERE role_type = 'super_user')
FROM auth.users
WHERE email like 'jorgen@veridit.no'
   OR email like 'erik.soberg@ssb.no'
   OR email like 'jonas.lundeland@sonat.no'
ON CONFLICT DO NOTHING;

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


CREATE TABLE public.activity_category_standard (
    id SERIAL PRIMARY KEY NOT NULL,
    code character varying(16) UNIQUE NOT NULL,
    name character varying UNIQUE NOT NULL,
    obsolete boolean NOT NULL DEFAULT false
);

INSERT INTO public.activity_category_standard(code, name)
VALUES ('isic_v4','ISIC Version 4')
     , ('nace_v2.1','NACE Version 2 Revision 1');

CREATE EXTENSION ltree SCHEMA public;

CREATE TABLE public.activity_category (
    id SERIAL PRIMARY KEY NOT NULL,
    activity_category_standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    path public.ltree NOT NULL,
    parent_id integer REFERENCES public.activity_category(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name character varying(256) NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(activity_category_standard_id, path)
);

-- Use a separate schema, that is not exposed by PostgREST, for administrative functions.
CREATE SCHEMA admin;

CREATE FUNCTION admin.upsert_activity_category()
RETURNS TRIGGER AS $$
DECLARE
    standardCode text;
    standardId int;
BEGIN
    -- Access the standard code passed as an argument
    standardCode := TG_ARGV[0];
    SELECT id INTO standardId FROM public.activity_category_standard WHERE code = standardCode;
    IF standardId IS NULL THEN
      RAISE EXCEPTION 'Unknown activity_category_standard.code %s', standardCode;
    END IF;

    WITH parent AS (
        SELECT activity_category.id
          FROM public.activity_category
         WHERE activity_category_standard_id = standardId
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.activity_category
        ( activity_category_standard_id
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
    ON CONFLICT (activity_category_standard_id, path)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                , custom = false
                ;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



CREATE FUNCTION admin.delete_stale_activity_category()
RETURNS TRIGGER AS $$
BEGIN
    -- All the `activity_category_standard_id` with a recent update must be complete.
    WITH changed_activity_category AS (
      SELECT DISTINCT activity_category_standard_id
      FROM public.activity_category
      WHERE updated_at = statement_timestamp()
    )
    -- Delete activities that have a stale updated_at
    DELETE FROM public.activity_category
    WHERE activity_category_standard_id IN (SELECT activity_category_standard_id FROM changed_activity_category)
    AND updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

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
ON ac.activity_category_standard_id = acs.id
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
ON ac.activity_category_standard_id = acs.id
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
CREATE TABLE public.settings (
    id SERIAL PRIMARY KEY NOT NULL,
    activity_category_standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    only_one_setting BOOLEAN NOT NULL DEFAULT true,
    CHECK(only_one_setting),
    UNIQUE(only_one_setting)
);


CREATE VIEW public.activity_category_available
WITH (security_invoker=on) AS
SELECT acs.code AS standard
     , ac.path
     , ac.label
     , ac.code
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs
ON ac.activity_category_standard_id = acs.id
WHERE acs.id = (SELECT activity_category_standard_id FROM public.settings)
ORDER BY path;


--
-- Name: activity_category_role; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.activity_category_role (
    id SERIAL PRIMARY KEY NOT NULL,
    role_id integer NOT NULL,
    activity_category_id integer NOT NULL,
    UNIQUE(role_id, activity_category_id)
);


--
-- Name: address; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.address (
    id integer NOT NULL,
    address_part1 character varying(200),
    address_part2 character varying(200),
    address_part3 character varying(200),
    region_id integer NOT NULL,
    latitude double precision,
    longitude double precision
);



--
-- Name: address_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.address ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: analysis_queue; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.analysis_queue (
    id integer NOT NULL,
    user_start_period timestamp with time zone NOT NULL,
    user_end_period timestamp with time zone NOT NULL,
    user_id integer NOT NULL,
    comment text,
    server_start_period timestamp with time zone,
    server_end_period timestamp with time zone
);



--
-- Name: analysis_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.analysis_queue ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.analysis_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: country; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.country (
    id integer NOT NULL,
    code_2 text UNIQUE NOT NULL,
    code_3 text UNIQUE NOT NULL,
    code_num text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(code_2, code_3, code_num, name)
);


--
-- Name: country_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.country ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: custom_analysis_check; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.custom_analysis_check (
    id integer NOT NULL,
    name character varying(64),
    query character varying(2048),
    target_unit_types character varying(16)
);



--
-- Name: custom_analysis_check_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.custom_analysis_check ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.custom_analysis_check_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_source; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TYPE public.data_source_priority AS ENUM ('trusted','ok','not_trusted');
CREATE TYPE public.allowed_operations AS ENUM ('create','alter','create_and_alter');
CREATE TYPE public.stat_unit_type AS ENUM ('local_unit','legal_unit','enterprise_unit','enterprise_group'
);
CREATE TYPE public.data_source_upload_type AS ENUM ('stat_units','activities');
CREATE TABLE public.data_source (
    id integer NOT NULL,
    name text NOT NULL,
    description text,
    user_id integer,
    priority public.data_source_priority NOT NULL,
    allowed_operations public.allowed_operations NOT NULL,
    attributes_to_check text,
    original_csv_attributes text,
    stat_unit_type public.stat_unit_type NOT NULL,
    restrictions text,
    variables_mapping text,
    csv_delimiter text,
    csv_skip_count integer NOT NULL,
    data_source_upload_type public.data_source_upload_type NOT NULL
);



--
-- Name: data_source_classification; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.data_source_classification (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: data_source_classification_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.data_source_classification ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.data_source_classification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_source_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.data_source ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.data_source_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_source_queue; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.data_source_queue (
    id integer NOT NULL,
    start_import_date timestamp with time zone,
    end_import_date timestamp with time zone,
    data_source_path text NOT NULL,
    data_source_file_name text NOT NULL,
    description text,
    status integer NOT NULL,
    note text,
    data_source_id integer NOT NULL,
    user_id integer,
    skip_lines_count integer NOT NULL
);



--
-- Name: data_source_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.data_source_queue ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.data_source_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_uploading_log; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.data_uploading_log (
    id integer NOT NULL,
    start_import_date timestamp with time zone,
    end_import_date timestamp with time zone,
    target_stat_ident text,
    stat_unit_name text,
    serialized_unit text,
    serialized_raw_unit text,
    data_source_queue_id integer NOT NULL,
    status integer NOT NULL,
    note text,
    errors text,
    summary text
);



--
-- Name: data_uploading_log_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.data_uploading_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.data_uploading_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE public.tag (
    id SERIAL PRIMARY KEY NOT NULL,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer REFERENCES public.tag(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name character varying(256) NOT NULL,
    description text,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    archived boolean NOT NULL DEFAULT false
);


--
-- Name: enterprise_group; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise_group (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident text,
    stat_ident_date timestamp with time zone,
    external_ident text,
    external_ident_type text,
    external_ident_date timestamp with time zone,
    active boolean NOT NULL DEFAULT true,
    short_name varchar(16),
    name varchar(256),
    data_source text,
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    address_id integer,
    enterprise_group_type_id integer,
    telephone_no text,
    email_address text,
    web_address text,
    contact_person text,
    notes text,
    edit_by_user_id integer NOT NULL,
    edit_comment text,
    unit_size_id integer,
    data_source_classification_id integer,
    reorg_references text,
    reorg_date timestamp with time zone,
    reorg_type_id integer,
    foreign_participation_id integer
);



--
-- Name: enterprise_group_role; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise_group_role (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: enterprise_group_role_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.enterprise_group_role ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.enterprise_group_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: enterprise_group_type; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise_group_type (
    id integer NOT NULL,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: enterprise_group_type_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.enterprise_group_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.enterprise_group_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: enterprise; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    parent_org_link integer,
    visiting_address_id integer,
    custom_visiting_address_id integer,
    postal_address_id integer,
    custom_postal_address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    notes text,
    sector_code_id integer,
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500),
    unit_size_id integer,
    foreign_participation_id integer,
    data_source_classification_id integer,
    enterprise_group_id integer,
    enterprise_group_date timestamp with time zone,
    enterprise_group_role_id integer
);




--
-- Name: foreign_participation; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.foreign_participation (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: foreign_participation_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.foreign_participation ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.foreign_participation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: legal_form; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.legal_form (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: legal_form_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.legal_form ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.legal_form_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: legal_unit; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.legal_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    tax_reg_ident character varying(50),
    tax_reg_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    birth_date date,
    death_date date,
    parent_org_link integer,
    data_source character varying(200),
    visiting_address_id integer,
    custom_visiting_address_id integer,
    postal_address_id integer,
    custom_postal_address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    free_econ_zone boolean,
    notes text,
    sector_code_id integer,
    legal_form_id integer,
    reorg_date timestamp with time zone,
    reorg_references integer,
    reorg_type_id integer,
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500) NOT NULL,
    unit_size_id integer,
    foreign_participation_id integer,
    data_source_classification_id integer,
    enterprise_id integer,
    seen_in_import_at timestamp with time zone DEFAULT statement_timestamp()
);

CREATE INDEX legal_unit_valid_to_idx ON public.legal_unit(tax_reg_ident) WHERE valid_to = 'infinity';
CREATE INDEX legal_unit_active_idx ON public.legal_unit(active);


--
-- Name: establishment; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.establishment (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    tax_reg_ident character varying(50),
    tax_reg_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    birth_date date,
    death_date date,
    parent_org_link integer,
    data_source character varying(200),
    visiting_address_id integer,
    custom_visiting_address_id integer,
    postal_address_id integer,
    custom_postal_address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    free_econ_zone boolean,
    notes text,
    sector_code_id integer,
    reorg_date timestamp with time zone,
    reorg_references integer,
    reorg_type_id integer,
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500) NOT NULL,
    unit_size_id integer,
    data_source_classification_id integer,
    enterprise_id integer,
    seen_in_import_at timestamp with time zone DEFAULT statement_timestamp()
);

CREATE INDEX establishment_valid_to_idx ON public.establishment(tax_reg_ident) WHERE valid_to = 'infinity';
CREATE INDEX establishment_active_idx ON public.establishment(active);

CREATE TYPE public.activity_type AS ENUM ('primary', 'secondary', 'ancilliary');

CREATE TABLE public.activity (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    activity_category_id integer NOT NULL,
    activity_type public.activity_type NOT NULL,
    updated_by_user_id integer NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    establishment_id integer NOT NULL REFERENCES public.establishment(id) ON DELETE CASCADE
);



CREATE TABLE public.tag_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    tag_id integer NOT NULL REFERENCES public.tag(id) ON DELETE CASCADE,
    establishment_id integer REFERENCES public.establishment(id) ON DELETE CASCADE,
    legal_unit_id integer REFERENCES public.legal_unit(id) ON DELETE CASCADE,
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer REFERENCES public.enterprise_group(id) ON DELETE CASCADE,
    CONSTRAINT "One and only one of establishment_id legal_unit_id enterprise_id or enterprise_group_id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);


--
-- Name: analysis_log; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.analysis_log (
    id integer NOT NULL,
    analysis_queue_id integer NOT NULL,
    establishment_id integer REFERENCES public.establishment(id) ON DELETE CASCADE,
    legal_unit_id integer REFERENCES public.legal_unit(id) ON DELETE CASCADE,
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer REFERENCES public.enterprise_group(id) ON DELETE CASCADE,
    issued_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    summary_messages text,
    error_values text,
    CONSTRAINT "One and only one of establishment_id legal_unit_id enterprise_id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);

--
-- Name: analysis_log_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.analysis_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.analysis_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: country_for_unit; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.country_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    country_id integer NOT NULL,
    establishment_id integer REFERENCES public.establishment(id) ON DELETE CASCADE,
    legal_unit_id integer REFERENCES public.legal_unit(id) ON DELETE CASCADE,
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer REFERENCES public.enterprise_group(id) ON DELETE CASCADE,
    CONSTRAINT "One and only one of establishment_id legal_unit_id enterprise_id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);


--
-- Name: person; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TYPE public.person_sex AS ENUM ('Male', 'Female');

CREATE TABLE public.person (
    id integer NOT NULL,
    personal_ident text UNIQUE,
    country_id integer,
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



--
-- Name: person_for_unit; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.person_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    person_id integer NOT NULL,
    person_type_id integer,
    establishment_id integer REFERENCES public.establishment(id) ON DELETE CASCADE,
    legal_unit_id integer REFERENCES public.legal_unit(id) ON DELETE CASCADE,
    CONSTRAINT "One and only one of establishment_id legal_unit_id  must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )

);



--
-- Name: person_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.person ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: person_type; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.person_type (
    id integer NOT NULL,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: person_type_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.person_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.person_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: postal_index; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.postal_index (
    id integer NOT NULL,
    name text,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
);



--
-- Name: postal_index_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.postal_index ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.postal_index_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: region; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.region (
    id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer REFERENCES public.region(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    CONSTRAINT "parent_id is required for child"
      CHECK(public.nlevel(path) = 1 OR parent_id IS NOT NULL)
);
CREATE INDEX ix_region_parent_id ON public.region USING btree (parent_id);


-- Create function for upsert operation on country
CREATE FUNCTION admin.upsert_region()
RETURNS TRIGGER AS $$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.region
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.region (path, parent_id, name, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, statement_timestamp())
    ON CONFLICT (path)
    DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        updated_at = statement_timestamp()
    WHERE region.id = EXCLUDED.id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create function for deleting stale countries
CREATE FUNCTION admin.delete_stale_region()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM public.region
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for region
CREATE VIEW public.region_view
WITH (security_invoker=on) AS
SELECT *
FROM public.region;

-- Create triggers for the view
CREATE TRIGGER upsert_region_view
INSTEAD OF INSERT ON public.region_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_region();

CREATE TRIGGER delete_stale_region_view
AFTER INSERT ON public.region_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_region();



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

--
-- Name: reorg_type; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.reorg_type (
    id integer NOT NULL,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: reorg_type_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.reorg_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reorg_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: report_tree; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.report_tree (
    id integer NOT NULL,
    title text,
    type text,
    report_id integer,
    parent_node_id integer,
    archived boolean NOT NULL DEFAULT false,
    resource_group text,
    report_url text
);



--
-- Name: report_tree_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.report_tree ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.report_tree_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sample_frame; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.sample_frame (
    id integer NOT NULL,
    name text NOT NULL,
    description text,
    predicate text NOT NULL,
    fields text NOT NULL,
    user_id integer,
    status integer NOT NULL,
    file_path text,
    generated_date_time timestamp with time zone,
    creation_date timestamp with time zone NOT NULL,
    editing_date timestamp with time zone
);



--
-- Name: sample_frame_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.sample_frame ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sample_frame_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sector_code; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.sector_code (
    id integer NOT NULL,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: sector_code_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.sector_code ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sector_code_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: unit_size; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.unit_size (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);



--
-- Name: unit_size_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.unit_size ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.unit_size_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


-- Create function for upsert operation on country
CREATE FUNCTION admin.upsert_country()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.country (code_2, code_3, code_num, name, active, custom, updated_at)
    VALUES (NEW.code_2, NEW.code_3, NEW.code_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (code_2, code_3, code_num, name)
    DO UPDATE SET
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp()
    WHERE country.id = EXCLUDED.id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create function for deleting stale countries
CREATE FUNCTION admin.delete_stale_country()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM public.country
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for country
CREATE VIEW public.country_view
WITH (security_invoker=on) AS
SELECT id, code_2, code_3, code_num, name, active, custom
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


\copy public.country_view(name, code_2, code_3, code_num) FROM 'dbseed/country/country_codes.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


-- Helpers to generate views for bach API handling of all the system provided configuration
-- that can also be overridden.
CREATE TYPE admin.view_type_enum AS ENUM ('system', 'custom');


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
                                ON CONFLICT (code) DO UPDATE SET
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


--
-- Name: region_role; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.region_role (
    id SERIAL PRIMARY KEY NOT NULL,
    role_id integer NOT NULL,
    region_id integer NOT NULL,
    UNIQUE(role_id, region_id)
);


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
CREATE TABLE public.stat_definition(
  id serial PRIMARY KEY,
  code varchar NOT NULL UNIQUE,
  stat_type public.stat_type NOT NULL,
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
INSERT INTO public.stat_definition(code, stat_type, frequency, name, description, priority) VALUES
  ('employees','int','yearly','Number of people employed','The number of people receiving an official salary with government reporting.',2),
  ('turnover','int','yearly','Turnover','The amount (EUR)',3);

CREATE TABLE public.stat_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    stat_definition_id integer NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    establishment_id integer NOT NULL REFERENCES public.establishment(id) ON DELETE CASCADE,
    value_int INTEGER,
    value_float FLOAT,
    value_str VARCHAR,
    value_bool BOOLEAN
);


CREATE OR REPLACE FUNCTION public.check_stat_for_unit_values()
RETURNS trigger AS $$
DECLARE
  new_stat_type public.stat_type;
BEGIN
  -- Fetch the stat_type for the current stat_definition_id
  SELECT stat_type INTO new_stat_type
  FROM public.stat_definition
  WHERE id = NEW.stat_definition_id;

  -- Use CASE statement to simplify the logic
  CASE new_stat_type
    WHEN 'int' THEN
      IF NEW.value_int IS NULL OR NEW.value_float IS NOT NULL OR NEW.value_str IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for stat_type %s', new_stat_type;
      END IF;
    WHEN 'float' THEN
      IF NEW.value_float IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_str IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for stat_type %s', new_stat_type;
      END IF;
    WHEN 'string' THEN
      IF NEW.value_str IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for stat_type %s', new_stat_type;
      END IF;
    WHEN 'bool' THEN
      IF NEW.value_bool IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_str IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for stat_type %s', new_stat_type;
      END IF;
    ELSE
      RAISE EXCEPTION 'Unknown stat_type: %', new_stat_type;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_stat_for_unit_values_trigger
BEFORE INSERT OR UPDATE ON public.stat_for_unit
FOR EACH ROW EXECUTE FUNCTION public.check_stat_for_unit_values();


CREATE OR REPLACE FUNCTION public.prevent_id_update()
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
        RAISE NOTICE '%s.%s: Preventing id changes', schema_name_str, table_name_str;
        EXECUTE format('CREATE TRIGGER trigger_prevent_'||table_name_str||'_id_update BEFORE UPDATE OF id ON '||schema_name_str||'.'||table_name_str||' FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();');
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.prevent_id_update_on_public_tables();
SET LOCAL client_min_messages TO INFO;

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
--     dyn_query := 'CREATE OR REPLACE VIEW legal_unit_history_with_stats AS SELECT id, unit_ident, name, change_description, valid_from, valid_to';
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


CREATE VIEW public.statistical_units
    (
    -- TODO: Generate SQL to provide these columns:
    establishment_id,
    legal_unit_id,
    enterprise_id,
    enterprise_group_id,
    name
    -- id integer NOT NULL,
    -- valid_from date NOT NULL,
    -- valid_to date NOT NULL,
    -- legal_form_id integer,
    -- sector_code_ids integer[],
    -- region_ids integer[],
    -- activity_category_ids integer[],
    -- unit_size_id integer,
    -- short_name character varying(200),
    -- tax_reg_ident character varying(50),
    -- external_ident character varying(50),
    -- external_ident_type character varying(50),
    -- data_source character varying(200),
    -- address_id integer,
    -- web_address character varying(200),
    -- telephone_no character varying(50),
    -- email_address character varying(50),
    -- free_econ_zone boolean NOT NULL,
    -- liq_date timestamp with time zone,
    -- liq_reason character varying(200),
    -- user_id character varying(100) NOT NULL,
    -- edit_comment character varying(500),
    -- data_source_classification_id integer,
    -- reorg_type_id integer,
    -- active boolean,
    )
    -- Ensure RLS as the connecting user.
    WITH (security_invoker=on)
    AS
    SELECT id AS establishment_id, NULL::INTEGER AS legal_unit_id, NULL::INTEGER AS enterprise_id, NULL::INTEGER AS enterprise_group_id, name FROM public.establishment
    UNION ALL
    SELECT NULL::INTEGER AS establishment_id, id AS legal_unit_id, NULL::INTEGER AS enterprise_id, NULL::INTEGER AS enterprise_group_id, name FROM public.legal_unit
    UNION ALL
    SELECT NULL::INTEGER AS establishment_id, NULL::INTEGER AS legal_unit_id, id AS enterprise_id, NULL::INTEGER AS enterprise_group_id, name FROM public.enterprise
    UNION ALL
    SELECT NULL::INTEGER AS establishment_id, NULL::INTEGER AS legal_unit_id, NULL::INTEGER AS enterprise_id, id AS enterprise_group_id, name FROM public.enterprise_group
;
--
-- Name: activity_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.activity_category_id_seq', 1, false);


--
-- Name: address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.address_id_seq', 1, false);


--
-- Name: analysis_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.analysis_log_id_seq', 1, false);


--
-- Name: analysis_queue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.analysis_queue_id_seq', 1, false);


--
-- Name: country_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.country_id_seq', 1, false);


--
-- Name: custom_analysis_check_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.custom_analysis_check_id_seq', 1, false);


--
-- Name: data_source_classification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.data_source_classification_id_seq', 1, false);


--
-- Name: data_source_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.data_source_id_seq', 1, false);


--
-- Name: data_source_queue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.data_source_queue_id_seq', 1, false);


--
-- Name: data_uploading_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.data_uploading_log_id_seq', 1, false);


--
-- Name: enterprise_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.enterprise_group_id_seq', 1, false);


--
-- Name: enterprise_group_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.enterprise_group_role_id_seq', 1, false);


--
-- Name: enterprise_group_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.enterprise_group_type_id_seq', 1, false);


--
-- Name: enterprise_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.enterprise_id_seq', 1, false);


--
-- Name: foreign_participation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.foreign_participation_id_seq', 1, false);


--
-- Name: legal_form_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.legal_form_id_seq', 1, false);


--
-- Name: legal_unit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.legal_unit_id_seq', 1, false);


--
-- Name: establishment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.establishment_id_seq', 1, false);


--
-- Name: person_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.person_id_seq', 1, false);


--
-- Name: person_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.person_type_id_seq', 1, false);


--
-- Name: postal_index_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.postal_index_id_seq', 1, false);


--
-- Name: reorg_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.reorg_type_id_seq', 1, false);


--
-- Name: report_tree_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.report_tree_id_seq', 1, false);


--
-- Name: sample_frame_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.sample_frame_id_seq', 1, false);


--
-- Name: sector_code_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.sector_code_id_seq', 1, false);


--
-- Name: unit_size_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.unit_size_id_seq', 1, false);


--
-- Name: address pk_address; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.address
    ADD CONSTRAINT pk_address PRIMARY KEY (id);


--
-- Name: analysis_log pk_analysis_log; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.analysis_log
    ADD CONSTRAINT pk_analysis_log PRIMARY KEY (id);


--
-- Name: analysis_queue pk_analysis_queue; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.analysis_queue
    ADD CONSTRAINT pk_analysis_queue PRIMARY KEY (id);


--
-- Name: country pk_country; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.country
    ADD CONSTRAINT pk_country PRIMARY KEY (id);


--
-- Name: custom_analysis_check pk_custom_analysis_check; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.custom_analysis_check
    ADD CONSTRAINT pk_custom_analysis_check PRIMARY KEY (id);


--
-- Name: data_source pk_data_source; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source
    ADD CONSTRAINT pk_data_source PRIMARY KEY (id);


--
-- Name: data_source_classification pk_data_source_classification; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source_classification
    ADD CONSTRAINT pk_data_source_classification PRIMARY KEY (id);


--
-- Name: data_source_queue pk_data_source_queue; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source_queue
    ADD CONSTRAINT pk_data_source_queue PRIMARY KEY (id);


--
-- Name: data_uploading_log pk_data_uploading_log; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_uploading_log
    ADD CONSTRAINT pk_data_uploading_log PRIMARY KEY (id);


--
-- Name: enterprise_group_role pk_enterprise_group_role; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group_role
    ADD CONSTRAINT pk_enterprise_group_role PRIMARY KEY (id);


--
-- Name: enterprise_group_type pk_enterprise_group_type; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group_type
    ADD CONSTRAINT pk_enterprise_group_type PRIMARY KEY (id);


--
-- Name: foreign_participation pk_foreign_participation; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.foreign_participation
    ADD CONSTRAINT pk_foreign_participation PRIMARY KEY (id);


--
-- Name: legal_form pk_legal_form; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_form
    ADD CONSTRAINT pk_legal_form PRIMARY KEY (id);


--
-- Name: person pk_person; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT pk_person PRIMARY KEY (id);


--
-- Name: person_type pk_person_type; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_type
    ADD CONSTRAINT pk_person_type PRIMARY KEY (id);


--
-- Name: postal_index pk_postal_index; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.postal_index
    ADD CONSTRAINT pk_postal_index PRIMARY KEY (id);


--
-- Name: reorg_type pk_reorg_type; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.reorg_type
    ADD CONSTRAINT pk_reorg_type PRIMARY KEY (id);


--
-- Name: report_tree pk_report_tree; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.report_tree
    ADD CONSTRAINT pk_report_tree PRIMARY KEY (id);


--
-- Name: sample_frame pk_sample_frame; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.sample_frame
    ADD CONSTRAINT pk_sample_frame PRIMARY KEY (id);


--
-- Name: sector_code pk_sector_code; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.sector_code
    ADD CONSTRAINT pk_sector_code PRIMARY KEY (id);


--
-- Name: unit_size pk_unit_size; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.unit_size
    ADD CONSTRAINT pk_unit_size PRIMARY KEY (id);


--
-- Name: ix_activity_activity_category_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_activity_category_id ON public.activity USING btree (activity_category_id);


--
-- Name: ix_activity_category_parent_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_category_parent_id ON public.activity_category USING btree (parent_id);


--
-- Name: ix_activity_category_role_activity_category_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_category_role_activity_category_id ON public.activity_category_role USING btree (activity_category_id);
CREATE INDEX ix_activity_category_role_role_id ON public.activity_category_role USING btree (role_id);


--
-- Name: ix_activity_establishment_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_establishment_id ON public.activity USING btree (establishment_id);


--
-- Name: ix_activity_updated_by; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_updated_by_user_id ON public.activity USING btree (updated_by_user_id);


--
-- Name: ix_address_address_part1_address_part2_address_part3_region_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_address_address_part1_address_part2_address_part3_region_id ON public.address USING btree (address_part1, address_part2, address_part3, region_id, latitude, longitude);


--
-- Name: ix_address_region_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_address_region_id ON public.address USING btree (region_id);


--
-- Name: ix_analysis_log_analysis_queue_id_analyzed_unit_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_analysis_log_analysis_queue_id_analyzed_queue_id ON public.analysis_log USING btree (analysis_queue_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_establishment_id ON public.analysis_log USING btree (establishment_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_legal_unit_id ON public.analysis_log USING btree (legal_unit_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_id ON public.analysis_log USING btree (enterprise_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_group_id ON public.analysis_log USING btree (enterprise_group_id);


--
-- Name: ix_analysis_queue_user_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_analysis_queue_user_id ON public.analysis_queue USING btree (user_id);



--
-- Name: ix_country_for_unit_country_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_country_for_unit_country_id ON public.country_for_unit USING btree (country_id);


--
-- Name: ix_country_for_unit_enterprise_group_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_country_for_unit_enterprise_group_id ON public.country_for_unit USING btree (enterprise_group_id);


--
-- Name: ix_country_for_unit_legal_unit_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_country_for_unit_legal_unit_id ON public.country_for_unit USING btree (legal_unit_id);


--
-- Name: ix_country_for_unit_establishment_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_country_for_unit_establishment_id ON public.country_for_unit USING btree (establishment_id);


--
-- Name: ix_data_source_classification_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_data_source_classification_code ON public.data_source_classification USING btree (code);


--
-- Name: ix_data_source_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_data_source_name ON public.data_source USING btree (name);


--
-- Name: ix_data_source_queue_data_source_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_data_source_queue_data_source_id ON public.data_source_queue USING btree (data_source_id);


--
-- Name: ix_data_source_queue_user_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_data_source_queue_user_id ON public.data_source_queue USING btree (user_id);


--
-- Name: ix_data_source_user_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_data_source_user_id ON public.data_source USING btree (user_id);


--
-- Name: ix_data_uploading_log_data_source_queue_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_data_uploading_log_data_source_queue_id ON public.data_uploading_log USING btree (data_source_queue_id);


--
-- Name: ix_enterprise_group_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_address_id ON public.enterprise_group USING btree (address_id);


--
-- Name: ix_enterprise_group_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_data_source_classification_id ON public.enterprise_group USING btree (data_source_classification_id);


--
-- Name: ix_enterprise_group_enterprise_group_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_enterprise_group_type_id ON public.enterprise_group USING btree (enterprise_group_type_id);


--
-- Name: ix_enterprise_group_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_foreign_participation_id ON public.enterprise_group USING btree (foreign_participation_id);


--
-- Name: ix_enterprise_group_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_name ON public.enterprise_group USING btree (name);


--
-- Name: ix_enterprise_group_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_reorg_type_id ON public.enterprise_group USING btree (reorg_type_id);


--
-- Name: ix_enterprise_group_role_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_enterprise_group_role_code ON public.enterprise_group_role USING btree (code);


--
-- Name: ix_enterprise_group_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_size_id ON public.enterprise_group USING btree (unit_size_id);


CREATE INDEX ix_enterprise_custom_postal_address_id ON public.enterprise USING btree (custom_postal_address_id);
CREATE INDEX ix_enterprise_custom_visiting_address_id ON public.enterprise USING btree (custom_visiting_address_id);
CREATE INDEX ix_enterprise_postal_address_id ON public.enterprise USING btree (postal_address_id);
CREATE INDEX ix_enterprise_visiting_address_id ON public.enterprise USING btree (visiting_address_id);


--
-- Name: ix_enterprise_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_data_source_classification_id ON public.enterprise USING btree (data_source_classification_id);


--
-- Name: ix_enterprise_ent_group_role_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_enterprise_group_role_id ON public.enterprise USING btree (enterprise_group_role_id);


--
-- Name: ix_enterprise_enterprise_group_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_enterprise_group_id ON public.enterprise USING btree (enterprise_group_id);


--
-- Name: ix_enterprise_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_foreign_participation_id ON public.enterprise USING btree (foreign_participation_id);


--
-- Name: ix_enterprise_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_sector_code_id ON public.enterprise USING btree (sector_code_id);


--
-- Name: ix_enterprise_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_name ON public.enterprise USING btree (name);


--
-- Name: ix_enterprise_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_short_name_stat_ident ON public.enterprise USING btree (short_name, stat_ident);


--
-- Name: ix_enterprise_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_size_id ON public.enterprise USING btree (unit_size_id);


--
-- Name: ix_enterprise_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_stat_ident ON public.enterprise USING btree (stat_ident);


--
-- Name: ix_foreign_participation_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_foreign_participation_code ON public.foreign_participation USING btree (code);


--
-- Name: ix_legal_form_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_legal_form_code ON public.legal_form USING btree (code);


--
-- Name: ix_legal_unit_actual_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_visiting_address_id ON public.legal_unit USING btree (visiting_address_id);


--
-- Name: ix_legal_unit_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_custom_visiting_address_id ON public.legal_unit USING btree (custom_visiting_address_id);


--
-- Name: ix_legal_unit_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_data_source_classification_id ON public.legal_unit USING btree (data_source_classification_id);


--
-- Name: ix_legal_unit_enterprise_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_enterprise_id ON public.legal_unit USING btree (enterprise_id);


--
-- Name: ix_legal_unit_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_foreign_participation_id ON public.legal_unit USING btree (foreign_participation_id);


--
-- Name: ix_legal_unit_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_sector_code_id ON public.legal_unit USING btree (sector_code_id);


--
-- Name: ix_legal_unit_legal_form_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_legal_form_id ON public.legal_unit USING btree (legal_form_id);


--
-- Name: ix_legal_unit_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_name ON public.legal_unit USING btree (name);


--
-- Name: ix_legal_unit_postal_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_postal_address_id ON public.legal_unit USING btree (postal_address_id);


--
-- Name: ix_legal_unit_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_reorg_type_id ON public.legal_unit USING btree (reorg_type_id);


--
-- Name: ix_legal_unit_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_short_name_reg_ident_stat_ident_tax ON public.legal_unit USING btree (short_name, stat_ident, tax_reg_ident);


--
-- Name: ix_legal_unit_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (unit_size_id);


--
-- Name: ix_legal_unit_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_stat_ident ON public.legal_unit USING btree (stat_ident);


--
-- Name: ix_establishment_actual_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_visiting_address_id ON public.establishment USING btree (visiting_address_id);


--
-- Name: ix_establishment_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_custom_visiting_address_id ON public.establishment USING btree (custom_visiting_address_id);


--
-- Name: ix_establishment_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_data_source_classification_id ON public.establishment USING btree (data_source_classification_id);


--
-- Name: ix_establishment_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_sector_code_id ON public.establishment USING btree (sector_code_id);


--
-- Name: ix_establishment_enterprise_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_enterprise_id ON public.establishment USING btree (enterprise_id);


--
-- Name: ix_establishment_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_name ON public.establishment USING btree (name);


--
-- Name: ix_establishment_postal_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_postal_address_id ON public.establishment USING btree (postal_address_id);


--
-- Name: ix_establishment_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_reorg_type_id ON public.establishment USING btree (reorg_type_id);


--
-- Name: ix_establishment_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_short_name_reg_ident_stat_ident_tax ON public.establishment USING btree (short_name, stat_ident, tax_reg_ident);


--
-- Name: ix_establishment_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_size_id ON public.establishment USING btree (unit_size_id);


--
-- Name: ix_establishment_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_stat_ident ON public.establishment USING btree (stat_ident);


--
-- Name: ix_person_country_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_country_id ON public.person USING btree (country_id);


--
-- Name: ix_person_for_unit_legal_unit_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_for_unit_legal_unit_id ON public.person_for_unit USING btree (legal_unit_id);


--
-- Name: ix_person_for_unit_establishment_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_for_unit_establishment_id ON public.person_for_unit USING btree (establishment_id);


--
-- Name: ix_person_for_unit_person_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_for_unit_person_id ON public.person_for_unit USING btree (person_id);


--
-- Name: ix_person_for_unit_person_type_id_establishment_id_legal_unit_id_; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_person_for_unit_person_type_id_establishment_id_legal_unit_id_ ON public.person_for_unit USING btree (person_type_id, establishment_id, legal_unit_id, person_id);


--
-- Name: ix_person_given_name_surname; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_given_name_surname ON public.person USING btree (given_name, middle_name, family_name);


--
-- Name: ix_sample_frame_user_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_sample_frame_user_id ON public.sample_frame USING btree (user_id);


--
-- Name: ix_sector_code_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_sector_code_code ON public.sector_code USING btree (code);


--
-- Name: ix_sector_code_parent_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_sector_code_parent_id ON public.sector_code USING btree (parent_id);


--
-- Name: ix_unit_size_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_unit_size_code ON public.unit_size USING btree (code);


--
-- Name: ix_region_role; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_region_role ON public.region_role USING btree (region_id);


--
-- Name: activity fk_activity_activity_category_activity_category_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT fk_activity_activity_category_activity_category_id FOREIGN KEY (activity_category_id) REFERENCES public.activity_category(id) ON DELETE CASCADE;


--
-- Name: activity_category fk_activity_category_activity_category_parent_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_category
    ADD CONSTRAINT fk_activity_category_activity_category_parent_id FOREIGN KEY (parent_id) REFERENCES public.activity_category(id);


--
-- Name: activity_category_role fk_activity_category_role_activity_category_activity_category_; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_category_role
    ADD CONSTRAINT fk_activity_category_role_activity_category_activity_category_ FOREIGN KEY (activity_category_id) REFERENCES public.activity_category(id) ON DELETE CASCADE;


--
-- Name: activity_category_role fk_activity_category_role_user_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_category_role
    ADD CONSTRAINT fk_activity_category_role_role_role_id FOREIGN KEY (role_id) REFERENCES public.statbus_role(id) ON DELETE CASCADE;


--
-- Name: activity fk_activity_user_updated_by_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT fk_activity_user_updated_by_user_id_user_id FOREIGN KEY (updated_by_user_id) REFERENCES public.statbus_user(id) ON DELETE CASCADE;


--
-- Name: address fk_address_region_region_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.address
    ADD CONSTRAINT fk_address_region_region_id FOREIGN KEY (region_id) REFERENCES public.region(id) ON DELETE CASCADE;


--
-- Name: analysis_log fk_analysis_log_analysis_queue_analysis_queue_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.analysis_log
    ADD CONSTRAINT fk_analysis_log_analysis_queue_analysis_queue_id FOREIGN KEY (analysis_queue_id) REFERENCES public.analysis_queue(id) ON DELETE CASCADE;


--
-- Name: analysis_queue fk_analysis_queue_user_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.analysis_queue
    ADD CONSTRAINT fk_analysis_queue_user_user_id FOREIGN KEY (user_id) REFERENCES public.statbus_user(id) ON DELETE CASCADE;


--
-- Name: country_for_unit fk_country_for_unit_country_country_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.country_for_unit
    ADD CONSTRAINT fk_country_for_unit_country_country_id FOREIGN KEY (country_id) REFERENCES public.country(id) ON DELETE CASCADE;


--
-- Name: data_source_queue fk_data_source_queue_data_source_data_source_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source_queue
    ADD CONSTRAINT fk_data_source_queue_data_source_data_source_id FOREIGN KEY (data_source_id) REFERENCES public.data_source(id) ON DELETE CASCADE;


--
-- Name: data_source_queue fk_data_source_queue_user_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source_queue
    ADD CONSTRAINT fk_data_source_queue_user_user_id FOREIGN KEY (user_id) REFERENCES public.statbus_user(id);


--
-- Name: data_source fk_data_source_user_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_source
    ADD CONSTRAINT fk_data_source_user_user_id FOREIGN KEY (user_id) REFERENCES public.statbus_user(id);


--
-- Name: data_uploading_log fk_data_uploading_log_data_source_queue_data_source_queue_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.data_uploading_log
    ADD CONSTRAINT fk_data_uploading_log_data_source_queue_data_source_queue_id FOREIGN KEY (data_source_queue_id) REFERENCES public.data_source_queue(id) ON DELETE CASCADE;


--
-- Name: enterprise_group fk_enterprise_group_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_address_address_id FOREIGN KEY (address_id) REFERENCES public.address(id);


--
-- Name: enterprise_group fk_enterprise_group_data_source_classification_data_source_cla; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_data_source_classification_data_source_cla FOREIGN KEY (data_source_classification_id) REFERENCES public.data_source_classification(id);


--
-- Name: enterprise_group fk_enterprise_group_enterprise_group_type_enterprise_group_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_enterprise_group_type_enterprise_group_type_id FOREIGN KEY (enterprise_group_type_id) REFERENCES public.enterprise_group_type(id);


--
-- Name: enterprise_group fk_enterprise_group_foreign_participation_foreign_participatio; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_foreign_participation_foreign_participatio FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: enterprise_group fk_enterprise_group_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: enterprise_group fk_enterprise_group_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_unit_size_size_id FOREIGN KEY (unit_size_id) REFERENCES public.unit_size(id);


--
-- Name: enterprise fk_enterprise_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_address_visiting_address_id FOREIGN KEY (visiting_address_id) REFERENCES public.address(id);


--
-- Name: enterprise fk_enterprise_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_address_custom_visiting_address_id FOREIGN KEY (custom_visiting_address_id) REFERENCES public.address(id);


--
-- Name: enterprise fk_enterprise_address_postal_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_address_postal_address_id FOREIGN KEY (postal_address_id) REFERENCES public.address(id);


--
-- Name: enterprise fk_enterprise_data_source_classification_data_source_clas; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_data_source_classification_data_source_clas FOREIGN KEY (data_source_classification_id) REFERENCES public.data_source_classification(id);


--
-- Name: enterprise fk_enterprise_enterprise_group_enterprise_group_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_enterprise_group_enterprise_group_id FOREIGN KEY (enterprise_group_id) REFERENCES public.enterprise_group(id);


--
-- Name: enterprise fk_enterprise_enterprise_group_role_ent_group_role_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_enterprise_group_role_enterprise_group_role_id FOREIGN KEY (enterprise_group_role_id) REFERENCES public.enterprise_group_role(id);


--
-- Name: enterprise fk_enterprise_foreign_participation_foreign_participation; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_foreign_participation_foreign_participation FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: enterprise fk_enterprise_sector_code_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_sector_code_sector_code_id FOREIGN KEY (sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: enterprise fk_enterprise_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_unit_size_size_id FOREIGN KEY (unit_size_id) REFERENCES public.unit_size(id);


--
-- Name: legal_unit fk_legal_unit_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_address_visiting_address_id FOREIGN KEY (visiting_address_id) REFERENCES public.address(id);


--
-- Name: legal_unit fk_legal_unit_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_address_custom_visiting_address_id FOREIGN KEY (custom_visiting_address_id) REFERENCES public.address(id);


--
-- Name: legal_unit fk_legal_unit_address_postal_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_address_postal_address_id FOREIGN KEY (postal_address_id) REFERENCES public.address(id);


--
-- Name: legal_unit fk_legal_unit_data_source_classification_data_source_classific; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_data_source_classification_data_source_classific FOREIGN KEY (data_source_classification_id) REFERENCES public.data_source_classification(id);


--
-- Name: legal_unit fk_legal_unit_enterprise_enterprise_temp_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_enterprise_enterprise_temp_id FOREIGN KEY (enterprise_id) REFERENCES public.enterprise(id);


--
-- Name: legal_unit fk_legal_unit_foreign_participation_foreign_participation_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_foreign_participation_foreign_participation_id FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: legal_unit fk_legal_unit_legal_form_legal_form_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_legal_form_legal_form_id FOREIGN KEY (legal_form_id) REFERENCES public.legal_form(id);


--
-- Name: legal_unit fk_legal_unit_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: legal_unit fk_legal_unit_sector_code_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_sector_code_sector_code_id FOREIGN KEY (sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: legal_unit fk_legal_unit_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_unit_size_size_id FOREIGN KEY (unit_size_id) REFERENCES public.unit_size(id);


--
-- Name: establishment fk_establishment_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_address_visiting_address_id FOREIGN KEY (visiting_address_id) REFERENCES public.address(id);


--
-- Name: establishment fk_establishment_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_address_custom_visiting_address_id FOREIGN KEY (custom_visiting_address_id) REFERENCES public.address(id);


--
-- Name: establishment fk_establishment_address_postal_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_address_postal_address_id FOREIGN KEY (postal_address_id) REFERENCES public.address(id);


--
-- Name: establishment fk_establishment_data_source_classification_data_source_classific; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_data_source_classification_data_source_classific FOREIGN KEY (data_source_classification_id) REFERENCES public.data_source_classification(id);


--
-- Name: establishment fk_establishment_legal_unit_legal_unit_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_legal_unit_legal_unit_id FOREIGN KEY (enterprise_id) REFERENCES public.enterprise(id);


--
-- Name: establishment fk_establishment_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: establishment fk_establishment_sector_code_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_sector_code_sector_code_id FOREIGN KEY (sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: establishment fk_establishment_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_unit_size_size_id FOREIGN KEY (unit_size_id) REFERENCES public.unit_size(id);


--
-- Name: person fk_person_country_country_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT fk_person_country_country_id FOREIGN KEY (country_id) REFERENCES public.country(id);


--
-- Name: person_for_unit fk_person_for_unit_legal_unit_legal_unit_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_legal_unit_legal_unit_id FOREIGN KEY (legal_unit_id) REFERENCES public.legal_unit(id) ON DELETE CASCADE;


--
-- Name: person_for_unit fk_person_for_unit_establishment_establishment_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_establishment_establishment_id FOREIGN KEY (establishment_id) REFERENCES public.establishment(id) ON DELETE CASCADE;


--
-- Name: person_for_unit fk_person_for_unit_person_person_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_person_person_id FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: person_for_unit fk_person_for_unit_person_type_person_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_person_type_person_type_id FOREIGN KEY (person_type_id) REFERENCES public.person_type(id);


--
-- Name: region fk_region_region_parent_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.region
    ADD CONSTRAINT fk_region_region_parent_id FOREIGN KEY (parent_id) REFERENCES public.region(id);


--
-- Name: sample_frame fk_sample_frame_user_user_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.sample_frame
    ADD CONSTRAINT fk_sample_frame_user_user_id FOREIGN KEY (user_id) REFERENCES public.statbus_user(id);


--
-- Name: sector_code fk_sector_code_sector_code_parent_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.sector_code
    ADD CONSTRAINT fk_sector_code_sector_code_parent_id FOREIGN KEY (parent_id) REFERENCES public.sector_code(id);


--
-- Name: region_role fk_region_role; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.region_role
    ADD CONSTRAINT fk_region_role_region_id FOREIGN KEY (region_id) REFERENCES public.region(id) ON DELETE CASCADE;


--
-- Name: region_role fk_region_role; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.region_role
    ADD CONSTRAINT fk_region_role_role_id FOREIGN KEY (role_id) REFERENCES public.statbus_role(id) ON DELETE CASCADE;


--
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

CREATE TABLE public.custom_view_def(
    id serial PRIMARY KEY,
    target_table_id int REFERENCES public.custom_view_def_target_table(id),
    slug text UNIQUE NOT NULL,
    name text NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
CREATE TABLE public.custom_view_def_source_column(
    id serial PRIMARY KEY,
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    column_name text NOT NULL,
    priority int NOT NULL, -- The ordering of the columns in the CSV file.
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
CREATE TABLE public.custom_view_def_mapping(
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    source_column_id int REFERENCES public.custom_view_def_source_column(id),
    target_column_id int REFERENCES public.custom_view_def_target_column(id),
    CONSTRAINT unique_source_column_mapping UNIQUE (custom_view_def_id, source_column_id),
    CONSTRAINT unique_target_column_mapping UNIQUE (custom_view_def_id, target_column_id),
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);


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
    --    CREATE VIEW public.legal_unit_custom_view
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
        --   , statement_timestamp() AS tax_reg_date
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
        ', ''Batch upload'' AS edit_comment' ||
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
        --   tax_reg_date = upsert_data.tax_reg_date
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
            --   , tax_reg_date
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
            --  , upsert_data.tax_reg_date
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
            WHERE column_name = 'tax_reg_ident'
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


-- Load seed data after all constraints are in place
SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.sector_code', 'path');
SET LOCAL client_min_messages TO INFO;

\copy public.sector_code_system(path, name) FROM 'dbseed/sector_code.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


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
SELECT admin.generate_table_views_for_batch_api('public.data_source_classification', 'code');
SET LOCAL client_min_messages TO INFO;

\copy public.data_source_classification_system(code, name) FROM 'dbseed/data_source_classification.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


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


-- View for current information about a legal unit, support update and delete.
CREATE VIEW public.legal_unit_current
WITH (security_invoker=on) AS
SELECT *
FROM public.legal_unit
WHERE valid_from >= statement_timestamp()
  AND statement_timestamp() <= valid_to
  AND active
  ;

--CREATE FUNCTION admin.upsert_legal_unit_current()
--RETURNS TRIGGER AS $$
--BEGIN
--    WITH parent AS (
--        SELECT id
--        FROM public.region
--        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
--    )
--    INSERT INTO public.region (path, parent_id, name, active, updated_at)
--    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, true, statement_timestamp())
--    ON CONFLICT (path)
--    DO UPDATE SET
--        parent_id = (SELECT id FROM parent),
--        name = EXCLUDED.name,
--        updated_at = statement_timestamp()
--    WHERE region.id = EXCLUDED.id;
--    RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;
--
---- Create function for deleting stale countries
--CREATE FUNCTION admin.delete_stale_legal_unit_current()
--RETURNS TRIGGER AS $$
--BEGIN
--    DELETE FROM public.region
--    WHERE updated_at < statement_timestamp() AND active = false;
--    RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;
--
---- Create triggers for the view
--CREATE TRIGGER upsert_legal_unit_current
--INSTEAD OF INSERT ON public.legal_unit_current
--FOR EACH ROW
--EXECUTE FUNCTION admin.upsert_legal_unit_current();
--
--CREATE TRIGGER delete_stale_legal_unit_current
--AFTER INSERT ON public.legal_unit_current
--FOR EACH STATEMENT
--EXECUTE FUNCTION admin.delete_stale_legal_unit_current();


-- View for insert of Norwegian Legal Unit (Hovedenhet)
CREATE VIEW public.legal_unit_custom_view
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

CREATE FUNCTION admin.upsert_legal_unit_custom_view()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        LIMIT 1
        --WHERE uuid = auth.uid()
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_reg_ident
        , statement_timestamp() AS tax_reg_date
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
        , 'Batch upload' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.legal_unit
        SET tax_reg_date = upsert_data.tax_reg_date
          , valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , seen_in_import_at = upsert_data.seen_in_import_at
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE legal_unit.tax_reg_ident = upsert_data.tax_reg_ident
          AND legal_unit.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, legal_unit.id
    ),
    insert_outcome AS (
        INSERT INTO public.legal_unit
          ( tax_reg_ident
          , tax_reg_date
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
            upsert_data.tax_reg_ident
          , upsert_data.tax_reg_date
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

CREATE FUNCTION admin.delete_stale_legal_unit_custom_view()
RETURNS TRIGGER AS $$
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        LIMIT 1
        --WHERE uuid = auth.uid()
    )
    UPDATE public.legal_unit
    SET valid_to = statement_timestamp()
      , edit_comment = 'Absent from upload'
      , edit_by_user_id = (SELECT id FROM su)
      , active = false
    WHERE seen_in_import_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for the view
CREATE TRIGGER upsert_legal_unit_custom_view
INSTEAD OF INSERT ON public.legal_unit_custom_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_legal_unit_custom_view();

CREATE TRIGGER delete_stale_legal_unit_custom_view
AFTER INSERT ON public.legal_unit_custom_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_legal_unit_custom_view();


-- time psql <<EOS
-- \copy public.legal_unit_custom_view FROM 'tmp/enheter.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
-- EOS



-- View for insert of Norwegian Legal Unit (Underenhet)
CREATE VIEW public.establishment_custom_view
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

-- Create function for upsert operation on country
CREATE FUNCTION admin.upsert_establishment_custom_view()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        LIMIT 1
        --WHERE uuid = auth.uid()
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_reg_ident
        , statement_timestamp() AS tax_reg_date
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
        , 'Batch upload' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.establishment
        SET tax_reg_date = upsert_data.tax_reg_date
          , valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , seen_in_import_at = upsert_data.seen_in_import_at
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE establishment.tax_reg_ident = upsert_data.tax_reg_ident
          AND establishment.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, establishment.id
    ),
    insert_outcome AS (
        INSERT INTO public.establishment
          ( tax_reg_ident
          , tax_reg_date
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
            upsert_data.tax_reg_ident
          , upsert_data.tax_reg_date
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
CREATE FUNCTION admin.delete_stale_establishment_custom_view()
RETURNS TRIGGER AS $$
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        LIMIT 1
        --WHERE uuid = auth.uid()
    )
    UPDATE public.establishment
    SET valid_to = statement_timestamp()
      , edit_comment = 'Absent from upload'
      , edit_by_user_id = (SELECT id FROM su)
      , active = false
    WHERE seen_in_import_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for the view
CREATE TRIGGER upsert_establishment_custom_view
INSTEAD OF INSERT ON public.establishment_custom_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_establishment_custom_view();

CREATE TRIGGER delete_stale_establishment_custom_view
AFTER INSERT ON public.establishment_custom_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_establishment_custom_view();

-- time psql <<EOS
-- \copy public.establishment_custom_view FROM 'tmp/underenheter.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
-- EOS

-- Add security.

CREATE OR REPLACE FUNCTION auth.has_statbus_role (user_uuid UUID, role_type public.statbus_role_type)
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
    WHERE ((su.uuid = $1) AND (sr.role_type = $2))
  );
$$;

-- Add security functions
CREATE OR REPLACE FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, role_types public.statbus_role_type[])
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
    WHERE ((su.uuid = $1) AND (sr.role_type = ANY ($2)))
  );
$$;


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
    -- _custom view is used for managing custom rows.
    -- For changes to these, one can directly modify them with the service
    -- account that bypasses RLS through the Supabase UI.
    IF NOT has_custom_and_active THEN
        RAISE NOTICE '%s.%s: super_user(s) can manage', schema_name_str, table_name_str;
        EXECUTE format('CREATE POLICY %s_super_user_manage ON %I.%I FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
    END IF;
END;
$$ LANGUAGE plpgsql;



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

-- The employees can only update the tables designated by their assigned region or activity_category
CREATE POLICY activity_employee_manage ON public.activity FOR ALL TO authenticated
USING (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), activity_category_id)
      )
WITH CHECK (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), activity_category_id)
      );

--CREATE POLICY "premium and admin view access" ON premium_records FOR ALL TO authenticated USING (has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[]));


-- Activate era handling
SELECT sql_saga.add_era('public.enterprise_group', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['id']);

SELECT sql_saga.add_era('public.enterprise', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise', ARRAY['id']);
SELECT sql_saga.add_foreign_key('public.enterprise', ARRAY['enterprise_group_id'], 'valid', 'enterprise_group_id_valid');

SELECT sql_saga.add_era('public.legal_unit', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['tax_reg_ident']);

SELECT sql_saga.add_era('public.establishment', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['tax_reg_ident']);

TABLE sql_saga.era;
TABLE sql_saga.unique_keys;
TABLE sql_saga.foreign_keys;


NOTIFY pgrst, 'reload config';

END;
