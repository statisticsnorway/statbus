BEGIN;

CREATE TABLE public.enterprise_group_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_enterprise_group_role_code ON public.enterprise_group_role USING btree (code) WHERE active;
CREATE INDEX ix_enterprise_group_role_active ON public.enterprise_group_role USING btree (active);

END;
