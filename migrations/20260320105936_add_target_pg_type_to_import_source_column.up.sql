BEGIN;

-- Move target_pg_type from import_source_column to import_data_column.
-- The type information originates at import_data_column (source_input rows have
-- internal siblings whose column_type IS the target type). Setting it here
-- eliminates redundant derivation in every INSERT path.

-- 1. Add column (nullable, only meaningful for source_input rows)
ALTER TABLE public.import_data_column ADD COLUMN target_pg_type TEXT;

-- 2. Populate existing source_input rows from sibling internal columns
UPDATE public.import_data_column AS idc_raw
SET target_pg_type = COALESCE(idc_int.column_type, 'TEXT')
FROM public.import_data_column AS idc_int
WHERE idc_int.step_id = idc_raw.step_id
  AND idc_int.purpose = 'internal'
  AND idc_int.column_name = regexp_replace(idc_raw.column_name, '_raw$', '')
  AND idc_raw.purpose = 'source_input';

-- Remaining source_input without sibling (e.g., link columns, ident columns)
UPDATE public.import_data_column
SET target_pg_type = 'TEXT'
WHERE purpose = 'source_input' AND target_pg_type IS NULL;

-- 3a. Update generate_external_ident_data_columns to set target_pg_type on source_input INSERT
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
        FROM public.external_ident_type_enabled
        ORDER BY priority
    LOOP
        IF v_ident_type.shape = 'regular' THEN
            -- Regular identifier: single source_input column
            -- Formula: base_priority + 2 + type.priority
            v_calculated_priority := v_base_priority + 2 + v_ident_type.priority;

            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
            VALUES (v_step_id, v_ident_type.code || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority, 'TEXT')
            ON CONFLICT (step_id, column_name) DO UPDATE SET
                priority = EXCLUDED.priority,
                is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                column_type = EXCLUDED.column_type,
                purpose = EXCLUDED.purpose,
                target_pg_type = EXCLUDED.target_pg_type
            WHERE public.import_data_column.priority != EXCLUDED.priority
               OR public.import_data_column.column_type != EXCLUDED.column_type
               OR public.import_data_column.purpose != EXCLUDED.purpose
               OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;

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

                INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
                VALUES (v_step_id, v_ident_type.code || '_' || v_label || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority, 'TEXT')
                ON CONFLICT (step_id, column_name) DO UPDATE SET
                    priority = EXCLUDED.priority,
                    is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                    column_type = EXCLUDED.column_type,
                    purpose = EXCLUDED.purpose,
                    target_pg_type = EXCLUDED.target_pg_type
                WHERE public.import_data_column.priority != EXCLUDED.priority
                   OR public.import_data_column.column_type != EXCLUDED.column_type
                   OR public.import_data_column.purpose != EXCLUDED.purpose
                   OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;

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

-- 3b. Update generate_link_lu_data_columns to set target_pg_type on source_input INSERT
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

    -- Add source_input column for each active external_ident_type, prefixed with 'legal_unit_'
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_enabled ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_current_priority, 'TEXT')
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type;
    END LOOP;

    -- The 'legal_unit_id' pk_id column is statically defined in 20250505120000_import_populate_steps.up.sql
    -- and should not be managed by this dynamic lifecycle callback.
END;
$generate_link_lu_data_columns$;

-- 3c. Update generate_stat_var_data_columns to set target_pg_type on source_input INSERT
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

    -- For statistical_variables step, we generate 3 columns per stat_definition in sequence:
    -- Baseline expectations:
    -- employees (priority=1): _raw=1, internal=2, pk_id=3
    -- turnover (priority=2): _raw=4, internal=5, pk_id=6

    -- Add source_input columns with target_pg_type derived from the stat definition type
    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 1;

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, v_stat_def.code || '_raw', 'TEXT', 'source_input', true, false, v_calculated_priority,
                CASE v_stat_def.type
                    WHEN 'int' THEN 'INTEGER'
                    WHEN 'float' THEN 'NUMERIC'
                    WHEN 'bool' THEN 'BOOLEAN'
                    ELSE 'TEXT'
                END)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type
        WHERE public.import_data_column.priority != EXCLUDED.priority
           OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;
    END LOOP;

    -- Add internal typed columns for each active stat_definition
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
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
    END LOOP;

    -- Add pk_id columns for each active stat_definition
    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 3;
        v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_pk_col_name, 'INTEGER', 'pk_id', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
    END LOOP;
END;
$generate_stat_var_data_columns$;

-- 4. Create view joining source columns to their target_pg_type via mappings
CREATE VIEW public.import_source_column_type
WITH (security_invoker = on) AS
SELECT isc.definition_id, isc.column_name, isc.priority,
       COALESCE(idc.target_pg_type, 'TEXT') AS target_pg_type
FROM public.import_source_column AS isc
LEFT JOIN public.import_mapping AS im
  ON im.source_column_id = isc.id AND NOT im.is_ignored
LEFT JOIN public.import_data_column AS idc
  ON idc.id = im.target_data_column_id;

GRANT SELECT ON public.import_source_column_type TO authenticated, regular_user, admin_user;

-- 5. Drop the now-unnecessary function (replaced by the view)
DROP FUNCTION IF EXISTS public.import_definition_source_column_types(integer);

END;
