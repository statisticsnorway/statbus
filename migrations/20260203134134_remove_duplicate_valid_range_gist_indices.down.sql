-- Down Migration 20260203134134: remove_duplicate_valid_range_gist_indices
--
-- Recreate the manual GIST indices that were removed.
-- Note: These are technically redundant with sql_saga's indices,
-- but we restore them for rollback compatibility.

BEGIN;

CREATE INDEX IF NOT EXISTS ix_legal_unit_valid_range ON public.legal_unit USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_establishment_valid_range ON public.establishment USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_activity_valid_range ON public.activity USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_contact_valid_range ON public.contact USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_enterprise_group_valid_range ON public.enterprise_group USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_location_valid_range ON public.location USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_person_for_unit_valid_range ON public.person_for_unit USING gist (valid_range);
CREATE INDEX IF NOT EXISTS ix_stat_for_unit_valid_range ON public.stat_for_unit USING gist (valid_range);

END;
