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