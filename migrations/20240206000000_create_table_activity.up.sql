BEGIN;

CREATE TYPE public.activity_type AS ENUM ('primary', 'secondary', 'ancilliary');

CREATE TABLE public.activity (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    type public.activity_type NOT NULL,
    category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_activity_category_id ON public.activity USING btree (category_id);
CREATE INDEX ix_activity_establishment_id ON public.activity USING btree (establishment_id);
CREATE INDEX ix_activity_legal_unit_id ON public.activity USING btree (legal_unit_id);
CREATE INDEX ix_activity_edit_by_user_id ON public.activity USING btree (edit_by_user_id);
CREATE INDEX ix_activity_establishment_valid_after_valid_to ON public.activity USING btree (establishment_id, valid_after, valid_to);

END;
