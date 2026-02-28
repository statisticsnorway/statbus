BEGIN;

CREATE TABLE public.tag_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tag_id integer NOT NULL REFERENCES public.tag(id) ON DELETE CASCADE,
    establishment_id integer CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    power_group_id integer CHECK (admin.power_group_id_exists(power_group_id)),
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    -- Removed separate UNIQUE constraints in favor of partial unique indexes below
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, power_group_id) = 1)
);
CREATE INDEX ix_tag_for_unit_tag_id ON public.tag_for_unit USING btree (tag_id);
CREATE INDEX ix_tag_for_unit_establishment_id_id ON public.tag_for_unit USING btree (establishment_id);
CREATE INDEX ix_tag_for_unit_legal_unit_id_id ON public.tag_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_tag_for_unit_enterprise_id_id ON public.tag_for_unit USING btree (enterprise_id);
CREATE INDEX ix_tag_for_unit_power_group_id_id ON public.tag_for_unit USING btree (power_group_id);
CREATE INDEX ix_tag_for_unit_edit_by_user_id ON public.tag_for_unit USING btree (edit_by_user_id);

-- One tag per unit - consolidated with NULLS NOT DISTINCT
-- The CHECK constraint ensures exactly one unit_id is non-null,
-- so NULLS NOT DISTINCT enforces uniqueness per tag+unit in one index.
-- Replaces 4 partial unique indexes with 1 comprehensive index.
CREATE UNIQUE INDEX tag_for_unit_tag_unit_consolidated_key 
ON public.tag_for_unit (tag_id, establishment_id, legal_unit_id, enterprise_id, power_group_id) 
NULLS NOT DISTINCT;

END;
