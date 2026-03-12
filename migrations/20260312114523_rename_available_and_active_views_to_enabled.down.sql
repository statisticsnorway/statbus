BEGIN;

-- Reverse Migration D: Rename _enabled back to _available/_active

-- Drop status views (didn't exist before)
SELECT admin.drop_table_views_for_batch_api('public.status');

-- Drop all regenerated batch API views (they use _enabled naming)
SELECT admin.drop_table_views_for_batch_api('public.sector');
SELECT admin.drop_table_views_for_batch_api('public.legal_form');
SELECT admin.drop_table_views_for_batch_api('public.legal_reorg_type');
SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');
SELECT admin.drop_table_views_for_batch_api('public.data_source');
SELECT admin.drop_table_views_for_batch_api('public.unit_size');
SELECT admin.drop_table_views_for_batch_api('public.person_role');
SELECT admin.drop_table_views_for_batch_api('public.power_group_type');
SELECT admin.drop_table_views_for_batch_api('public.legal_rel_type');

-- Rename enum value back: 'enabled' → 'available'
ALTER TYPE admin.view_type_enum RENAME VALUE 'enabled' TO 'available';

-- Restore admin.generate_view with 'available' references
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
    view_name_str := table_properties.table_name || '_' || view_type::text;

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
    WHEN 'available' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_ordered');
        IF table_properties.has_enabled THEN
            where_clause_str := 'WHERE enabled';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'system' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
        where_clause_str := 'WHERE custom = false';
    WHEN 'custom' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
        where_clause_str := 'WHERE custom = true';
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END CASE;

    IF columns_str IS NULL THEN
      IF table_properties.has_path THEN
          columns := array_append(columns, 'path');
      ELSEIF table_properties.has_code THEN
          columns := array_append(columns, 'code');
      END IF;
      columns := array_append(columns, 'name');
      IF table_properties.has_priority THEN
          columns := array_append(columns, 'priority');
      END IF;
      IF table_properties.has_description THEN
          columns := array_append(columns, 'description');
      END IF;
      columns_str := array_to_string(columns, ', ');
    END IF;

    view_sql := format($view$
CREATE VIEW public.%1$I WITH (security_invoker=on) AS
SELECT %2$s
FROM %3$s
%4$s
%5$s
$view$
    , view_name_str, columns_str, from_str, where_clause_str, order_clause_str);

    EXECUTE view_sql;
    view_name := format('public.%I', view_name_str)::regclass;
    RAISE NOTICE 'Created view: %', view_name;
    RETURN view_name;
END;
$generate_view$ LANGUAGE plpgsql;

-- Restore admin.drop_table_views_for_batch_api with '_available'
CREATE OR REPLACE FUNCTION admin.drop_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    view_name_ordered text;
    view_name_available text;
    view_name_system text;
    view_name_custom text;
    upsert_function_name_system text;
    upsert_function_name_custom text;
    prepare_function_name_custom text;
BEGIN
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_available := schema_name_str || '.' || table_name_str || '_available';
    view_name_ordered := schema_name_str || '.' || table_name_str || '_ordered';

    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';
    prepare_function_name_custom := 'admin.prepare_' || table_name_str || '_custom';

    EXECUTE 'DROP VIEW ' || view_name_custom;
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_available;
    EXECUTE 'DROP VIEW ' || view_name_ordered;

    EXECUTE 'DROP FUNCTION ' || upsert_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_custom || '()';
    EXECUTE 'DROP FUNCTION ' || prepare_function_name_custom || '()';

    DECLARE
        table_properties admin.batch_api_table_properties;
        unique_columns text[];
        index_name text;
    BEGIN
        table_properties := admin.detect_batch_api_table_properties(table_name);
        unique_columns := admin.get_unique_columns(table_properties);
        IF array_length(unique_columns, 1) IS NOT NULL THEN
            index_name := 'ix_' || table_name_str || '_' || array_to_string(unique_columns, '_');
            EXECUTE format('DROP INDEX IF EXISTS %I', index_name);
        END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- Restore admin.generate_table_views_for_batch_api with 'available'
CREATE OR REPLACE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass)
RETURNS void AS $$
DECLARE
    table_properties admin.batch_api_table_properties;
    view_name_ordered regclass;
    view_name_available regclass;
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
    view_name_available := admin.generate_view(table_properties, 'available');
    view_name_system := admin.generate_view(table_properties, 'system');
    view_name_custom := admin.generate_view(table_properties, 'custom');

    PERFORM admin.generate_active_code_custom_unique_constraint(table_properties);

    IF table_properties.has_path THEN
        upsert_function_name_system := admin.generate_path_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_path_upsert_function(table_properties, 'custom');
    ELSIF table_properties.has_code THEN
        upsert_function_name_system := admin.generate_code_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_code_upsert_function(table_properties, 'custom');
    ELSE
        RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
    END IF;

    prepare_function_name_custom := admin.generate_prepare_function_for_custom(table_properties);

    triggers_name_system := admin.generate_view_triggers(view_name_system, upsert_function_name_system, NULL);
    triggers_name_custom := admin.generate_view_triggers(view_name_custom, upsert_function_name_custom, prepare_function_name_custom);
END;
$$ LANGUAGE plpgsql;

-- Regenerate all batch API views with original _available naming
SELECT admin.generate_table_views_for_batch_api('public.sector');
SELECT admin.generate_table_views_for_batch_api('public.legal_form');
SELECT admin.generate_table_views_for_batch_api('public.legal_reorg_type');
SELECT admin.generate_table_views_for_batch_api('public.foreign_participation');
SELECT admin.generate_table_views_for_batch_api('public.data_source');
SELECT admin.generate_table_views_for_batch_api('public.unit_size');
SELECT admin.generate_table_views_for_batch_api('public.person_role');
SELECT admin.generate_table_views_for_batch_api('public.power_group_type');
SELECT admin.generate_table_views_for_batch_api('public.legal_rel_type');

-- Rename manual views back
DROP TRIGGER activity_category_enabled_custom_upsert_custom ON public.activity_category_enabled_custom;
DROP TRIGGER activity_category_enabled_upsert_custom ON public.activity_category_enabled;

ALTER VIEW public.activity_category_enabled RENAME TO activity_category_available;
ALTER VIEW public.activity_category_enabled_custom RENAME TO activity_category_available_custom;

ALTER FUNCTION admin.activity_category_enabled_upsert_custom() RENAME TO activity_category_available_upsert_custom;
ALTER FUNCTION admin.activity_category_enabled_custom_upsert_custom() RENAME TO activity_category_available_custom_upsert_custom;

CREATE TRIGGER activity_category_available_upsert_custom
INSTEAD OF INSERT ON public.activity_category_available
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_available_upsert_custom();

CREATE TRIGGER activity_category_available_custom_upsert_custom
INSTEAD OF INSERT ON public.activity_category_available_custom
FOR EACH ROW
EXECUTE FUNCTION admin.activity_category_available_custom_upsert_custom();

-- Rename _enabled back to _active
ALTER VIEW public.external_ident_type_enabled RENAME TO external_ident_type_active;
ALTER VIEW public.stat_definition_enabled RENAME TO stat_definition_active;

-- Restore original import procedures (with _available references)
-- analyse_data_source
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
        WITH batch_data AS (
            SELECT dt.row_id, dt.data_source_code_raw AS data_source_code FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.action IS DISTINCT FROM 'skip'
        ), distinct_codes AS (
            SELECT data_source_code AS code FROM batch_data WHERE NULLIF(data_source_code, '') IS NOT NULL GROUP BY 1
        ), resolved_codes AS (
            SELECT dc.code, ds.id as resolved_id FROM distinct_codes dc LEFT JOIN public.data_source_available ds ON ds.code = dc.code
        ), lookups AS (
            SELECT bd.row_id, rc.resolved_id as resolved_data_source_id FROM batch_data bd LEFT JOIN resolved_codes rc ON bd.data_source_code = rc.code
        )
        UPDATE public.%1$I dt SET
            data_source_id = COALESCE(l.resolved_data_source_id, dt.data_source_id),
            invalid_codes = jsonb_strip_nulls(
                (COALESCE(dt.invalid_codes, '{}'::jsonb) - 'data_source_code_raw') ||
                jsonb_build_object('data_source_code_raw', CASE WHEN NULLIF(dt.data_source_code_raw, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code_raw ELSE NULL END)
            ),
            last_completed_priority = %2$L
        FROM lookups l WHERE dt.row_id = l.row_id;
    $SQL$, v_job.data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Updating non-skipped rows with SQL: %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_data_source (Batch): Updated % non-skipped rows.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_data_source: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_data_source_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;
    v_sql := format('UPDATE public.%I dt SET last_completed_priority = %s WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %s', v_job.data_table_name, v_step.priority, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
END;
$analyse_data_source$;

END;
