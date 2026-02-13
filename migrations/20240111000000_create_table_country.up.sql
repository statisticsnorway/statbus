BEGIN;

CREATE TABLE public.country (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso_2 text UNIQUE NOT NULL,
    iso_3 text UNIQUE NOT NULL,
    iso_num text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(iso_2, iso_3, iso_num, name)
);
CREATE UNIQUE INDEX ix_country_iso_2 ON public.country USING btree (iso_2) WHERE enabled;
CREATE UNIQUE INDEX ix_country_iso_3 ON public.country USING btree (iso_3) WHERE enabled;
CREATE UNIQUE INDEX ix_country_iso_num ON public.country USING btree (iso_num) WHERE enabled;
CREATE INDEX ix_country_enabled ON public.country USING btree (enabled);

END;
