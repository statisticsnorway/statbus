BEGIN;

CREATE TABLE public.tag_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tag_id integer NOT NULL REFERENCES public.tag(id) ON DELETE CASCADE,
    establishment_id integer CHECK (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer CHECK (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer CHECK (admin.enterprise_group_id_exists(enterprise_group_id)),
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    UNIQUE (tag_id, establishment_id),
    UNIQUE (tag_id, legal_unit_id),
    UNIQUE (tag_id, enterprise_id),
    UNIQUE (tag_id, enterprise_group_id),
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);
CREATE INDEX ix_tag_for_unit_tag_id ON public.tag_for_unit USING btree (tag_id);
CREATE INDEX ix_tag_for_unit_establishment_id_id ON public.tag_for_unit USING btree (establishment_id);
CREATE INDEX ix_tag_for_unit_legal_unit_id_id ON public.tag_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_tag_for_unit_enterprise_id_id ON public.tag_for_unit USING btree (enterprise_id);
CREATE INDEX ix_tag_for_unit_enterprise_group_id_id ON public.tag_for_unit USING btree (enterprise_group_id);
CREATE INDEX ix_tag_for_unit_edit_by_user_id ON public.tag_for_unit USING btree (edit_by_user_id);

END;
