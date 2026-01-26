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
    CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) = 1)
);

-- One notes record per unit - consolidated with NULLS NOT DISTINCT
-- The CHECK constraint ensures exactly one unit_id is non-null,
-- so NULLS NOT DISTINCT enforces uniqueness across all unit types in one index.
-- Replaces 4 separate unique indexes with 1 comprehensive index.
CREATE UNIQUE INDEX unit_notes_unit_consolidated_key 
ON public.unit_notes (establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) 
NULLS NOT DISTINCT;

CREATE INDEX ix_unit_notes_edit_by_user_id ON public.unit_notes USING btree (edit_by_user_id);

END;
