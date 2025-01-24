BEGIN;

CREATE TABLE public.stat_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE RESTRICT,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
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
    )
);

CREATE INDEX ix_stat_for_unit_stat_definition_id ON public.stat_for_unit USING btree (stat_definition_id);
CREATE INDEX ix_stat_for_unit_data_source_id ON public.stat_for_unit USING btree (data_source_id);
CREATE INDEX ix_stat_for_unit_legal_unit_id ON public.stat_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_stat_for_unit_establishment_id ON public.stat_for_unit USING btree (establishment_id);

END;
