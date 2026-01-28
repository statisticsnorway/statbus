-- Down Migration 20250123095441: Create a notes table
BEGIN;

DROP INDEX IF EXISTS ix_unit_notes_establishment_id;
DROP INDEX IF EXISTS ix_unit_notes_legal_unit_id;
DROP INDEX IF EXISTS ix_unit_notes_enterprise_id;
DROP INDEX IF EXISTS ix_unit_notes_power_group_id;
DROP INDEX IF EXISTS ix_unit_notes_updated_by_user_id;

DROP TABLE IF EXISTS public.unit_notes;

END;
