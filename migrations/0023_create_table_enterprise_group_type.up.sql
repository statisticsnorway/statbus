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