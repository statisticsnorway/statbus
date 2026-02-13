BEGIN;

CREATE TABLE public.enterprise (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enabled boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp()
);

CREATE INDEX ix_enterprise_enabled ON public.enterprise USING btree (enabled);
CREATE INDEX ix_enterprise_edit_by_user_id ON public.enterprise USING btree (edit_by_user_id);

END;
