BEGIN;

CREATE TABLE public.country (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso_2 text UNIQUE NOT NULL,
    iso_3 text UNIQUE NOT NULL,
    iso_num text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(iso_2, iso_3, iso_num, name)
);
CREATE UNIQUE INDEX ix_country_iso_2 ON public.country USING btree (iso_2) WHERE active;
CREATE UNIQUE INDEX ix_country_iso_3 ON public.country USING btree (iso_3) WHERE active;
CREATE UNIQUE INDEX ix_country_iso_num ON public.country USING btree (iso_num) WHERE active;
CREATE INDEX ix_country_active ON public.country USING btree (active);

END;
