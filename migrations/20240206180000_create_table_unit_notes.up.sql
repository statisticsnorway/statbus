-- Migration 20250123095441: Create a notes table
BEGIN;

CREATE TABLE public.unit_notes (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    notes text NOT NULL,
    establishment_id integer CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer CHECK (admin.enterprise_group_id_exists(enterprise_group_id)),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);

CREATE UNIQUE INDEX ix_unit_notes_establishment_id ON public.unit_notes USING btree (establishment_id);
CREATE UNIQUE INDEX ix_unit_notes_legal_unit_id ON public.unit_notes USING btree (legal_unit_id);
CREATE UNIQUE INDEX ix_unit_notes_enterprise_id ON public.unit_notes USING btree (enterprise_id);
CREATE UNIQUE INDEX ix_unit_notes_enterprise_group_id ON public.unit_notes USING btree (enterprise_group_id);

CREATE INDEX ix_unit_notes_edit_by_user_id ON public.unit_notes USING btree (edit_by_user_id);

END;
