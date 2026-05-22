-- Down Migration: add_import_analyse_length_limits
--
-- Reverts:
--   1. Removes the import_step row for 'analyse_length_limits'
--      (ON DELETE CASCADE will also remove any import_data_column
--      rows owned by that step, of which there are currently none).
--   2. Drops import.analyse_length_limits procedure.
--
-- Note: definition_snapshots in existing public.import_job rows
-- still reference the dropped step. Those snapshots are immutable
-- per-job artifacts and shouldn't be mutated post-creation. New
-- imports created after this down migration won't include the
-- length_limits step.

BEGIN;

DELETE FROM public.import_step WHERE code = 'analyse_length_limits';

DROP PROCEDURE IF EXISTS import.analyse_length_limits(integer, integer, text);

END;
