BEGIN;

CREATE TABLE public.stat_for_unit (
    id SERIAL NOT NULL,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE RESTRICT,
    valid_from date NOT NULL,
    valid_after date NOT NULL,
    valid_to date NOT NULL DEFAULT 'infinity',
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    value_int INTEGER,
    value_float FLOAT,
    value_string VARCHAR,
    value_bool BOOLEAN,
    CHECK(
        (value_int IS NOT NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS NOT NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS NOT NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS NOT NULL)
    ),
    -- Note: Audit columns (edit_by_user_id, edit_at) are populated by import procedures
    -- using values derived during the import job prepare step.
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp()
);

CREATE INDEX ix_stat_for_unit_stat_definition_id ON public.stat_for_unit USING btree (stat_definition_id);
CREATE INDEX ix_stat_for_unit_data_source_id ON public.stat_for_unit USING btree (data_source_id);
CREATE INDEX ix_stat_for_unit_legal_unit_id ON public.stat_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_stat_for_unit_establishment_id ON public.stat_for_unit USING btree (establishment_id);
CREATE INDEX ix_stat_for_unit_legal_unit_id_valid_range ON public.stat_for_unit USING gist (legal_unit_id, daterange(valid_after, valid_to, '(]'));

CREATE TRIGGER trg_stat_for_unit_synchronize_valid_from_after
    BEFORE INSERT OR UPDATE ON public.stat_for_unit
    FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

END;
