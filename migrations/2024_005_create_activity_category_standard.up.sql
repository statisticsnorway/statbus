BEGIN;

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

END;