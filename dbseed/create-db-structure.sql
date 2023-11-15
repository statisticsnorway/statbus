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
-- There can only ever by one administrator role.
CREATE UNIQUE INDEX statbus_role_role_type ON public.statbus_role(role_type) WHERE role_type = 'super_user';

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
BEGIN
  INSERT INTO public.statbus_user (uuid) VALUES (new.id);
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


CREATE OR REPLACE FUNCTION auth.has_statbus_role (user_uuid UUID, role_type public.statbus_role_type)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT users.id
    FROM statbus_user
    WHERE ((statbus_user.uuid = $1)
      AND ($2 = statbus_user.role_type)))
$$;


CREATE OR REPLACE FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, role_types public.statbus_role_type[])
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT statbus_user.id
    FROM statbus_user
    WHERE (statbus_user.uuid = $1)
      AND ($2 = ANY (statbus_user.role_type))
  )
$$;


CREATE OR REPLACE FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
    SELECT EXISTS(
        SELECT public.statbus_user.id
        FROM public.statbus_user AS u
        INNER JOIN public.activity_category_role AS acr ON acr.role_id = u.role_id
        WHERE u.uuid = $1
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
        SELECT public.statbus_user.id
        FROM public.statbus_user AS u
        INNER JOIN public.region_role ON region_role.role_id = u.role_id
        WHERE u.uuid = $1
          AND acr.region_id  = $2
   )
$$;


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


--
-- Name: activity; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.activity (
    id integer NOT NULL,
    id_date timestamp with time zone NOT NULL,
    activity_category_id integer NOT NULL,
    activity_year integer,
    activity_type integer NOT NULL,
    employees integer,
    turnover numeric(18,2),
    updated_by_user_id integer NOT NULL,
    updated_date timestamp with time zone NOT NULL
);



--
-- Name: activity_category; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.activity_category (
    id integer NOT NULL,
    section character varying(10) NOT NULL,
    parent_id integer,
    dic_parent_id integer,
    version_id integer NOT NULL,
    activity_category_level integer,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code character varying(10) NOT NULL
);



--
-- Name: activity_category_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.activity_category ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.activity_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
-- Name: activity_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.activity ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.activity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
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
    iso_code text,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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

CREATE TABLE public.data_source (
    id integer NOT NULL,
    name text NOT NULL,
    description text,
    user_id integer,
    priority integer NOT NULL,
    allowed_operations integer NOT NULL,
    attributes_to_check text,
    original_csv_attributes text,
    stat_unit_type integer NOT NULL,
    restrictions text,
    variables_mapping text,
    csv_delimiter text,
    csv_skip_count integer NOT NULL,
    data_source_upload_type integer NOT NULL
);



--
-- Name: data_source_classification; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.data_source_classification (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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


--
-- Name: dictionary_version; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.dictionary_version (
    id integer NOT NULL,
    version_id integer NOT NULL,
    version_name text
);



--
-- Name: dictionary_version_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.dictionary_version ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dictionary_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: enterprise_group; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise_group (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    reg_ident integer UNIQUE NOT NULL,
    reg_ident_date timestamp with time zone NOT NULL default now(),
    stat_ident text,
    stat_ident_date timestamp with time zone,
    name character varying(400),
    short_name text,
    registration_date timestamp with time zone NOT NULL,
    registration_reason_id integer,
    tax_reg_ident text,
    tax_reg_date timestamp with time zone,
    external_ident text,
    external_ident_type text,
    external_ident_date timestamp with time zone,
    data_source text,
    archived boolean NOT NULL DEFAULT false,
    address_id integer,
    actual_address_id integer,
    postal_address_id integer,
    ent_group_type_id integer,
    num_of_people_emp integer,
    telephone_no text,
    email_address text,
    web_address text,
    liq_date_start timestamp with time zone,
    liq_date_end timestamp with time zone,
    reorg_type_code text,
    reorg_references text,
    contact_person text,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    liq_reason text,
    suspension_start text,
    suspension_end text,
    employees integer,
    employees_year integer,
    employees_date timestamp with time zone,
    turnover numeric(18,2),
    turnover_year integer,
    turnover_date timestamp with time zone,
    status_date timestamp with time zone NOT NULL,
    notes text,
    user_id integer NOT NULL,
    change_reason integer DEFAULT 0 NOT NULL,
    edit_comment text,
    size_id integer,
    data_source_classification_id integer,
    reorg_type_id integer,
    reorg_date timestamp with time zone,
    unit_status_id integer,
    foreign_participation_id integer
);



--
-- Name: enterprise_group_role; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.enterprise_group_role (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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
    reg_ident integer NOT NULL,
    reg_ident_date timestamp with time zone NOT NULL,
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    name character varying(400),
    short_name character varying(200),
    parent_org_link integer,
    tax_reg_ident character varying(50),
    tax_reg_date timestamp with time zone,
    registration_reason_id integer,
    registration_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    data_source character varying(200),
    address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    actual_address_id integer,
    postal_address_id integer,
    free_econ_zone boolean NOT NULL,
    num_of_people_emp integer,
    employees integer,
    employees_year integer,
    employees_date timestamp with time zone,
    turnover numeric(18,2),
    turnover_date timestamp with time zone,
    turnover_year integer,
    notes text,
    classified boolean,
    status_date timestamp with time zone,
    ref_no character varying(25),
    inst_sector_code_id integer,
    legal_form_id integer,
    liq_date timestamp with time zone,
    liq_reason character varying(200),
    suspension_start timestamp with time zone,
    suspension_end timestamp with time zone,
    reorg_type_code character varying(50),
    reorg_date timestamp with time zone,
    reorg_references integer,
    archived boolean NOT NULL DEFAULT false,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    user_id character varying(100) NOT NULL,
    change_reason integer DEFAULT 0 NOT NULL,
    edit_comment character varying(500),
    size_id integer,
    foreign_participation_id integer,
    data_source_classification_id integer,
    reorg_type_id integer,
    unit_status_id integer,
    enterprise_group_id integer,
    ent_group_id_date timestamp with time zone,
    commercial boolean NOT NULL,
    total_capital character varying(100),
    mun_capital_share character varying(100),
    state_capital_share character varying(100),
    priv_capital_share character varying(100),
    foreign_capital_share character varying(100),
    foreign_capital_currency character varying(100),
    ent_group_role_id integer
);




--
-- Name: foreign_participation; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.foreign_participation (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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
    reg_ident integer NOT NULL,
    reg_ident_date timestamp with time zone NOT NULL,
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    name character varying(400),
    short_name character varying(200),
    parent_org_link integer,
    tax_reg_ident character varying(50),
    tax_reg_date timestamp with time zone,
    registration_reason_id integer,
    registration_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    data_source character varying(200),
    address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    actual_address_id integer,
    postal_address_id integer,
    free_econ_zone boolean NOT NULL,
    num_of_people_emp integer,
    employees integer,
    employees_year integer,
    employees_date timestamp with time zone,
    turnover numeric(18,2),
    turnover_date timestamp with time zone,
    turnover_year integer,
    notes text,
    classified boolean,
    status_date timestamp with time zone,
    ref_no character varying(25),
    inst_sector_code_id integer,
    legal_form_id integer,
    liq_date timestamp with time zone,
    liq_reason character varying(200),
    suspension_start timestamp with time zone,
    suspension_end timestamp with time zone,
    reorg_type_code character varying(50),
    reorg_date timestamp with time zone,
    reorg_references integer,
    archived boolean NOT NULL DEFAULT false,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    user_id character varying(100) NOT NULL,
    change_reason integer DEFAULT 0 NOT NULL,
    edit_comment character varying(500),
    size_id integer,
    foreign_participation_id integer,
    data_source_classification_id integer,
    reorg_type_id integer,
    unit_status_id integer,
    enterprise_id integer,
    ent_reg_ident_date timestamp with time zone,
    market boolean,
    total_capital character varying(100),
    mun_capital_share character varying(100),
    state_capital_share character varying(100),
    priv_capital_share character varying(100),
    foreign_capital_share character varying(100),
    foreign_capital_currency character varying(100)
);



--
-- Name: establishment; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.establishment (
    id SERIAL PRIMARY KEY NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    reg_ident integer NOT NULL,
    reg_ident_date timestamp with time zone NOT NULL,
    stat_ident character varying(15),
    stat_ident_date timestamp with time zone,
    name character varying(400),
    short_name character varying(200),
    parent_org_link integer,
    tax_reg_ident character varying(50),
    tax_reg_date timestamp with time zone,
    registration_reason_id integer,
    registration_date timestamp with time zone,
    external_ident character varying(50),
    external_ident_date timestamp with time zone,
    external_ident_type character varying(50),
    data_source character varying(200),
    address_id integer,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    actual_address_id integer,
    postal_address_id integer,
    free_econ_zone boolean NOT NULL,
    num_of_people_emp integer,
    employees integer,
    employees_year integer,
    employees_date timestamp with time zone,
    turnover numeric(18,2),
    turnover_date timestamp with time zone,
    turnover_year integer,
    notes text,
    classified boolean,
    status_date timestamp with time zone,
    ref_no character varying(25),
    inst_sector_code_id integer,
    legal_form_id integer,
    liq_date timestamp with time zone,
    liq_reason character varying(200),
    suspension_start timestamp with time zone,
    suspension_end timestamp with time zone,
    reorg_type_code character varying(50),
    reorg_date timestamp with time zone,
    reorg_references integer,
    archived boolean NOT NULL DEFAULT false,
    start_period timestamp with time zone NOT NULL,
    end_period timestamp with time zone NOT NULL,
    user_id character varying(100) NOT NULL,
    change_reason integer DEFAULT 0 NOT NULL,
    edit_comment character varying(500),
    size_id integer,
    foreign_participation_id integer,
    data_source_classification_id integer,
    reorg_type_id integer,
    unit_status_id integer,
    legal_unit_id integer,
    legal_unit_id_date timestamp with time zone
);



--
-- Name: activity_for_unit; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.activity_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    activity_id integer NOT NULL,
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

CREATE TABLE public.person (
    id integer NOT NULL,
    id_date timestamp with time zone NOT NULL,
    given_name character varying(150),
    personal_id text,
    surname character varying(150),
    middle_name character varying(150),
    birth_date timestamp with time zone,
    sex smallint,
    country_id integer,
    phone_number text,
    phone_number1 text,
    address text
);



--
-- Name: person_for_unit; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.person_for_unit (
    id SERIAL PRIMARY KEY NOT NULL,
    enterprise_id integer NOT NULL,
    person_id integer NOT NULL,
    establishment_id integer NOT NULL,
    legal_unit_id integer NOT NULL,
    enterprise_group_id integer,
    person_type_id integer
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
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
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
    id integer NOT NULL,
    adminstrative_center text,
    parent_id integer,
    full_path text,
    full_path_language1 text,
    full_path_language2 text,
    region_level integer,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
);



--
-- Name: region_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.region ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: registration_reason; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.registration_reason (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
);



--
-- Name: registration_reason_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.registration_reason ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.registration_reason_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reorg_type; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.reorg_type (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
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
    parent_id integer,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text
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
    code integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
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


--
-- Name: unit_status; Type: TABLE; Schema: public; Owner: statbus_development
--

CREATE TABLE public.unit_status (
    id integer NOT NULL,
    name text NOT NULL,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text,
    code text NOT NULL
);



--
-- Name: unit_status_id_seq; Type: SEQUENCE; Schema: public; Owner: statbus_development
--

ALTER TABLE public.unit_status ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.unit_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
    -- legal_unit_id integer REFERENCES public.legal_unit(id) ON DELETE CASCADE,
    -- enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    -- enterprise_group_id integer REFERENCES public.enterprise_group(id) ON DELETE CASCADE,
    value_int INTEGER,
    value_float FLOAT,
    value_str VARCHAR,
    value_bool BOOLEAN
    -- CONSTRAINT "One and only one of establishment_id legal_unit_id enterprise_id must be set"
    -- CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
    --     OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
    --     OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
    --     OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
    --     )
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
--
CREATE TRIGGER trigger_prevent_statbus_role_id_update BEFORE UPDATE OF id ON public.statbus_role FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_statbus_user_id_update BEFORE UPDATE OF id ON public.statbus_user FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_activity_id_update BEFORE UPDATE OF id ON public.activity FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_activity_category_id_update BEFORE UPDATE OF id ON public.activity_category FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_activity_category_role_id_update BEFORE UPDATE OF id ON public.activity_category_role FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_address_id_update BEFORE UPDATE OF id ON public.address FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_analysis_queue_id_update BEFORE UPDATE OF id ON public.analysis_queue FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_country_id_update BEFORE UPDATE OF id ON public.country FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_custom_analysis_check_id_update BEFORE UPDATE OF id ON public.custom_analysis_check FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_data_source_id_update BEFORE UPDATE OF id ON public.data_source FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_data_source_classification_id_update BEFORE UPDATE OF id ON public.data_source_classification FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_data_source_queue_id_update BEFORE UPDATE OF id ON public.data_source_queue FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_data_uploading_log_id_update BEFORE UPDATE OF id ON public.data_uploading_log FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_dictionary_version_id_update BEFORE UPDATE OF id ON public.dictionary_version FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_enterprise_group_id_update BEFORE UPDATE OF id ON public.enterprise_group FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_enterprise_group_role_id_update BEFORE UPDATE OF id ON public.enterprise_group_role FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_enterprise_group_type_id_update BEFORE UPDATE OF id ON public.enterprise_group_type FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_enterprise_id_update BEFORE UPDATE OF id ON public.enterprise FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_foreign_participation_id_update BEFORE UPDATE OF id ON public.foreign_participation FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_legal_form_id_update BEFORE UPDATE OF id ON public.legal_form FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_legal_unit_id_update BEFORE UPDATE OF id ON public.legal_unit FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_establishment_id_update BEFORE UPDATE OF id ON public.establishment FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_activity_for_unit_id_update BEFORE UPDATE OF id ON public.activity_for_unit FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_analysis_log_id_update BEFORE UPDATE OF id ON public.analysis_log FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_country_for_unit_id_update BEFORE UPDATE OF id ON public.country_for_unit FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_person_id_update BEFORE UPDATE OF id ON public.person FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_person_for_unit_id_update BEFORE UPDATE OF id ON public.person_for_unit FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_person_type_id_update BEFORE UPDATE OF id ON public.person_type FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_postal_index_id_update BEFORE UPDATE OF id ON public.postal_index FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_region_id_update BEFORE UPDATE OF id ON public.region FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_registration_reason_id_update BEFORE UPDATE OF id ON public.registration_reason FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_reorg_type_id_update BEFORE UPDATE OF id ON public.reorg_type FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_report_tree_id_update BEFORE UPDATE OF id ON public.report_tree FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_sample_frame_id_update BEFORE UPDATE OF id ON public.sample_frame FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_sector_code_id_update BEFORE UPDATE OF id ON public.sector_code FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_unit_size_id_update BEFORE UPDATE OF id ON public.unit_size FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_unit_status_id_update BEFORE UPDATE OF id ON public.unit_status FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_region_role_id_update BEFORE UPDATE OF id ON public.region_role FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_stat_definition_id_update BEFORE UPDATE OF id ON public.stat_definition FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();
CREATE TRIGGER trigger_prevent_stat_for_unit_id_update BEFORE UPDATE OF id ON public.stat_for_unit FOR EACH ROW EXECUTE FUNCTION public.prevent_id_update();


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
    -- size_id integer,
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
    -- num_of_people_emp integer,
    -- employees integer,
    -- turnover numeric(18,2),
    -- classified boolean,
    -- liq_date timestamp with time zone,
    -- liq_reason character varying(200),
    -- user_id character varying(100) NOT NULL,
    -- change_reason integer DEFAULT 0 NOT NULL,
    -- edit_comment character varying(500),
    -- data_source_classification_id integer,
    -- reorg_type_id integer,
    -- unit_status_id integer,
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
-- Name: activity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.activity_id_seq', 1, false);


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
-- Name: dictionary_version_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.dictionary_version_id_seq', 1, false);


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
-- Name: region_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.region_id_seq', 1, false);


--
-- Name: registration_reason_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.registration_reason_id_seq', 1, false);


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
-- Name: unit_status_id_seq; Type: SEQUENCE SET; Schema: public; Owner: statbus_development
--

SELECT pg_catalog.setval('public.unit_status_id_seq', 1, false);


--
-- Name: activity pk_activity; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT pk_activity PRIMARY KEY (id);


--
-- Name: activity_category pk_activity_category; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_category
    ADD CONSTRAINT pk_activity_category PRIMARY KEY (id);


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
-- Name: dictionary_version pk_dictionary_version; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.dictionary_version
    ADD CONSTRAINT pk_dictionary_version PRIMARY KEY (id);


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
-- Name: region pk_region; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.region
    ADD CONSTRAINT pk_region PRIMARY KEY (id);


--
-- Name: registration_reason pk_registration_reason; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.registration_reason
    ADD CONSTRAINT pk_registration_reason PRIMARY KEY (id);


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
-- Name: unit_status pk_unit_status; Type: CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.unit_status
    ADD CONSTRAINT pk_unit_status PRIMARY KEY (id);


--
-- Name: ix_activity_activity_category_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_activity_category_id ON public.activity USING btree (activity_category_id);


--
-- Name: ix_activity_category_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_activity_category_code ON public.activity_category USING btree (code);


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
-- Name: ix_activity_for_unit_activity_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_for_unit_activity_id ON public.activity_for_unit USING btree (activity_id);


--
-- Name: ix_activity_for_unit_enterprise_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_for_unit_enterprise_id ON public.activity_for_unit USING btree (enterprise_id);


--
-- Name: ix_activity_for_unit_establishment_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_for_unit_establishment_id ON public.activity_for_unit USING btree (establishment_id);


--
-- Name: ix_activity_for_unit_unit_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_activity_for_unit_unit_id ON public.activity_for_unit USING btree (legal_unit_id);


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
-- Name: ix_country_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_country_code ON public.country USING btree (code);


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
-- Name: ix_enterprise_group_actual_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_actual_address_id ON public.enterprise_group USING btree (actual_address_id);


--
-- Name: ix_enterprise_group_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_address_id ON public.enterprise_group USING btree (address_id);


--
-- Name: ix_enterprise_group_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_data_source_classification_id ON public.enterprise_group USING btree (data_source_classification_id);


--
-- Name: ix_enterprise_group_ent_group_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_ent_group_type_id ON public.enterprise_group USING btree (ent_group_type_id);


--
-- Name: ix_enterprise_group_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_foreign_participation_id ON public.enterprise_group USING btree (foreign_participation_id);


--
-- Name: ix_enterprise_group_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_name ON public.enterprise_group USING btree (name);


--
-- Name: ix_enterprise_group_postal_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_postal_address_id ON public.enterprise_group USING btree (postal_address_id);


--
-- Name: ix_enterprise_group_registration_reason_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_registration_reason_id ON public.enterprise_group USING btree (registration_reason_id);


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

CREATE INDEX ix_enterprise_group_size_id ON public.enterprise_group USING btree (size_id);


--
-- Name: ix_enterprise_group_start_period; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_start_period ON public.enterprise_group USING btree (start_period);


--
-- Name: ix_enterprise_group_type_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_enterprise_group_type_code ON public.enterprise_group_type USING btree (code);


--
-- Name: ix_enterprise_group_unit_status_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_group_unit_status_id ON public.enterprise_group USING btree (unit_status_id);


--
-- Name: ix_enterprise_actual_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_actual_address_id ON public.enterprise USING btree (actual_address_id);


--
-- Name: ix_enterprise_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_address_id ON public.enterprise USING btree (address_id);


--
-- Name: ix_enterprise_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_data_source_classification_id ON public.enterprise USING btree (data_source_classification_id);


--
-- Name: ix_enterprise_ent_group_role_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_ent_group_role_id ON public.enterprise USING btree (ent_group_role_id);


--
-- Name: ix_enterprise_enterprise_group_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_enterprise_group_id ON public.enterprise USING btree (enterprise_group_id);


--
-- Name: ix_enterprise_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_foreign_participation_id ON public.enterprise USING btree (foreign_participation_id);


--
-- Name: ix_enterprise_inst_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_inst_sector_code_id ON public.enterprise USING btree (inst_sector_code_id);


--
-- Name: ix_enterprise_legal_form_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_legal_form_id ON public.enterprise USING btree (legal_form_id);


--
-- Name: ix_enterprise_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_name ON public.enterprise USING btree (name);


--
-- Name: ix_enterprise_postal_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_postal_address_id ON public.enterprise USING btree (postal_address_id);


--
-- Name: ix_enterprise_registration_reason_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_registration_reason_id ON public.enterprise USING btree (registration_reason_id);


--
-- Name: ix_enterprise_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_reorg_type_id ON public.enterprise USING btree (reorg_type_id);


--
-- Name: ix_enterprise_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_short_name_reg_ident_stat_ident_tax_reg_ident ON public.enterprise USING btree (short_name, reg_ident, stat_ident, tax_reg_ident);


--
-- Name: ix_enterprise_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_size_id ON public.enterprise USING btree (size_id);


--
-- Name: ix_enterprise_start_period; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_start_period ON public.enterprise USING btree (start_period);


--
-- Name: ix_enterprise_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_stat_ident ON public.enterprise USING btree (stat_ident);


--
-- Name: ix_enterprise_unit_status_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_enterprise_unit_status_id ON public.enterprise USING btree (unit_status_id);


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

CREATE INDEX ix_legal_unit_actual_address_id ON public.legal_unit USING btree (actual_address_id);


--
-- Name: ix_legal_unit_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_address_id ON public.legal_unit USING btree (address_id);


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
-- Name: ix_legal_unit_inst_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_inst_sector_code_id ON public.legal_unit USING btree (inst_sector_code_id);


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
-- Name: ix_legal_unit_registration_reason_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_registration_reason_id ON public.legal_unit USING btree (registration_reason_id);


--
-- Name: ix_legal_unit_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_reorg_type_id ON public.legal_unit USING btree (reorg_type_id);


--
-- Name: ix_legal_unit_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_short_name_reg_ident_stat_ident_tax_reg_ident ON public.legal_unit USING btree (short_name, reg_ident, stat_ident, tax_reg_ident);


--
-- Name: ix_legal_unit_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (size_id);


--
-- Name: ix_legal_unit_start_period; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_start_period ON public.legal_unit USING btree (start_period);


--
-- Name: ix_legal_unit_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_stat_ident ON public.legal_unit USING btree (stat_ident);


--
-- Name: ix_legal_unit_unit_status_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_legal_unit_unit_status_id ON public.legal_unit USING btree (unit_status_id);


--
-- Name: ix_establishment_actual_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_actual_address_id ON public.establishment USING btree (actual_address_id);


--
-- Name: ix_establishment_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_address_id ON public.establishment USING btree (address_id);


--
-- Name: ix_establishment_data_source_classification_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_data_source_classification_id ON public.establishment USING btree (data_source_classification_id);


--
-- Name: ix_establishment_foreign_participation_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_foreign_participation_id ON public.establishment USING btree (foreign_participation_id);


--
-- Name: ix_establishment_inst_sector_code_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_inst_sector_code_id ON public.establishment USING btree (inst_sector_code_id);


--
-- Name: ix_establishment_legal_form_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_legal_form_id ON public.establishment USING btree (legal_form_id);


--
-- Name: ix_establishment_legal_unit_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_legal_unit_id ON public.establishment USING btree (legal_unit_id);


--
-- Name: ix_establishment_name; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_name ON public.establishment USING btree (name);


--
-- Name: ix_establishment_postal_address_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_postal_address_id ON public.establishment USING btree (postal_address_id);


--
-- Name: ix_establishment_registration_reason_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_registration_reason_id ON public.establishment USING btree (registration_reason_id);


--
-- Name: ix_establishment_reorg_type_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_reorg_type_id ON public.establishment USING btree (reorg_type_id);


--
-- Name: ix_establishment_short_name_reg_ident_stat_ident_tax_reg_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_short_name_reg_ident_stat_ident_tax_reg_ident ON public.establishment USING btree (short_name, reg_ident, stat_ident, tax_reg_ident);


--
-- Name: ix_establishment_size_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_size_id ON public.establishment USING btree (size_id);


--
-- Name: ix_establishment_start_period; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_start_period ON public.establishment USING btree (start_period);


--
-- Name: ix_establishment_stat_ident; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_stat_ident ON public.establishment USING btree (stat_ident);


--
-- Name: ix_establishment_unit_status_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_establishment_unit_status_id ON public.establishment USING btree (unit_status_id);


--
-- Name: ix_person_country_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_country_id ON public.person USING btree (country_id);


--
-- Name: ix_person_for_unit_enterprise_group_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_for_unit_enterprise_group_id ON public.person_for_unit USING btree (enterprise_group_id);


--
-- Name: ix_person_for_unit_enterprise_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_for_unit_enterprise_id ON public.person_for_unit USING btree (enterprise_id);


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

CREATE UNIQUE INDEX ix_person_for_unit_person_type_id_establishment_id_legal_unit_id_ ON public.person_for_unit USING btree (person_type_id, establishment_id, legal_unit_id, enterprise_id, person_id);


--
-- Name: ix_person_given_name_surname; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_person_given_name_surname ON public.person USING btree (given_name, surname);


--
-- Name: ix_region_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_region_code ON public.region USING btree (code);


--
-- Name: ix_region_parent_id; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE INDEX ix_region_parent_id ON public.region USING btree (parent_id);


--
-- Name: ix_registration_reason_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_registration_reason_code ON public.registration_reason USING btree (code);


--
-- Name: ix_reorg_type_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_reorg_type_code ON public.reorg_type USING btree (code);


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
-- Name: ix_unit_status_code; Type: INDEX; Schema: public; Owner: statbus_development
--

CREATE UNIQUE INDEX ix_unit_status_code ON public.unit_status USING btree (code);


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
-- Name: activity_for_unit fk_activity_for_unit_activity_activity_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_for_unit
    ADD CONSTRAINT fk_activity_for_unit_activity_activity_id FOREIGN KEY (activity_id) REFERENCES public.activity(id) ON DELETE CASCADE;


--
-- Name: activity_for_unit fk_activity_for_unit_enterprise_enterprise_temp_id3; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.activity_for_unit
    ADD CONSTRAINT fk_activity_for_unit_enterprise_enterprise_temp_id3 FOREIGN KEY (enterprise_id) REFERENCES public.enterprise(id);


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
-- Name: enterprise_group fk_enterprise_group_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_address_actual_address_id FOREIGN KEY (actual_address_id) REFERENCES public.address(id);


--
-- Name: enterprise_group fk_enterprise_group_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_address_address_id FOREIGN KEY (address_id) REFERENCES public.address(id);


--
-- Name: enterprise_group fk_enterprise_group_address_postal_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_address_postal_address_id FOREIGN KEY (postal_address_id) REFERENCES public.address(id);


--
-- Name: enterprise_group fk_enterprise_group_data_source_classification_data_source_cla; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_data_source_classification_data_source_cla FOREIGN KEY (data_source_classification_id) REFERENCES public.data_source_classification(id);


--
-- Name: enterprise_group fk_enterprise_group_enterprise_group_type_ent_group_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_enterprise_group_type_ent_group_type_id FOREIGN KEY (ent_group_type_id) REFERENCES public.enterprise_group_type(id);


--
-- Name: enterprise_group fk_enterprise_group_foreign_participation_foreign_participatio; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_foreign_participation_foreign_participatio FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: enterprise_group fk_enterprise_group_registration_reason_registration_reason_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_registration_reason_registration_reason_id FOREIGN KEY (registration_reason_id) REFERENCES public.registration_reason(id);


--
-- Name: enterprise_group fk_enterprise_group_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: enterprise_group fk_enterprise_group_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_unit_size_size_id FOREIGN KEY (size_id) REFERENCES public.unit_size(id);


--
-- Name: enterprise_group fk_enterprise_group_unit_status_unit_status_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise_group
    ADD CONSTRAINT fk_enterprise_group_unit_status_unit_status_id FOREIGN KEY (unit_status_id) REFERENCES public.unit_status(id);


--
-- Name: enterprise fk_enterprise_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_address_actual_address_id FOREIGN KEY (actual_address_id) REFERENCES public.address(id);


--
-- Name: enterprise fk_enterprise_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_address_address_id FOREIGN KEY (address_id) REFERENCES public.address(id);


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
    ADD CONSTRAINT fk_enterprise_enterprise_group_role_ent_group_role_id FOREIGN KEY (ent_group_role_id) REFERENCES public.enterprise_group_role(id);


--
-- Name: enterprise fk_enterprise_foreign_participation_foreign_participation; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_foreign_participation_foreign_participation FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: enterprise fk_enterprise_legal_form_legal_form_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_legal_form_legal_form_id FOREIGN KEY (legal_form_id) REFERENCES public.legal_form(id);


--
-- Name: enterprise fk_enterprise_registration_reason_registration_reason_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_registration_reason_registration_reason_id FOREIGN KEY (registration_reason_id) REFERENCES public.registration_reason(id);


--
-- Name: enterprise fk_enterprise_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: enterprise fk_enterprise_sector_code_inst_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_sector_code_inst_sector_code_id FOREIGN KEY (inst_sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: enterprise fk_enterprise_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_unit_size_size_id FOREIGN KEY (size_id) REFERENCES public.unit_size(id);


--
-- Name: enterprise fk_enterprise_unit_status_unit_status_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.enterprise
    ADD CONSTRAINT fk_enterprise_unit_status_unit_status_id FOREIGN KEY (unit_status_id) REFERENCES public.unit_status(id);


--
-- Name: legal_unit fk_legal_unit_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_address_actual_address_id FOREIGN KEY (actual_address_id) REFERENCES public.address(id);


--
-- Name: legal_unit fk_legal_unit_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_address_address_id FOREIGN KEY (address_id) REFERENCES public.address(id);


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
-- Name: legal_unit fk_legal_unit_registration_reason_registration_reason_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_registration_reason_registration_reason_id FOREIGN KEY (registration_reason_id) REFERENCES public.registration_reason(id);


--
-- Name: legal_unit fk_legal_unit_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: legal_unit fk_legal_unit_sector_code_inst_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_sector_code_inst_sector_code_id FOREIGN KEY (inst_sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: legal_unit fk_legal_unit_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_unit_size_size_id FOREIGN KEY (size_id) REFERENCES public.unit_size(id);


--
-- Name: legal_unit fk_legal_unit_unit_status_unit_status_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.legal_unit
    ADD CONSTRAINT fk_legal_unit_unit_status_unit_status_id FOREIGN KEY (unit_status_id) REFERENCES public.unit_status(id);


--
-- Name: establishment fk_establishment_address_actual_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_address_actual_address_id FOREIGN KEY (actual_address_id) REFERENCES public.address(id);


--
-- Name: establishment fk_establishment_address_address_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_address_address_id FOREIGN KEY (address_id) REFERENCES public.address(id);


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
-- Name: establishment fk_establishment_foreign_participation_foreign_participation_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_foreign_participation_foreign_participation_id FOREIGN KEY (foreign_participation_id) REFERENCES public.foreign_participation(id);


--
-- Name: establishment fk_establishment_legal_form_legal_form_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_legal_form_legal_form_id FOREIGN KEY (legal_form_id) REFERENCES public.legal_form(id);


--
-- Name: establishment fk_establishment_legal_unit_legal_unit_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_legal_unit_legal_unit_id FOREIGN KEY (legal_unit_id) REFERENCES public.legal_unit(id);


--
-- Name: establishment fk_establishment_registration_reason_registration_reason_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_registration_reason_registration_reason_id FOREIGN KEY (registration_reason_id) REFERENCES public.registration_reason(id);


--
-- Name: establishment fk_establishment_reorg_type_reorg_type_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_reorg_type_reorg_type_id FOREIGN KEY (reorg_type_id) REFERENCES public.reorg_type(id);


--
-- Name: establishment fk_establishment_sector_code_inst_sector_code_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_sector_code_inst_sector_code_id FOREIGN KEY (inst_sector_code_id) REFERENCES public.sector_code(id);


--
-- Name: establishment fk_establishment_unit_size_size_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_unit_size_size_id FOREIGN KEY (size_id) REFERENCES public.unit_size(id);


--
-- Name: establishment fk_establishment_unit_status_unit_status_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.establishment
    ADD CONSTRAINT fk_establishment_unit_status_unit_status_id FOREIGN KEY (unit_status_id) REFERENCES public.unit_status(id);


--
-- Name: person fk_person_country_country_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT fk_person_country_country_id FOREIGN KEY (country_id) REFERENCES public.country(id);


--
-- Name: person_for_unit fk_person_for_unit_enterprise_group_enterprise_group_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_enterprise_group_enterprise_group_id FOREIGN KEY (enterprise_group_id) REFERENCES public.enterprise_group(id);


--
-- Name: person_for_unit fk_person_for_unit_enterprise_enterprise_id; Type: FK CONSTRAINT; Schema: public; Owner: statbus_development
--

ALTER TABLE ONLY public.person_for_unit
    ADD CONSTRAINT fk_person_for_unit_enterprise_enterprise_id FOREIGN KEY (enterprise_id) REFERENCES public.enterprise(id) ON DELETE CASCADE;


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


-- Activate era handling
SELECT sql_saga.add_era('public.enterprise_group', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['id']);
SELECT sql_saga.add_era('public.enterprise', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise', ARRAY['id']);
SELECT sql_saga.add_foreign_key('public.enterprise', ARRAY['enterprise_group_id'], 'valid', 'enterprise_group_id_valid');
SELECT sql_saga.add_era('public.legal_unit', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['id']);
SELECT sql_saga.add_era('public.establishment', 'valid_from', 'valid_to');
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['id']);
TABLE sql_saga.era;
TABLE sql_saga.unique_keys;
TABLE sql_saga.foreign_keys;


ALTER TABLE public.statbus_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.statbus_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_category_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_for_unit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.address ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.country ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.country_for_unit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_analysis_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_source_classification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_source_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_uploading_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dictionary_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enterprise_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enterprise_group_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enterprise_group_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enterprise ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.foreign_participation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_form ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_unit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.establishment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person_for_unit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postal_index ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.region ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_reason ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorg_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_tree ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sample_frame ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sector_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_size ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.region_role ENABLE ROW LEVEL SECURITY;


-- All authenticated users can read everything, regardless of role.
CREATE POLICY statbus_user_authenticated_read ON public.statbus_user FOR SELECT TO authenticated USING (true);
CREATE POLICY statbus_role_authenticated_read ON public.statbus_role FOR SELECT TO authenticated USING (true);
CREATE POLICY activity_authenticated_read ON public.activity FOR SELECT TO authenticated USING (true);
CREATE POLICY activity_category_authenticated_read ON public.activity_category FOR SELECT TO authenticated USING (true);
CREATE POLICY activity_category_role_authenticated_read ON public.activity_category_role FOR SELECT TO authenticated USING (true);
CREATE POLICY activity_for_unit_authenticated_read ON public.activity_for_unit FOR SELECT TO authenticated USING (true);
CREATE POLICY address_authenticated_read ON public.address FOR SELECT TO authenticated USING (true);
CREATE POLICY analysis_log_authenticated_read ON public.analysis_log FOR SELECT TO authenticated USING (true);
CREATE POLICY analysis_queue_authenticated_read ON public.analysis_queue FOR SELECT TO authenticated USING (true);
CREATE POLICY country_authenticated_read ON public.country FOR SELECT TO authenticated USING (true);
CREATE POLICY country_for_unit_authenticated_read ON public.country_for_unit FOR SELECT TO authenticated USING (true);
CREATE POLICY custom_analysis_check_authenticated_read ON public.custom_analysis_check FOR SELECT TO authenticated USING (true);
CREATE POLICY data_source_authenticated_read ON public.data_source FOR SELECT TO authenticated USING (true);
CREATE POLICY data_source_classification_authenticated_read ON public.data_source_classification FOR SELECT TO authenticated USING (true);
CREATE POLICY data_source_queue_authenticated_read ON public.data_source_queue FOR SELECT TO authenticated USING (true);
CREATE POLICY data_uploading_log_authenticated_read ON public.data_uploading_log FOR SELECT TO authenticated USING (true);
CREATE POLICY dictionary_version_authenticated_read ON public.dictionary_version FOR SELECT TO authenticated USING (true);
CREATE POLICY enterprise_group_authenticated_read ON public.enterprise_group FOR SELECT TO authenticated USING (true);
CREATE POLICY enterprise_group_role_authenticated_read ON public.enterprise_group_role FOR SELECT TO authenticated USING (true);
CREATE POLICY enterprise_group_type_authenticated_read ON public.enterprise_group_type FOR SELECT TO authenticated USING (true);
CREATE POLICY enterprise_authenticated_read ON public.enterprise FOR SELECT TO authenticated USING (true);
CREATE POLICY foreign_participation_authenticated_read ON public.foreign_participation FOR SELECT TO authenticated USING (true);
CREATE POLICY legal_form_authenticated_read ON public.legal_form FOR SELECT TO authenticated USING (true);
CREATE POLICY legal_unit_authenticated_read ON public.legal_unit FOR SELECT TO authenticated USING (true);
CREATE POLICY establishment_authenticated_read ON public.establishment FOR SELECT TO authenticated USING (true);
CREATE POLICY person_authenticated_read ON public.person FOR SELECT TO authenticated USING (true);
CREATE POLICY person_for_unit_authenticated_read ON public.person_for_unit FOR SELECT TO authenticated USING (true);
CREATE POLICY person_type_authenticated_read ON public.person_type FOR SELECT TO authenticated USING (true);
CREATE POLICY postal_index_authenticated_read ON public.postal_index FOR SELECT TO authenticated USING (true);
CREATE POLICY region_authenticated_read ON public.region FOR SELECT TO authenticated USING (true);
CREATE POLICY registration_reason_authenticated_read ON public.registration_reason FOR SELECT TO authenticated USING (true);
CREATE POLICY reorg_type_authenticated_read ON public.reorg_type FOR SELECT TO authenticated USING (true);
CREATE POLICY report_tree_authenticated_read ON public.report_tree FOR SELECT TO authenticated USING (true);
CREATE POLICY sample_frame_authenticated_read ON public.sample_frame FOR SELECT TO authenticated USING (true);
CREATE POLICY sector_code_authenticated_read ON public.sector_code FOR SELECT TO authenticated USING (true);
CREATE POLICY unit_size_authenticated_read ON public.unit_size FOR SELECT TO authenticated USING (true);
CREATE POLICY unit_status_authenticated_read ON public.unit_status FOR SELECT TO authenticated USING (true);
CREATE POLICY region_role ON public.region_role FOR SELECT TO authenticated USING (true);


-- Administrators can do anything to any table.
CREATE POLICY statbus_user_administrator_manage ON public.statbus_user FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY statbus_role_administrator_manage ON public.statbus_role FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY activity_administrator_manage ON public.activity FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY activity_category_administrator_manage ON public.activity_category FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY activity_category_role_administrator_manage ON public.activity_category_role FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY activity_for_unit_administrator_manage ON public.activity_for_unit FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY address_administrator_manage ON public.address FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY analysis_log_administrator_manage ON public.analysis_log FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY analysis_queue_administrator_manage ON public.analysis_queue FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY country_administrator_manage ON public.country FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY country_for_unit_administrator_manage ON public.country_for_unit FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY custom_analysis_check_administrator_manage ON public.custom_analysis_check FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY data_source_administrator_manage ON public.data_source FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY data_source_classification_administrator_manage ON public.data_source_classification FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY data_source_queue_administrator_manage ON public.data_source_queue FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY data_uploading_log_administrator_manage ON public.data_uploading_log FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY dictionary_version_administrator_manage ON public.dictionary_version FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY enterprise_group_administrator_manage ON public.enterprise_group FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY enterprise_group_role_administrator_manage ON public.enterprise_group_role FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY enterprise_group_type_administrator_manage ON public.enterprise_group_type FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY enterprise_administrator_manage ON public.enterprise FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY foreign_participation_administrator_manage ON public.foreign_participation FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY legal_form_administrator_manage ON public.legal_form FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY legal_unit_administrator_manage ON public.legal_unit FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY establishment_administrator_manage ON public.establishment FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY person_administrator_manage ON public.person FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY person_for_unit_administrator_manage ON public.person_for_unit FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY person_type_administrator_manage ON public.person_type FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY postal_index_administrator_manage ON public.postal_index FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY region_administrator_manage ON public.region FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY registration_reason_administrator_manage ON public.registration_reason FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY reorg_type_administrator_manage ON public.reorg_type FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY report_tree_administrator_manage ON public.report_tree FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY sample_frame_administrator_manage ON public.sample_frame FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY sector_code_administrator_manage ON public.sector_code FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY unit_size_administrator_manage ON public.unit_size FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY unit_status_administrator_manage ON public.unit_status FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));
CREATE POLICY region_role_administrator_manage ON public.region_role FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type));


-- The employees can only update the tables designated by their assigned region or activity_category
CREATE POLICY activity_employee_manage ON public.activity FOR ALL TO authenticated
USING (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), activity_category_id)
      )
WITH CHECK (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), activity_category_id)
      );

--CREATE POLICY "premium and admin view access" ON premium_records FOR ALL TO authenticated USING (has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[]));

NOTIFY pgrst, 'reload config';

END;
