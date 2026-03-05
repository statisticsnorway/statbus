```sql
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
            -- An import_source_column is an orphan ONLY if it is dynamically generated AND its 
            -- corresponding `source_input` data column no longer exists.
            -- 
            -- Dynamically generated columns include:
            -- 1. Regular external_ident_type codes (e.g., 'tax_ident')
            -- 2. Hierarchical external_ident_type component columns (e.g., 'admin_statistical_region')
            -- 3. stat_definition codes
            -- 4. legal_unit prefixed external ident codes (e.g., 'legal_unit_tax_ident')
            
            v_data_column_exists := true; -- Assume not an orphan by default
            v_is_dynamic_column := false;
            
            -- Check if this is a dynamic column from external_ident_type (regular or hierarchical component)
            IF v_source_col.column_name IN (SELECT code FROM public.external_ident_type) THEN
                -- Regular external ident type code
                v_is_dynamic_column := true;
            ELSIF EXISTS (
                -- Hierarchical component column: matches pattern {code}_{label}
                -- where code is a hierarchical external_ident_type and label is one of its labels
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
                -- This is a dynamically managed source column. Check if its data column still exists.
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
