-- Down migration: drop public.normalize_all_sequences().
--
-- Safe to drop cleanly (unlike a data-repair migration's down): this
-- procedure has no persistent state of its own -- it only ever reads
-- pg_catalog and calls setval on sequences that already exist. Dropping it
-- does not undo any setval calls already made; those sequence positions
-- are correct data (derived from the rows actually present), not an
-- artifact of the procedure's existence, and are left exactly as they are
-- -- same principle as every other STATBUS-31x down migration that
-- restores prior CODE without reverting data a fix legitimately produced.

BEGIN;

DROP PROCEDURE IF EXISTS public.normalize_all_sequences();

COMMIT;
