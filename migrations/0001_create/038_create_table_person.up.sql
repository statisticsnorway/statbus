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