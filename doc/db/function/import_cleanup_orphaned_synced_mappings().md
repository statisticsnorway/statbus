```sql
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
$procedure$
```
