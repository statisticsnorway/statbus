BEGIN;

CREATE TABLE public.person_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    person_id integer NOT NULL REFERENCES public.person(id) ON DELETE CASCADE,
    person_role_id integer REFERENCES public.person_role(id),
    establishment_id integer check (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer check (admin.legal_unit_id_exists(legal_unit_id)),
    CONSTRAINT "One and only one of establishment_id legal_unit_id  must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_person_for_unit_legal_unit_id ON public.person_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_person_for_unit_establishment_id ON public.person_for_unit USING btree (establishment_id);
CREATE INDEX ix_person_for_unit_person_id ON public.person_for_unit USING btree (person_id);
CREATE UNIQUE INDEX ix_person_for_unit_person_role_id_establishment_id_legal_unit_id_ ON public.person_for_unit USING btree (person_role_id, establishment_id, legal_unit_id, person_id);

END;
