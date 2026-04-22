-- Down Migration 20260422011930: restore the prior import.cleanup_orphaned_synced_mappings
--
-- Reintroduces the dynamic-name detection gate that misses orphan
-- source_columns whose parent code was renamed or deleted. The body is
-- the verbatim version shipped in
-- 20250507000000_import_generate_default_definitions.up.sql lines 107-184.

BEGIN;

CREATE OR REPLACE PROCEDURE import.cleanup_orphaned_synced_mappings()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_def RECORD;
    v_source_col RECORD;
    v_data_column_exists BOOLEAN;
    v_is_dynamic_column BOOLEAN;
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
            v_data_column_exists := true;
            v_is_dynamic_column := false;

            IF v_source_col.column_name IN (SELECT code FROM public.external_ident_type) THEN
                v_is_dynamic_column := true;
            ELSIF EXISTS (
                SELECT 1
                FROM public.external_ident_type eit
                WHERE eit.shape = 'hierarchical'
                  AND eit.labels IS NOT NULL
                  AND v_source_col.column_name LIKE eit.code || '_%'
                  AND substring(v_source_col.column_name FROM length(eit.code) + 2) = ANY(
                      string_to_array(ltree2text(eit.labels), '.')
                  )
            ) THEN
                v_is_dynamic_column := true;
            ELSIF v_source_col.column_name IN (SELECT code FROM public.stat_definition) THEN
                v_is_dynamic_column := true;
            ELSIF v_source_col.column_name LIKE 'legal_unit_%' AND
                  replace(v_source_col.column_name, 'legal_unit_', '') IN (SELECT code FROM public.external_ident_type) THEN
                v_is_dynamic_column := true;
            END IF;

            IF v_is_dynamic_column THEN
                SELECT EXISTS (
                    SELECT 1
                    FROM public.import_definition_step ids
                    JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                    WHERE ids.definition_id = v_def.id
                      AND idc.column_name = v_source_col.column_name || '_raw'
                      AND idc.purpose = 'source_input'
                ) INTO v_data_column_exists;
            END IF;

            IF NOT v_data_column_exists THEN
                RAISE DEBUG '    - Deleting orphaned source column ID % (name: "%") and its mappings for definition ID %.',
                            v_source_col.source_column_id, v_source_col.column_name, v_def.id;
                DELETE FROM public.import_source_column WHERE id = v_source_col.source_column_id;
            END IF;
        END LOOP;
        PERFORM admin.validate_import_definition(v_def.id);
    END LOOP;
    RAISE DEBUG 'Finished import.cleanup_orphaned_synced_mappings.';
END;
$procedure$;

-- Restore the prior import.synchronize_default_definitions_all_steps
-- (without the trailing cleanup_orphaned_synced_mappings call). Body
-- as shipped in 20250507000000_import_generate_default_definitions.up.sql.
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
    RAISE DEBUG 'Finished import.synchronize_default_definitions_all_steps.';
END;
$synchronize_default_definitions_all_steps$;

END;
