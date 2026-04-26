-- Remove the content_hash column. Idempotent; safe to re-run.

BEGIN;

ALTER TABLE db.migration DROP COLUMN IF EXISTS content_hash;

COMMIT;
