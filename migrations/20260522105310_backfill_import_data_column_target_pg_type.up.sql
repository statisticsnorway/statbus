-- Migration: backfill_import_data_column_target_pg_type
--
-- Foundation for the import-length-truncate-warn campaign
-- (companion tasks: import-length-analyse-step, import-length-test).
--
-- Background:
--   public.import_data_column.target_pg_type stores the canonical
--   PostgreSQL type of the eventual target column in public.* (e.g.
--   character varying(200) for location.address_part1). The view
--   public.import_source_column_type reads it via
--   COALESCE(idc.target_pg_type, 'TEXT') and exposes it to the
--   PostgREST API. The new analyse_length_limits procedure (next task
--   in the campaign) reads target_pg_type to know each column's
--   bounded length — without it, the procedure can't tell a
--   varchar(200) target apart from an unbounded TEXT.
--
-- Pre-state on dev:
--   All 67 `internal`-purpose rows have target_pg_type IS NULL.
--   55 `source_input` rows have target_pg_type set (mostly 'TEXT'
--   from the existing generator INSERTs).
--
-- This migration:
--   1. Creates helper `import.resolve_target_pg_type(step_code, column_name)`
--      that maps step+column → public.<table>.<column> per the V5 recon
--      convention, then returns format_type(atttypid, atttypmod) for that
--      column (e.g. 'character varying(200)', 'integer', 'numeric(9,6)').
--      Returns NULL when no public.* mapping exists (purely-internal
--      computed values like enum-typed 'operation'/'action' or FK ids
--      that don't map to a same-named public column).
--
--   2. Updates `import.generate_external_ident_data_columns` and
--      `import.generate_stat_var_data_columns` so newly-created internal
--      rows inherit target_pg_type automatically (via COALESCE with
--      column_type fallback for purely-internal columns).
--
--   3. Backfills target_pg_type for all existing NULL `internal`-purpose
--      rows. Uses COALESCE(resolve_target_pg_type, column_type) so
--      purely-internal columns (no public.* mapping) fall back to the
--      same type they already use in the import _data table.
--
--   4. Hard-fails (RAISE EXCEPTION) if any `internal`-purpose row still
--      has NULL target_pg_type after the backfill — catches future
--      schema drift where a new generator emits internal columns the
--      helper doesn't yet handle.

BEGIN;

-- ─── Helper: import.resolve_target_pg_type ───────────────────────────────

CREATE OR REPLACE FUNCTION import.resolve_target_pg_type(
    p_step_code text,
    p_column_name text
) RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $resolve_target_pg_type$
DECLARE
    v_table_name text;
    v_column_name text;
    v_resolved_type text;
BEGIN
    -- Map (import_step.code, import_data_column.column_name) → the
    -- canonical PostgreSQL type string of the corresponding
    -- public.<table>.<column>, when such a mapping exists. Returns
    -- NULL for columns with no public.* counterpart (purely-internal
    -- import machinery like 'operation', 'action',
    -- 'primary_for_enterprise', or FK ids that resolve to *_id
    -- columns on the parent table).
    CASE
        WHEN p_step_code = 'physical_location' AND p_column_name LIKE 'physical_%' THEN
            v_table_name := 'location';
            v_column_name := substring(p_column_name from 10); -- strip 'physical_'
        WHEN p_step_code = 'postal_location' AND p_column_name LIKE 'postal_%' THEN
            v_table_name := 'location';
            v_column_name := substring(p_column_name from 8);  -- strip 'postal_'
        WHEN p_step_code = 'primary_activity' AND p_column_name LIKE 'primary_%' THEN
            v_table_name := 'activity';
            v_column_name := substring(p_column_name from 9);  -- strip 'primary_'
        WHEN p_step_code = 'secondary_activity' AND p_column_name LIKE 'secondary_%' THEN
            v_table_name := 'activity';
            v_column_name := substring(p_column_name from 11); -- strip 'secondary_'
        WHEN p_step_code IN ('legal_unit', 'establishment', 'contact',
                              'data_source', 'status', 'legal_relationship') THEN
            v_table_name := p_step_code;
            v_column_name := p_column_name;
        WHEN p_step_code = 'external_idents' THEN
            v_table_name := 'external_ident';
            v_column_name := p_column_name;
        WHEN p_step_code = 'tags' THEN
            v_table_name := 'tag';
            v_column_name := p_column_name;
        WHEN p_step_code = 'edit_info' AND p_column_name LIKE 'edit_%' THEN
            -- edit_* columns appear on every unit/sub-unit table with
            -- identical types (edit_comment varchar(512), edit_at
            -- timestamptz, edit_by_user_id integer). public.legal_unit
            -- is the canonical source.
            v_table_name := 'legal_unit';
            v_column_name := p_column_name;
        ELSE
            RETURN NULL;
    END CASE;

    SELECT format_type(a.atttypid, a.atttypmod)
    INTO v_resolved_type
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = v_table_name
      AND a.attname = v_column_name
      AND NOT a.attisdropped
      AND a.attnum > 0;

    RETURN v_resolved_type;
END;
$resolve_target_pg_type$;

COMMENT ON FUNCTION import.resolve_target_pg_type(text, text) IS
'Resolves (step_code, column_name) → canonical PostgreSQL type of the
corresponding public.<table>.<column>, when such a mapping exists per
the V5 recon convention. Used by import_data_column backfill +
generator procedures to keep target_pg_type in sync with the actual
target schema. Returns NULL for purely-internal import-machinery
columns (caller falls back to import_data_column.column_type).';


-- ─── Generator updates: emit target_pg_type on new internal rows ─────────

-- import.generate_external_ident_data_columns: the {code}_path LTREE
-- internal column previously omitted target_pg_type. Now sets it via
-- COALESCE(resolve_target_pg_type, 'LTREE') — resolve returns NULL
-- (no public.external_ident.path), falling back to 'LTREE'. Form
-- preserved so future schema additions flow through automatically.
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
 LANGUAGE plpgsql
AS $procedure$
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
            -- target_pg_type: LTREE is the in-data-table type; no public.external_ident.path
            -- exists, so resolve_target_pg_type returns NULL and we fall back to 'LTREE'.
            v_calculated_priority := v_slot_base + v_num_labels;

            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
            VALUES (v_step_id, v_ident_type.code || '_path', 'LTREE', 'internal', true, false, v_calculated_priority,
                    COALESCE(import.resolve_target_pg_type('external_idents', v_ident_type.code || '_path'), 'LTREE'))
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

            RAISE DEBUG '[import.generate_external_ident_data_columns] Hierarchical type "%": created/updated path column "%_path" with priority %',
                v_ident_type.code, v_ident_type.code, v_calculated_priority;
        END IF;
    END LOOP;
END;
$procedure$;


-- import.generate_stat_var_data_columns: internal typed columns
-- (employees, turnover, etc) now emit target_pg_type. No public.*
-- counterpart for stat values (they land in stat_for_unit.value_*),
-- so resolve_target_pg_type returns NULL and we fall back to the
-- same type the data table uses.
CREATE OR REPLACE PROCEDURE import.generate_stat_var_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_stat_def RECORD;
    v_def RECORD;
    v_pk_col_name TEXT;
    v_stat_def_code TEXT;
    v_calculated_priority INT;
    v_active_codes TEXT[];
    v_internal_column_type TEXT;
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

    -- Add internal typed columns for each active stat_definition.
    -- target_pg_type tracks column_type (no public.* counterpart for stat values).
    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 2;
        v_internal_column_type := CASE v_stat_def.type
            WHEN 'int' THEN 'INTEGER'
            WHEN 'float' THEN 'NUMERIC'
            WHEN 'bool' THEN 'BOOLEAN'
            ELSE 'TEXT'
        END;

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, v_stat_def.code, v_internal_column_type,
                'internal', true, false, v_calculated_priority,
                COALESCE(import.resolve_target_pg_type('statistical_variables', v_stat_def.code), v_internal_column_type))
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            column_type = EXCLUDED.column_type,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type
        WHERE public.import_data_column.priority != EXCLUDED.priority
           OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;
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
$procedure$;


-- ─── Backfill existing rows ──────────────────────────────────────────────

-- For every internal-purpose row with NULL target_pg_type, resolve via
-- the helper and COALESCE with the existing column_type so purely-
-- internal columns (no public.* mapping) end up with the same type
-- they already use in the import _data table.
UPDATE public.import_data_column idc
SET target_pg_type = COALESCE(
    import.resolve_target_pg_type(s.code, idc.column_name),
    idc.column_type
)
FROM public.import_step s
WHERE idc.step_id = s.id
  AND idc.purpose = 'internal'
  AND idc.target_pg_type IS NULL;


-- ─── Regression assertion: every internal row now has target_pg_type ─────

-- Catches a future class of bug where someone adds a new generator
-- emitting internal columns the helper doesn't yet handle. Without
-- this assertion, the new rows would silently inherit NULL
-- target_pg_type and the downstream analyse_length_limits procedure
-- (next task in the campaign) would silently skip them.
DO $assert_no_null_target_pg_type$
DECLARE
    v_missing_count integer;
    v_missing_sample text;
BEGIN
    SELECT count(*) INTO v_missing_count
    FROM public.import_data_column
    WHERE purpose = 'internal' AND target_pg_type IS NULL;

    IF v_missing_count > 0 THEN
        SELECT string_agg(s.code || '/' || idc.column_name, ', ' ORDER BY s.code, idc.column_name)
        INTO v_missing_sample
        FROM public.import_data_column idc
        JOIN public.import_step s ON s.id = idc.step_id
        WHERE idc.purpose = 'internal' AND idc.target_pg_type IS NULL
        LIMIT 10;

        RAISE EXCEPTION 'backfill_import_data_column_target_pg_type: % internal-purpose rows still have NULL target_pg_type after backfill. Sample: %. Extend import.resolve_target_pg_type to cover the new step+column.',
            v_missing_count, v_missing_sample;
    END IF;
END;
$assert_no_null_target_pg_type$;

END;
