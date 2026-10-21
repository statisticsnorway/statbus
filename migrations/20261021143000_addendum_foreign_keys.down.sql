-- STATBUS-524 down: restore the hand-written admin.*_id_exists CHECK constraints.
BEGIN;
SET LOCAL lock_timeout = '30s';

-- Recreate the helpers first; the CHECKs reference them.
CREATE FUNCTION admin.legal_unit_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.legal_unit WHERE id = fk_id);
$$;
CREATE FUNCTION admin.establishment_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.establishment WHERE id = fk_id);
$$;
CREATE FUNCTION admin.person_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.person WHERE id = fk_id);
$$;
CREATE FUNCTION admin.power_group_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.power_group WHERE id = fk_id);
$$;

-- Drop the native foreign keys and restore the CHECKs.
ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_person_id_fkey;
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_person_id_check
    CHECK (admin.person_id_exists(person_id));
ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_power_group_id_fkey;
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_power_group_id_check
    CHECK (admin.power_group_id_exists(power_group_id));
ALTER TABLE public.tag_for_unit DROP CONSTRAINT tag_for_unit_power_group_id_fkey;
ALTER TABLE public.tag_for_unit ADD CONSTRAINT tag_for_unit_power_group_id_check
    CHECK (admin.power_group_id_exists(power_group_id));
ALTER TABLE public.unit_notes DROP CONSTRAINT unit_notes_power_group_id_fkey;
ALTER TABLE public.unit_notes ADD CONSTRAINT unit_notes_power_group_id_check
    CHECK (admin.power_group_id_exists(power_group_id));

-- Drop the sql_saga foreign keys and restore the CHECKs.
SELECT sql_saga.drop_foreign_key('public.external_ident', ARRAY['legal_unit_id']);
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_legal_unit_id_check
    CHECK (admin.legal_unit_id_exists(legal_unit_id));
SELECT sql_saga.drop_foreign_key('public.external_ident', ARRAY['establishment_id']);
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_establishment_id_check
    CHECK (admin.establishment_id_exists(establishment_id));
SELECT sql_saga.drop_foreign_key('public.tag_for_unit', ARRAY['legal_unit_id']);
ALTER TABLE public.tag_for_unit ADD CONSTRAINT tag_for_unit_legal_unit_id_check
    CHECK (admin.legal_unit_id_exists(legal_unit_id));
SELECT sql_saga.drop_foreign_key('public.tag_for_unit', ARRAY['establishment_id']);
ALTER TABLE public.tag_for_unit ADD CONSTRAINT tag_for_unit_establishment_id_check
    CHECK (admin.establishment_id_exists(establishment_id));
SELECT sql_saga.drop_foreign_key('public.unit_notes', ARRAY['legal_unit_id']);
ALTER TABLE public.unit_notes ADD CONSTRAINT unit_notes_legal_unit_id_check
    CHECK (admin.legal_unit_id_exists(legal_unit_id));
SELECT sql_saga.drop_foreign_key('public.unit_notes', ARRAY['establishment_id']);
ALTER TABLE public.unit_notes ADD CONSTRAINT unit_notes_establishment_id_check
    CHECK (admin.establishment_id_exists(establishment_id));

END;
