BEGIN;

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

END;