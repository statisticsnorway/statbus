BEGIN;

-- 1. Drop the view
DROP VIEW IF EXISTS public.import_source_column_type;

-- 2. Restore the original function
CREATE OR REPLACE FUNCTION public.import_definition_source_column_types(p_definition_id integer)
RETURNS TABLE(column_name text, column_type text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $import_definition_source_column_types$
  SELECT isc.column_name, COALESCE(idc_int.column_type, 'TEXT') AS column_type
  FROM import_source_column AS isc
  JOIN import_mapping AS im ON im.source_column_id = isc.id AND NOT im.is_ignored
  JOIN import_data_column AS idc_raw ON idc_raw.id = im.target_data_column_id
  LEFT JOIN import_data_column AS idc_int
    ON idc_int.step_id = idc_raw.step_id
    AND idc_int.purpose = 'internal'
    AND idc_int.column_name = replace(idc_raw.column_name, '_raw', '')
  WHERE isc.definition_id = p_definition_id
  ORDER BY isc.priority;
$import_definition_source_column_types$;

-- 3a. Restore original generate_external_ident_data_columns (without target_pg_type)
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

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_enabled;
    RAISE DEBUG '[import.generate_external_ident_data_columns] For step_id % (external_idents), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_base_priority
    FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose NOT IN ('source_input', 'internal');

    FOR v_ident_type IN
        SELECT code, priority, shape, labels
        FROM public.external_ident_type_enabled
        ORDER BY priority
    LOOP
        IF v_ident_type.shape = 'regular' THEN
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
            v_labels_array := string_to_array(ltree2text(v_ident_type.labels), '.');
            v_num_labels := array_length(v_labels_array, 1);

            IF v_num_labels IS NULL OR v_num_labels = 0 THEN
                RAISE WARNING '[import.generate_external_ident_data_columns] Hierarchical type "%" has no labels, skipping', v_ident_type.code;
                CONTINUE;
            END IF;

            v_slot_base := v_base_priority + 2 + v_ident_type.priority * 11;

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

-- 3b. Restore original generate_link_lu_data_columns (without target_pg_type)
CREATE OR REPLACE PROCEDURE import.generate_link_lu_data_columns()
LANGUAGE plpgsql AS $generate_link_lu_data_columns$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_current_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_enabled;
    RAISE DEBUG '[import.generate_link_lu_data_columns] For step_id % (link_establishment_to_legal_unit), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
    FROM public.import_data_column idc WHERE idc.step_id = v_step_id;

    FOR v_ident_type IN SELECT code FROM public.external_ident_type_enabled ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_current_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying;
    END LOOP;
END;
$generate_link_lu_data_columns$;

-- 3c. Restore original generate_stat_var_data_columns (without target_pg_type)
CREATE OR REPLACE PROCEDURE import.generate_stat_var_data_columns()
LANGUAGE plpgsql AS $generate_stat_var_data_columns$
DECLARE
    v_step_id INT;
    v_stat_def RECORD;
    v_def RECORD;
    v_pk_col_name TEXT;
    v_stat_def_code TEXT;
    v_calculated_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'statistical_variables step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.stat_definition_enabled;
    RAISE DEBUG '[import.generate_stat_var_data_columns] For step_id % (statistical_variables), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 1;

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_stat_def.code || '_raw', 'TEXT', 'source_input', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;
    END LOOP;

    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 2;

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_stat_def.code,
                CASE v_stat_def.type
                    WHEN 'int' THEN 'INTEGER'
                    WHEN 'float' THEN 'NUMERIC'
                    WHEN 'bool' THEN 'BOOLEAN'
                    ELSE 'TEXT'
                END,
                'internal', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            column_type = EXCLUDED.column_type,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;
    END LOOP;

    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 3;
        v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_pk_col_name, 'INTEGER', 'pk_id', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;
    END LOOP;
END;
$generate_stat_var_data_columns$;

-- 4. Drop the column
ALTER TABLE public.import_data_column DROP COLUMN target_pg_type;

END;
