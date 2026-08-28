-- Migration 20260828231905: reconstruct import source columns lost to seed path divergence
--
-- STATBUS-312. import.cleanup_orphaned_synced_mappings (migration
-- 20260422011930) deletes an import_source_column whenever its sibling
-- `{name}_raw` import_data_column is absent under the definition's steps.
-- That check is only SAFE once every data-column generator for the
-- GENERATE phase has settled — the migration's own header documents this:
-- cleanup must run LAST, after the columns it is checking against exist.
--
-- A full-from-migrations seed rebuild can apply that generate-phase
-- ordering differently than an incrementally-maintained database: if
-- cleanup's orphan check ever observes a data_column set that has not yet
-- fully settled (a construction-order artifact, not a real orphan),
-- import_source_column rows for definitions that are otherwise entirely
-- correct get wrongly deleted (cascading to their import_mapping rows).
-- The fleet's real boxes are incrementally maintained and never take this
-- path, so they hold the correct state; a database built by replaying
-- every migration from scratch can end up missing rows the fleet has.
--
-- THE REPAIR IS PURELY RECONSTRUCTIVE, NEVER A DELETE. It calls
-- import.synchronize_definition_step_mappings(definition_id, step_code)
-- directly — the SAME procedure that creates these pairs correctly in the
-- first place (doc/db/function/import_synchronize_definition_step_mappings(integer, text).md)
-- — for every enabled, non-custom definition's relevant steps, rather than
-- hand-writing a second copy of its INSERT logic that could drift out of
-- sync with the real one. That procedure is already idempotent by
-- construction: `IF NOT FOUND` before creating a source_column, and
-- `ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO
-- NOTHING` for the mapping — it only fills gaps, never touches a row that
-- is already correct. Deliberately NOT calling
-- import.cleanup_orphaned_synced_mappings() here: that is the delete side
-- of the pair, and a repair migration's job is to move a replay TOWARD the
-- fleet's state, never to risk moving it further away.
--
-- DERIVATION VERIFIED, not assumed (STATBUS-312 ruling's required order):
-- synchronize_definition_step_mappings computes column_name via
-- regexp_replace(dc.column_name, '_raw$', ''), priority via sequential
-- max+1 in dc.priority order, and the mapping's four fields entirely from
-- the import_definition_step ⨝ import_data_column join — nothing else.
-- Checked both target tables' full schemas (doc/db/table/public_import_source_column.md,
-- public_import_mapping.md): neither carries any field beyond what this
-- derivation already accounts for, for the custom=FALSE population this
-- bug affects. So running it again can only ever reconstruct exactly what
-- should already be there — it cannot invent a mapping that was not the
-- system's own correct one.
--
-- IDEMPOTENT BY CONSTRUCTION: a settled database (every real box; an
-- incrementally-built seed) has nothing missing, so every call below is a
-- no-op. A database missing rows to this specific defect gets them back.
-- Safe to re-run.
--
-- WHY THIS IS REAL, NOT TEST-ONLY: install.sh's seed-restore path
-- documents a silent full-replay fallback when the cached seed artifact is
-- stale or absent — a fresh box taking that fallback builds exactly the
-- database this migration exists to correct, silently, with no test
-- suite to catch it. The durable rule this migration is also an instance
-- of: a migration's data operations must be expressed so the result does
-- not depend on its position in the replay sequence — this one is written
-- to hold regardless of what ran before it, by re-deriving from source
-- rather than trusting an intermediate state.

BEGIN;

DO $do$
DECLARE
    v_def RECORD;
BEGIN
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE enabled = TRUE AND custom = FALSE
    LOOP
        IF EXISTS (
            SELECT 1 FROM public.import_definition_step ids
            JOIN public.import_step s ON ids.step_id = s.id
            WHERE ids.definition_id = v_def.id AND s.code = 'external_idents'
        ) THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'external_idents');
        END IF;
        IF EXISTS (
            SELECT 1 FROM public.import_definition_step ids
            JOIN public.import_step s ON ids.step_id = s.id
            WHERE ids.definition_id = v_def.id AND s.code = 'link_establishment_to_legal_unit'
        ) THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'link_establishment_to_legal_unit');
        END IF;
        IF EXISTS (
            SELECT 1 FROM public.import_definition_step ids
            JOIN public.import_step s ON ids.step_id = s.id
            WHERE ids.definition_id = v_def.id AND s.code = 'statistical_variables'
        ) THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'statistical_variables');
        END IF;
    END LOOP;
END;
$do$;

COMMIT;
