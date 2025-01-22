BEGIN;

CREATE TABLE public.external_ident (
    id SERIAL NOT NULL,
    ident VARCHAR(50) NOT NULL,
    type_id INTEGER NOT NULL REFERENCES public.external_ident_type(id) ON DELETE RESTRICT,
    establishment_id INTEGER CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id INTEGER CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id INTEGER REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id INTEGER CHECK (admin.enterprise_group_id_exists(enterprise_group_id)),
    updated_by_user_id INTEGER NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);

CREATE UNIQUE INDEX external_ident_type_for_ident ON public.external_ident(type_id, ident);
CREATE UNIQUE INDEX external_ident_type_for_establishment ON public.external_ident(type_id, establishment_id) WHERE establishment_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_legal_unit ON public.external_ident(type_id, legal_unit_id) WHERE legal_unit_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_enterprise ON public.external_ident(type_id, enterprise_id) WHERE enterprise_id IS NOT NULL;
CREATE UNIQUE INDEX external_ident_type_for_enterprise_group ON public.external_ident(type_id, enterprise_group_id) WHERE enterprise_group_id IS NOT NULL;
CREATE INDEX external_ident_establishment_id_idx ON public.external_ident(establishment_id);
CREATE INDEX external_ident_legal_unit_id_idx ON public.external_ident(legal_unit_id);
CREATE INDEX external_ident_enterprise_id_idx ON public.external_ident(enterprise_id);
CREATE INDEX external_ident_enterprise_group_id_idx ON public.external_ident(enterprise_group_id);

END;