BEGIN;

CREATE TABLE public.person_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    person_id integer NOT NULL REFERENCES public.person(id) ON DELETE RESTRICT,
    person_role_id integer REFERENCES public.person_role(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_person_for_unit_person_id ON public.person_for_unit USING btree (person_id);
CREATE INDEX ix_person_for_unit_person_role_id ON public.person_for_unit USING btree (person_role_id);
CREATE INDEX ix_person_for_unit_data_source_id ON public.person_for_unit USING btree (data_source_id);
CREATE INDEX ix_person_for_unit_legal_unit_id ON public.person_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_person_for_unit_establishment_id ON public.person_for_unit USING btree (establishment_id);

END;
