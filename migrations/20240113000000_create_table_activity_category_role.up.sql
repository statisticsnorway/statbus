BEGIN;

CREATE TABLE public.activity_category_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
    activity_category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    UNIQUE(role_id, activity_category_id)
);
CREATE INDEX ix_activity_category_role_activity_category_id ON public.activity_category_role USING btree (activity_category_id);
CREATE INDEX ix_activity_category_role_role_id ON public.activity_category_role USING btree (role_id);

END;