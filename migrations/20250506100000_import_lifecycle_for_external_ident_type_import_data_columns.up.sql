BEGIN;

-- Lifecycle callback procedures for external_ident data columns
-- Supports both regular (single column) and hierarchical (multiple component columns + path) identifier types
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
LANGUAGE plpgsql AS $generate_external_ident_data_columns$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_base_priority INT;
    v_active_codes TEXT[];
    v_calculated_priority INT;
    v_slot_base INT;
    v_label TEXT;
    v_label_index INT;
    v_num_labels INT;
    v_labels_array TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_active;
    RAISE DEBUG '[import.generate_external_ident_data_columns] For step_id % (external_idents), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    -- Get the highest priority among non-dynamic columns (those without purpose='source_input' and 'internal')
    -- For external_idents step, this should be 4 (from establishment_id)
    SELECT COALESCE(MAX(idc.priority), 0) INTO v_base_priority
    FROM public.import_data_column idc 
    WHERE idc.step_id = v_step_id 
      AND idc.purpose NOT IN ('source_input', 'internal');

    -- Generate data columns for each active external_ident_type
    -- Regular types: single {code}_raw column
    -- Hierarchical types: {code}_{label}_raw columns + {code}_path internal column
    FOR v_ident_type IN 
        SELECT code, priority, shape, labels 
        FROM public.external_ident_type_active 
        ORDER BY priority
    LOOP
        IF v_ident_type.shape = 'regular' THEN
            -- Regular identifier: single source_input column
            -- Formula: base_priority + 2 + type.priority
            v_calculated_priority := v_base_priority + 2 + v_ident_type.priority;
            
            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
            VALUES (v_step_id, v_ident_type.code || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority)
            ON CONFLICT (step_id, column_name) DO UPDATE SET
                priority = EXCLUDED.priority,
                is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                column_type = EXCLUDED.column_type,
                purpose = EXCLUDED.purpose
            WHERE public.import_data_column.priority != EXCLUDED.priority
               OR public.import_data_column.column_type != EXCLUDED.column_type
               OR public.import_data_column.purpose != EXCLUDED.purpose;
            
            RAISE DEBUG '[import.generate_external_ident_data_columns] Regular type "%": created/updated column "%_raw" with priority %', 
                v_ident_type.code, v_ident_type.code, v_calculated_priority;

        ELSIF v_ident_type.shape = 'hierarchical' THEN
            -- Hierarchical identifier: multiple component columns + path column
            -- Parse labels into array: 'region.district.unit' -> ['region', 'district', 'unit']
            v_labels_array := string_to_array(ltree2text(v_ident_type.labels), '.');
            v_num_labels := array_length(v_labels_array, 1);
            
            IF v_num_labels IS NULL OR v_num_labels = 0 THEN
                RAISE WARNING '[import.generate_external_ident_data_columns] Hierarchical type "%" has no labels, skipping', v_ident_type.code;
                CONTINUE;
            END IF;
            
            -- Calculate slot base priority to avoid collisions
            -- Formula: base_priority + 2 + type.priority * (max_labels + 1)
            -- Using max_labels = 10 as reasonable upper bound for hierarchical depth
            v_slot_base := v_base_priority + 2 + v_ident_type.priority * 11;
            
            -- Generate source_input column for each label component
            v_label_index := 0;
            FOREACH v_label IN ARRAY v_labels_array
            LOOP
                v_calculated_priority := v_slot_base + v_label_index;
                
                INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
                VALUES (v_step_id, v_ident_type.code || '_' || v_label || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority)
                ON CONFLICT (step_id, column_name) DO UPDATE SET
                    priority = EXCLUDED.priority,
                    is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                    column_type = EXCLUDED.column_type,
                    purpose = EXCLUDED.purpose
                WHERE public.import_data_column.priority != EXCLUDED.priority
                   OR public.import_data_column.column_type != EXCLUDED.column_type
                   OR public.import_data_column.purpose != EXCLUDED.purpose;
                
                RAISE DEBUG '[import.generate_external_ident_data_columns] Hierarchical type "%": created/updated column "%_%_raw" with priority %', 
                    v_ident_type.code, v_ident_type.code, v_label, v_calculated_priority;
                
                v_label_index := v_label_index + 1;
            END LOOP;
            
            -- Generate internal path column (computed during analysis)
            -- Note: is_uniquely_identifying must be FALSE for internal columns (constraint requirement)
            v_calculated_priority := v_slot_base + v_num_labels;
            
            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
            VALUES (v_step_id, v_ident_type.code || '_path', 'LTREE', 'internal', true, false, v_calculated_priority)
            ON CONFLICT (step_id, column_name) DO UPDATE SET
                priority = EXCLUDED.priority,
                is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                column_type = EXCLUDED.column_type,
                purpose = EXCLUDED.purpose
            WHERE public.import_data_column.priority != EXCLUDED.priority
               OR public.import_data_column.column_type != EXCLUDED.column_type
               OR public.import_data_column.purpose != EXCLUDED.purpose;
            
            RAISE DEBUG '[import.generate_external_ident_data_columns] Hierarchical type "%": created/updated path column "%_path" with priority %', 
                v_ident_type.code, v_ident_type.code, v_calculated_priority;
        END IF;
    END LOOP;
END;
$generate_external_ident_data_columns$;

CREATE OR REPLACE PROCEDURE import.cleanup_external_ident_data_columns()
LANGUAGE plpgsql AS $cleanup_external_ident_data_columns$
DECLARE
    v_step_id INT;
    v_active_column_names TEXT[];
    v_ident_type RECORD;
    v_labels_array TEXT[];
    v_label TEXT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'external_idents step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_external_ident_data_columns] For step_id % (external_idents), cleaning up orphaned columns.', v_step_id;

    -- Build list of column names that should exist based on active types
    v_active_column_names := ARRAY[]::TEXT[];
    
    FOR v_ident_type IN 
        SELECT code, shape, labels 
        FROM public.external_ident_type_active
    LOOP
        IF v_ident_type.shape = 'regular' THEN
            -- Regular: single {code}_raw column
            v_active_column_names := v_active_column_names || (v_ident_type.code || '_raw');
        ELSIF v_ident_type.shape = 'hierarchical' THEN
            -- Hierarchical: {code}_{label}_raw columns + {code}_path
            v_labels_array := string_to_array(ltree2text(v_ident_type.labels), '.');
            FOREACH v_label IN ARRAY v_labels_array
            LOOP
                v_active_column_names := v_active_column_names || (v_ident_type.code || '_' || v_label || '_raw');
            END LOOP;
            v_active_column_names := v_active_column_names || (v_ident_type.code || '_path');
        END IF;
    END LOOP;
    
    RAISE DEBUG '[import.cleanup_external_ident_data_columns] Active column names to preserve: %', v_active_column_names;

    -- Delete dynamically generated columns (source_input or internal) that are no longer needed
    -- A column is dynamically generated if it ends with '_raw' or '_path'
    DELETE FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose IN ('source_input', 'internal')
      AND (idc.column_name LIKE '%_raw' OR idc.column_name LIKE '%_path')
      AND idc.column_name != ALL(v_active_column_names);
END;
$cleanup_external_ident_data_columns$;

-- Register the lifecycle callback
CALL lifecycle_callbacks.add(
    'import_external_ident_data_columns',
    ARRAY['public.external_ident_type']::regclass[],
    'import.generate_external_ident_data_columns',
    'import.cleanup_external_ident_data_columns'
);

-- Initial call to populate columns based on existing types
CALL import.generate_external_ident_data_columns();

END;
