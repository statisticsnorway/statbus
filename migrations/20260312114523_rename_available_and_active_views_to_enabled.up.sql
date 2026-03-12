BEGIN;

-- ============================================================================
-- Migration D: Rename all _available and _active views to _enabled
--
-- Standardizes classification view naming across the entire codebase:
--   _available → _enabled (auto-generated batch API views)
--   _active    → _enabled (manually created views)
--
-- Must happen BEFORE first production deployment to avoid rework.
-- ============================================================================

-- ============================================================================
-- 1. Drop all auto-generated batch API views (they depend on the enum value)
--    Order: custom/system depend on available, available depends on ordered
-- ============================================================================
SELECT admin.drop_table_views_for_batch_api('public.sector');
SELECT admin.drop_table_views_for_batch_api('public.legal_form');
SELECT admin.drop_table_views_for_batch_api('public.legal_reorg_type');
SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');
SELECT admin.drop_table_views_for_batch_api('public.data_source');
SELECT admin.drop_table_views_for_batch_api('public.unit_size');
SELECT admin.drop_table_views_for_batch_api('public.person_role');
SELECT admin.drop_table_views_for_batch_api('public.power_group_type');
SELECT admin.drop_table_views_for_batch_api('public.legal_rel_type');

-- ============================================================================
-- 2. Rename enum value 'available' → 'enabled'
-- ============================================================================
ALTER TYPE admin.view_type_enum RENAME VALUE 'available' TO 'enabled';

-- ============================================================================
-- 3. Update admin.generate_view to reference '_enabled' for system/custom bases
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.generate_view(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regclass AS $generate_view$
DECLARE
    view_sql text;
    view_name_str text;
    view_name regclass;
    from_str text;
    where_clause_str text := '';
    order_clause_str text := '';
    columns text[] := ARRAY[]::text[];
    columns_str text;
BEGIN
    -- Construct the view name
    view_name_str := table_properties.table_name || '_' || view_type::text;

    -- Determine where clause and ordering logic based on view type and table properties
    CASE view_type
    WHEN 'ordered' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name);
        IF table_properties.has_priority AND table_properties.has_code THEN
            order_clause_str := 'ORDER BY priority ASC NULLS LAST, code ASC';
        ELSIF table_properties.has_path THEN
            order_clause_str := 'ORDER BY path ASC';
        ELSIF table_properties.has_code THEN
            order_clause_str := 'ORDER BY code ASC';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'enabled' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_ordered');
        IF table_properties.has_enabled THEN
            where_clause_str := 'WHERE enabled';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'system' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_enabled');
        where_clause_str := 'WHERE custom = false';
    WHEN 'custom' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_enabled');
        where_clause_str := 'WHERE custom = true';
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END CASE;


    IF columns_str IS NULL THEN
      -- Add relevant columns based on table properties
      IF table_properties.has_path THEN
          columns := array_append(columns, 'path');
      ELSEIF table_properties.has_code THEN
          columns := array_append(columns, 'code');
      END IF;

      -- Always include 'name'
      columns := array_append(columns, 'name');

      IF table_properties.has_priority THEN
          columns := array_append(columns, 'priority');
      END IF;

      IF table_properties.has_description THEN
          columns := array_append(columns, 'description');
      END IF;

      -- Combine columns into a comma-separated string for SQL query
      columns_str := array_to_string(columns, ', ');
    END IF;

    -- Construct the SQL statement for the view
    view_sql := format($view$
CREATE VIEW public.%1$I WITH (security_invoker=on) AS
SELECT %2$s
FROM %3$s
%4$s
%5$s
$view$
    , view_name_str                -- %1$
    , columns_str                  -- %2$
    , from_str                     -- %3$
    , where_clause_str             -- %4$
    , order_clause_str             -- %5$
    );

    EXECUTE view_sql;

    view_name := format('public.%I', view_name_str)::regclass;
    RAISE NOTICE 'Created view: %', view_name;

    RETURN view_name;
END;
$generate_view$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. Update admin.drop_table_views_for_batch_api to use '_enabled'
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.drop_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    view_name_ordered text;
    view_name_enabled text;
    view_name_system text;
    view_name_custom text;
    upsert_function_name_system text;
    upsert_function_name_custom text;
    prepare_function_name_custom text;
BEGIN
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view and function names
    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_enabled := schema_name_str || '.' || table_name_str || '_enabled';
    view_name_ordered := schema_name_str || '.' || table_name_str || '_ordered';

    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';

    prepare_function_name_custom := 'admin.prepare_' || table_name_str || '_custom';

    -- Drop views
    EXECUTE 'DROP VIEW ' || view_name_custom;
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_enabled;
    EXECUTE 'DROP VIEW ' || view_name_ordered;

    -- Drop functions
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_custom || '()';

    EXECUTE 'DROP FUNCTION ' || prepare_function_name_custom || '()';

    -- Get unique columns and construct index name using same logic as in generate_active_code_custom_unique_constraint
    DECLARE
        table_properties admin.batch_api_table_properties;
        unique_columns text[];
        index_name text;
    BEGIN
        table_properties := admin.detect_batch_api_table_properties(table_name);
        unique_columns := admin.get_unique_columns(table_properties);

        -- Only attempt to drop if we have unique columns
        IF array_length(unique_columns, 1) IS NOT NULL THEN
            index_name := 'ix_' || table_name_str || '_' || array_to_string(unique_columns, '_');
            EXECUTE format('DROP INDEX IF EXISTS %I', index_name);
        END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. Update admin.generate_table_views_for_batch_api to use 'enabled'
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    table_properties admin.batch_api_table_properties;
    view_name_ordered regclass;
    view_name_enabled regclass;
    view_name_system regclass;
    view_name_custom regclass;
    upsert_function_name_system regprocedure;
    upsert_function_name_custom regprocedure;
    prepare_function_name_custom regprocedure;
    triggers_name_system text[];
    triggers_name_custom text[];
BEGIN
    table_properties := admin.detect_batch_api_table_properties(table_name);

    view_name_ordered := admin.generate_view(table_properties, 'ordered');
    view_name_enabled := admin.generate_view(table_properties, 'enabled');
    view_name_system := admin.generate_view(table_properties, 'system');
    view_name_custom := admin.generate_view(table_properties, 'custom');

    PERFORM admin.generate_active_code_custom_unique_constraint(table_properties);

    -- Determine the upsert function names based on table properties
    IF table_properties.has_path THEN
        upsert_function_name_system := admin.generate_path_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_path_upsert_function(table_properties, 'custom');
    ELSIF table_properties.has_code THEN
        upsert_function_name_system := admin.generate_code_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_code_upsert_function(table_properties, 'custom');
    ELSE
        RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
    END IF;

    -- Generate prepare functions
    prepare_function_name_custom := admin.generate_prepare_function_for_custom(table_properties);

    -- Generate view triggers
    triggers_name_system := admin.generate_view_triggers(view_name_system, upsert_function_name_system, NULL);
    triggers_name_custom := admin.generate_view_triggers(view_name_custom, upsert_function_name_custom, prepare_function_name_custom);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. Regenerate all 9 batch API view sets with new _enabled naming
-- ============================================================================
SELECT admin.generate_table_views_for_batch_api('public.sector');
SELECT admin.generate_table_views_for_batch_api('public.legal_form');
SELECT admin.generate_table_views_for_batch_api('public.legal_reorg_type');
SELECT admin.generate_table_views_for_batch_api('public.foreign_participation');
SELECT admin.generate_table_views_for_batch_api('public.data_source');
SELECT admin.generate_table_views_for_batch_api('public.unit_size');
SELECT admin.generate_table_views_for_batch_api('public.person_role');
SELECT admin.generate_table_views_for_batch_api('public.power_group_type');
SELECT admin.generate_table_views_for_batch_api('public.legal_rel_type');

-- ============================================================================
-- 7. Generate views for status (was missing entirely)
-- ============================================================================
SELECT admin.generate_table_views_for_batch_api('public.status');

-- ============================================================================
-- 8. Rename manual views: activity_category_available → activity_category_enabled
-- ============================================================================

-- Drop triggers first (they reference the old view names)
DROP TRIGGER activity_category_available_custom_upsert_custom ON public.activity_category_available_custom;
DROP TRIGGER activity_category_available_upsert_custom ON public.activity_category_available;

-- Rename views
ALTER VIEW public.activity_category_available RENAME TO activity_category_enabled;
ALTER VIEW public.activity_category_available_custom RENAME TO activity_category_enabled_custom;

-- Rename trigger functions
ALTER FUNCTION admin.activity_category_available_upsert_custom() RENAME TO activity_category_enabled_upsert_custom;
ALTER FUNCTION admin.activity_category_available_custom_upsert_custom() RENAME TO activity_category_enabled_custom_upsert_custom;

-- Re-create triggers with new names on renamed views
CREATE TRIGGER activity_category_enabled_upsert_custom
INSTEAD OF INSERT ON public.activity_category_enabled
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_enabled_upsert_custom();

CREATE TRIGGER activity_category_enabled_custom_upsert_custom
INSTEAD OF INSERT ON public.activity_category_enabled_custom
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_enabled_custom_upsert_custom();

-- ============================================================================
-- 9. Rename manual views: _active → _enabled
-- ============================================================================

-- external_ident_type_active → external_ident_type_enabled
ALTER VIEW public.external_ident_type_active RENAME TO external_ident_type_enabled;

-- stat_definition_active → stat_definition_enabled
ALTER VIEW public.stat_definition_active RENAME TO stat_definition_enabled;

-- ============================================================================
-- 10. Update import procedures that reference old view names
-- ============================================================================

-- 10a. import.analyse_data_source: data_source_available → data_source_enabled
CREATE OR REPLACE PROCEDURE import.analyse_data_source(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_data_source$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT;
    v_skipped_update_count INT;
BEGIN
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Starting analysis for batch_seq %.', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    v_sql := format($SQL$
        WITH
        batch_data AS (
            SELECT dt.row_id, dt.data_source_code_raw AS data_source_code
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1 AND dt.action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT data_source_code AS code
            FROM batch_data
            WHERE NULLIF(data_source_code, '') IS NOT NULL
            GROUP BY 1
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                ds.id as resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.data_source_enabled ds ON ds.code = dc.code
        ),
        lookups AS (
            SELECT
                bd.row_id,
                rc.resolved_id as resolved_data_source_id
            FROM batch_data bd
            LEFT JOIN resolved_codes rc ON bd.data_source_code = rc.code
        )
        UPDATE public.%1$I dt SET
            data_source_id = COALESCE(l.resolved_data_source_id, dt.data_source_id), -- Only update if resolved, don't nullify
            invalid_codes = jsonb_strip_nulls(
                (COALESCE(dt.invalid_codes, '{}'::jsonb) - 'data_source_code_raw') ||
                jsonb_build_object('data_source_code_raw',
                    CASE
                        WHEN NULLIF(dt.data_source_code_raw, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code_raw
                        ELSE NULL
                    END
                )
            ),
            last_completed_priority = %2$L
        FROM lookups l
        WHERE dt.row_id = l.row_id;
    $SQL$, v_job.data_table_name, v_step.priority);

    RAISE DEBUG '[Job %] analyse_data_source (Batch): Updating non-skipped rows with SQL: %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_data_source (Batch): Updated % non-skipped rows.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_data_source: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_data_source_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%I dt SET last_completed_priority = %s WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %s', v_job.data_table_name, v_step.priority, v_step.priority);
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;
END;
$analyse_data_source$;

-- 10b. import.analyse_legal_unit: legal_form_available, sector_available, unit_size_available → _enabled
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_data_table_name TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'legal_unit'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw']; -- Keys that go into invalid_codes
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id; END IF;

    v_sql := format($$
        UPDATE %1$I dt SET
            action = 'skip'::public.import_row_action_type,
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip'
          AND NULLIF(dt.name_raw, '') IS NULL
          AND NULLIF(dt.legal_form_code_raw, '') IS NULL
          AND NULLIF(dt.sector_code_raw, '') IS NULL
          AND NULLIF(dt.unit_size_code_raw, '') IS NULL
          AND NULLIF(dt.birth_date_raw, '') IS NULL
          AND NULLIF(dt.death_date_raw, '') IS NULL
          AND dt.status_id IS NULL; -- status_id is resolved from status_code_raw in a prior step
    $$, v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, dt.legal_unit_id,
               dt.legal_form_code_raw, dt.sector_code_raw, dt.unit_size_code_raw,
               dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT legal_form_code_raw AS code, 'legal_form' AS type FROM t_batch_data WHERE NULLIF(legal_form_code_raw, '') IS NOT NULL
        UNION SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(lf.id, s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.legal_form_enabled lf ON dc.type = 'legal_form' AND dc.code = lf.code
    LEFT JOIN public.sector_enabled s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_enabled us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id, bd.legal_unit_id,
                bd.legal_form_code_raw as legal_form_code,
                bd.sector_code_raw as sector_code,
                bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date,
                bd.death_date_raw as death_date,
                lf.resolved_id as resolved_legal_form_id,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes lf ON bd.legal_form_code_raw = lf.code AND lf.type = 'legal_form'
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            legal_form_id = l.resolved_legal_form_id,
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name for legal unit.')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %3$L::TEXT[]) ||
                                     jsonb_build_object('legal_form_code_raw', CASE WHEN NULLIF(l.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN l.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_invalid_code_keys_arr       -- %3$L
    );

    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Updating batch data with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_unit_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_legal_unit: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_legal_unit: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_legal_unit: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_legal_unit');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary_for_enterprise conflicts (best-effort)
    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary_for_enterprise conflicts within the batch in %s.', p_job_id, v_data_table_name;
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT
                    src.row_id,
                    FIRST_VALUE(src.row_id) OVER (
                        PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)')
                        ORDER BY src.legal_unit_id ASC NULLS LAST, src.row_id ASC
                    ) as winner_row_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.primary_for_enterprise = true
                  AND src.enterprise_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET primary_for_enterprise = false
            FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id
              AND dt.row_id != bp.winner_row_id
              AND dt.primary_for_enterprise = true;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary conflicts with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch.', p_job_id;
END;
$analyse_legal_unit$;

-- 10c. import.analyse_establishment: sector_available, unit_size_available → _enabled
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'establishment'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id; END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, establishment_id,
               dt.sector_code_raw, dt.unit_size_code_raw, dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.sector_enabled s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_enabled us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id, bd.establishment_id,
                bd.sector_code_raw as sector_code, bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date, bd.death_date_raw as death_date,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %3$L::TEXT[]) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,            -- %1$I
        v_error_keys_to_clear_arr,    -- %2$L
        v_invalid_code_keys_arr       -- %3$L
    );

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_establishment_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_establishment: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_establishment: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_establishment: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_establishment');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary conflicts (best-effort)
    BEGIN
        IF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_formal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.legal_unit_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_legal_unit = true AND src.legal_unit_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_legal_unit = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_legal_unit = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        ELSIF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_informal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_enterprise = true AND src.enterprise_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_enterprise = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_enterprise = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;

-- 10d. import.analyse_activity: activity_category_available → activity_category_enabled
CREATE OR REPLACE PROCEDURE import.analyse_activity(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_activity$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[];
    v_job_mode public.import_mode;
    v_source_code_col_name TEXT;
    v_resolved_id_col_name_in_lookup_cte TEXT;
    v_json_key TEXT;
    v_lookup_failed_condition_sql TEXT;
    v_error_json_expr_sql TEXT;
    v_invalid_code_json_expr_sql TEXT;
    v_parent_unit_missing_error_key TEXT;
    v_parent_unit_missing_error_message TEXT;
    v_prelim_update_count INT := 0;
    v_parent_id_check_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch) for step_code %: Starting analysis for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Get the specific step details using p_step_code from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_activity: Step with code % not found in snapshot. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Determine column names and JSON key based on the step being processed
    IF p_step_code = 'primary_activity' THEN
        v_source_code_col_name := 'primary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_primary_activity_category_id';
        v_json_key := 'primary_activity_category_code_raw';
    ELSIF p_step_code = 'secondary_activity' THEN
        v_source_code_col_name := 'secondary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_secondary_activity_category_id';
        v_json_key := 'secondary_activity_category_code_raw';
    ELSE
        RAISE EXCEPTION '[Job %] analyse_activity: Invalid p_step_code provided: %. Expected ''primary_activity'' or ''secondary_activity''.', p_job_id, p_step_code;
    END IF;
    v_error_keys_to_clear_arr := ARRAY[v_json_key];

    -- SQL condition string for when the lookup for the current activity type fails
    v_lookup_failed_condition_sql := format('dt.%1$I IS NOT NULL AND l.%2$I IS NULL', v_source_code_col_name, v_resolved_id_col_name_in_lookup_cte);

    -- SQL expression string for constructing the error JSON object for the current activity type
    v_error_json_expr_sql := format('jsonb_build_object(%1$L, ''Not found'')', v_json_key);

    -- SQL expression string for constructing the invalid_codes JSON object for the current activity type
    v_invalid_code_json_expr_sql := format('jsonb_build_object(%1$L, dt.%2$I)', v_json_key, v_source_code_col_name);

    -- PERF: Removed IS NOT NULL from join conditions to enable hash join optimization.
    -- NULL codes won't match any category code anyway (NULL = 'x' evaluates to NULL/false).
    -- This reduces query time from O(n²) nested loop to O(n) hash join.
    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id AS data_row_id,
                pac.id as resolved_primary_activity_category_id,
                sac.id as resolved_secondary_activity_category_id
            FROM public.%1$I dt_sub -- Target data table
            LEFT JOIN public.activity_category_enabled pac ON pac.code = dt_sub.primary_activity_category_code_raw
            LEFT JOIN public.activity_category_enabled sac ON sac.code = dt_sub.secondary_activity_category_code_raw
            WHERE dt_sub.batch_seq = $1
        )
        UPDATE public.%1$I dt SET -- Target data table
            primary_activity_category_id = CASE
                                               WHEN %2$L = 'primary_activity' THEN l.resolved_primary_activity_category_id
                                               ELSE dt.primary_activity_category_id
                                           END,
            secondary_activity_category_id = CASE
                                                 WHEN %2$L = 'secondary_activity' THEN l.resolved_secondary_activity_category_id
                                                 ELSE dt.secondary_activity_category_id
                                             END,
            state = 'analysing'::public.import_data_state,
            errors = dt.errors - %3$L::TEXT[],
            invalid_codes = CASE
                                WHEN (%4$s) THEN
                                    dt.invalid_codes || jsonb_strip_nulls(%5$s)
                                ELSE
                                    dt.invalid_codes - %3$L::TEXT[]
                            END,
            last_completed_priority = %6$L::INTEGER
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.action IS DISTINCT FROM 'skip';
    $$,
        v_data_table_name,
        p_step_code,
        v_error_keys_to_clear_arr,
        v_lookup_failed_condition_sql,
        v_invalid_code_json_expr_sql,
        v_step.priority
    );

    RAISE DEBUG '[Job %] analyse_activity: Single-pass batch update for non-skipped rows for step % (activity issues now non-fatal for all modes): %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_activity: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_activity: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_activity: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_activity: Error during single-pass batch update for step %: %', p_job_id, p_step_code, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_activity_batch_error', SQLERRM, 'step_code', p_step_code)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_activity: Marked job as failed due to error in step %: %', p_job_id, p_step_code, SQLERRM;
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_activity: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$analyse_activity$;

-- ============================================================================
-- 11. Dynamically rewrite remaining functions that reference old view names
--
-- These functions are too large to duplicate in the migration. Instead, we use
-- pg_get_functiondef() to get the current body and replace the view references.
-- This is safe because the replacements are unique strings with no false matches.
-- ============================================================================
DO $do$
DECLARE
    v_func RECORD;
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_funcs TEXT[] := ARRAY[
        -- Functions referencing external_ident_type_active
        'import.analyse_external_idents(integer,integer,text)',
        'admin.generate_statistical_unit_jsonb_indices()',
        'import.generate_external_ident_data_columns()',
        'import.cleanup_external_ident_data_columns()',
        'import.generate_link_lu_data_columns()',
        'import.cleanup_link_lu_data_columns()',
        'import.synchronize_default_definitions_all_steps()',
        -- Functions referencing stat_definition_active
        'import.generate_stat_var_data_columns()',
        'import.cleanup_stat_var_data_columns()',
        'import.process_statistical_variables(integer,integer,text)',
        'import.synchronize_definition_step_mappings(integer)',
        'import.create_source_and_mappings_for_definition(integer,text[])'
    ];
    v_func_sig TEXT;
    v_func_oid OID;
BEGIN
    FOREACH v_func_sig IN ARRAY v_funcs LOOP
        -- Look up the function OID
        BEGIN
            v_func_oid := v_func_sig::regprocedure;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Function % not found, skipping', v_func_sig;
            CONTINUE;
        END;

        -- Get the full CREATE OR REPLACE statement
        v_funcdef := pg_get_functiondef(v_func_oid);

        -- Apply replacements
        v_new_funcdef := replace(v_funcdef, 'external_ident_type_active', 'external_ident_type_enabled');
        v_new_funcdef := replace(v_new_funcdef, 'stat_definition_active', 'stat_definition_enabled');

        -- Only execute if something changed
        IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
            -- pg_get_functiondef returns CREATE FUNCTION, we need CREATE OR REPLACE
            v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
            v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
            EXECUTE v_new_funcdef;
            RAISE NOTICE 'Updated function % with new view references', v_func_sig;
        ELSE
            RAISE NOTICE 'Function % had no old view references, skipping', v_func_sig;
        END IF;
    END LOOP;
END;
$do$;

-- ============================================================================
-- 12. Re-grant permissions on all views (dropped and recreated views lost grants)
-- ============================================================================
SELECT admin.grant_permissions_on_views();
SELECT admin.grant_select_on_all_views();

END;
