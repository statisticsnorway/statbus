-- Migration 20260422011930: fix cleanup_orphaned_synced_mappings for renamed/deleted external_ident_type and stat_definition
--
-- import.cleanup_orphaned_synced_mappings did not detect orphan
-- source_columns when an external_ident_type or stat_definition was
-- RENAMED or DELETED. The previous body decided whether a source_column
-- was eligible for cleanup by checking whether its name CURRENTLY
-- matched a known external_ident_type / stat_definition / hierarchical
-- component / legal_unit-prefixed code. After a rename/delete, the OLD
-- name no longer matched any of those — so v_is_dynamic_column became
-- false, the data-column existence check was skipped, the source_column
-- survived as a permanent orphan, and admin.validate_import_definition
-- rejected the definition with "Unused import_source_column".
--
-- Operator-visible failure (jo.statbus.org, 2026-04-22): definitions
-- 1–8 stuck at valid=false; UI showed "Error creating import job:
-- [object Object]" because the older app code didn't render the
-- PostgrestError properly (separately fixed in commit ea9dff870).
-- Test 108 currently codifies the buggy behavior — its expected
-- output shows "Removed import_source_column rows: (0 rows)" after a
-- DELETE of stat_ident; we update that expectation in the same commit.
--
-- The fix has two parts:
--
-- 1. Drop the dynamic-name detection gate in
--    cleanup_orphaned_synced_mappings. For non-custom definitions the
--    lifecycle is the SOLE creator of source_columns, so the canonical
--    orphan check is "no matching {column_name}_raw import_data_column
--    for one of this definition's steps". Apply that check
--    unconditionally.
--
-- 2. Make synchronize_default_definitions_all_steps call
--    cleanup_orphaned_synced_mappings() at the END. The original
--    lifecycle ordering ran cleanup_orphaned_synced_mappings as a
--    cleanup callback at priority 5 — meaning it fires FIRST in the
--    cleanup phase, BEFORE cleanup_stat_var_data_columns (priority 4)
--    has dropped the OLD data_column. So when our orphan check runs,
--    the soon-to-be-orphaned source_column still has its matching
--    `_raw` data column, and is incorrectly judged "not orphan".
--    Calling cleanup_orphaned_synced_mappings() at the end of the
--    GENERATE phase (priority 5, runs LAST) makes it see the
--    settled state.

BEGIN;

CREATE OR REPLACE PROCEDURE import.cleanup_orphaned_synced_mappings()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_def RECORD;
    v_source_col RECORD;
    v_data_column_exists BOOLEAN;
BEGIN
    RAISE DEBUG '--> Running import.cleanup_orphaned_synced_mappings...';
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE enabled = TRUE AND custom = FALSE
    LOOP
        RAISE DEBUG '  [-] Checking definition ID: % for orphaned synced mappings.', v_def.id;
        FOR v_source_col IN
            SELECT isc.id AS source_column_id, isc.column_name
            FROM public.import_source_column isc
            WHERE isc.definition_id = v_def.id
        LOOP
            -- Canonical orphan check: every legitimate source_column on a
            -- non-custom definition has a sibling `{name}_raw` data column
            -- under one of the definition's steps (the lifecycle creates
            -- the pair atomically via import.synchronize_definition_step_mappings).
            -- Absence of the matching data_column => orphan, regardless of
            -- whether the source_column's name still matches a CURRENT
            -- external_ident_type/stat_definition code (it doesn't after
            -- rename/delete — that's the bug this migration fixes).
            SELECT EXISTS (
                SELECT 1
                FROM public.import_definition_step ids
                JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                WHERE ids.definition_id = v_def.id
                  AND idc.column_name = v_source_col.column_name || '_raw'
                  AND idc.purpose = 'source_input'
            ) INTO v_data_column_exists;

            IF NOT v_data_column_exists THEN
                RAISE DEBUG '    - Deleting orphaned source column ID % (name: "%") and its mappings for definition ID %.',
                            v_source_col.source_column_id, v_source_col.column_name, v_def.id;
                DELETE FROM public.import_source_column WHERE id = v_source_col.source_column_id; -- Cascades to import_mapping
            END IF;
        END LOOP;
        -- Re-validate the definition after potential cleanup
        PERFORM admin.validate_import_definition(v_def.id);
    END LOOP;
    RAISE DEBUG 'Finished import.cleanup_orphaned_synced_mappings.';
END;
$procedure$;

-- Part 2: synchronize_default_definitions_all_steps now invokes
-- cleanup_orphaned_synced_mappings at the end so orphan removal runs
-- AFTER all data_column generators have settled the canonical state.
CREATE OR REPLACE PROCEDURE import.synchronize_default_definitions_all_steps()
LANGUAGE plpgsql AS $synchronize_default_definitions_all_steps$
DECLARE
    v_def RECORD;
BEGIN
    RAISE DEBUG '--> Running import.synchronize_default_definitions_all_steps...';
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE enabled = TRUE AND custom = FALSE
    LOOP
        RAISE DEBUG '  [-] Synchronizing definition ID: %', v_def.id;
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'external_idents') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'external_idents');
        END IF;
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'link_establishment_to_legal_unit') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'link_establishment_to_legal_unit');
        END IF;
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'statistical_variables') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'statistical_variables');
        END IF;
    END LOOP;
    -- Settled: now strip any source_columns whose `_raw` data_column was
    -- deleted by an earlier cleanup-phase callback (rename/delete of an
    -- external_ident_type or stat_definition). Without this call the
    -- orphan would survive — see migration header for full reasoning.
    CALL import.cleanup_orphaned_synced_mappings();
    RAISE DEBUG 'Finished import.synchronize_default_definitions_all_steps.';
END;
$synchronize_default_definitions_all_steps$;

END;
