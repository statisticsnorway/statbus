-- Down migration 20260414170500: migration_version_unique
BEGIN;

ALTER TABLE db.migration DROP CONSTRAINT IF EXISTS migration_version_unique;

END;
