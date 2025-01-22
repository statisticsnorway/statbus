BEGIN;

CREATE TYPE public.tag_type AS ENUM ('custom', 'system');

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

END;