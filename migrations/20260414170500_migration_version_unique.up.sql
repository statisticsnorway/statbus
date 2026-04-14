-- Migration 20260414170500: migration_version_unique
--
-- Close a latent bug in db.migration: its primary key is (id SERIAL),
-- not (version). Two concurrent `./sb migrate up` runs could both apply
-- the same migration version and both insert bookkeeping rows — silent
-- duplication of applied history.
--
-- Complements the process-level mutex added to migrate.Up()
-- (pg_advisory_lock(hashtext('migrate_up'))) by closing the DB-layer
-- hole in case a future code path bypasses the Go wrapper and inserts
-- into db.migration directly.
BEGIN;

-- Defensively remove any existing duplicates before adding the constraint.
-- Keep the oldest row (smallest id) per version; delete the rest.
DELETE FROM db.migration m
 USING (
   SELECT version, MIN(id) AS keep_id
     FROM db.migration
    GROUP BY version
   HAVING COUNT(*) > 1
 ) d
 WHERE m.version = d.version
   AND m.id != d.keep_id;

ALTER TABLE db.migration
  ADD CONSTRAINT migration_version_unique UNIQUE (version);

END;
