BEGIN;

-- Helpers to generate views for bach API handling of all the system provided configuration
-- that can also be overridden.
CREATE TYPE admin.view_type_enum AS ENUM ('ordered', 'available', 'system', 'custom');
CREATE TYPE admin.batch_api_table_properties AS (
    has_priority boolean,
    has_enabled boolean,
    has_path boolean,
    has_code boolean,
    has_custom boolean,
    has_description boolean,
    schema_name text,
    table_name text
);

CREATE FUNCTION admin.generate_view(
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


CREATE FUNCTION admin.get_unique_columns(
    table_properties admin.batch_api_table_properties)
RETURNS text[] LANGUAGE plpgsql AS $get_unique_columns$
DECLARE
    unique_columns text[] := ARRAY[]::text[];
BEGIN
    IF table_properties.has_enabled THEN
        unique_columns := array_append(unique_columns, 'enabled');
    END IF;

    IF table_properties.has_path THEN
        unique_columns := array_append(unique_columns, 'path');
    ELSEIF table_properties.has_code THEN
        unique_columns := array_append(unique_columns, 'code');
    END IF;

    RETURN unique_columns;
END;
$get_unique_columns$;


CREATE FUNCTION admin.generate_active_code_custom_unique_constraint(
    table_properties admin.batch_api_table_properties)
RETURNS VOID LANGUAGE plpgsql AS $generate_active_code_custom_unique_constraint$
DECLARE
    constraint_sql text;
    unique_columns text[];
    index_name text;
BEGIN
    -- Get the unique columns based on table properties
    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct index name by joining columns with underscores
    index_name := 'ix_' || table_properties.table_name || '_' || array_to_string(unique_columns, '_');

    -- Ensure there are columns to create a constraint for
    IF array_length(unique_columns, 1) IS NOT NULL THEN
        -- Create a unique index for the determined unique columns
        constraint_sql := format($$
CREATE UNIQUE INDEX %I ON public.%I USING btree (%s);
$$, index_name, table_properties.table_name, array_to_string(unique_columns, ', '));

        EXECUTE constraint_sql;
        RAISE NOTICE 'Created unique constraint on (%) for table %', array_to_string(unique_columns, ', '), table_properties.table_name;
    END IF;
END;
$generate_active_code_custom_unique_constraint$;


CREATE FUNCTION admin.generate_code_upsert_function(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regprocedure LANGUAGE plpgsql AS $generate_code_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    content_columns text := 'name';
    content_values text := 'NEW.name';
    content_update_sets text := 'name = NEW.name';
    unique_columns text[];
BEGIN
    -- Utilize has_description from table_properties
    IF table_properties.has_description THEN
        content_columns := content_columns || ', description';
        content_values := content_values || ', NEW.description';
        content_update_sets := content_update_sets || ', description = NEW.description';
    END IF;

    IF table_properties.has_enabled THEN
        content_columns := content_columns || ', enabled';
        content_values := content_values || ', TRUE';
        content_update_sets := content_update_sets || ', enabled = TRUE';
    END IF;

    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct the SQL statement for the upsert function
function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO %3$I.%4$I (code, %5$s, custom, updated_at)
    VALUES (NEW.code, %6$s, %7$L, statement_timestamp())
    ON CONFLICT (%9$s) DO UPDATE SET
        %8$s,
        custom = %7$L,
        updated_at = statement_timestamp()
    WHERE %4$I.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %%', to_json(row);

    RETURN NULL;
END;
$body$;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, table_properties.schema_name -- %3$: Schema name for the table
, table_properties.table_name  -- %4$: Table name
, content_columns              -- %5$: Columns to be inserted/updated
, content_values               -- %6$: Values to be inserted
, custom_value                 -- %7$: Boolean indicating system or custom
, content_update_sets          -- %8$: SET clause for the ON CONFLICT update
, array_to_string(unique_columns, ', ') -- %9$: columns to use for conflict detection/resolution
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created code-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_code_upsert_function$;


CREATE FUNCTION admin.generate_path_upsert_function(
    table_properties admin.batch_api_table_properties,
    view_type admin.view_type_enum)
RETURNS regprocedure AS $generate_path_upsert_function$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    unique_columns text[];
BEGIN
    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- Get unique columns using admin.get_unique_columns
    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct the SQL statement for the upsert function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER AS $body$
BEGIN
    WITH parent AS (
        SELECT id
        FROM %3$I.%4$I
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO %3$I.%4$I (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, %5$L, %6$L, statement_timestamp())
    ON CONFLICT (%7$s) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = %6$L,
        updated_at = statement_timestamp()
    WHERE %4$I.id = EXCLUDED.id;
    RETURN NULL;
END;
$body$ LANGUAGE plpgsql;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, schema_name_str              -- %3$: Schema name for the target table
, table_name_str               -- %4$: Table name
, not custom_value             -- %5$: Boolean indicating system or custom (inverted for INSERT)
, custom_value                 -- %6$: Value for custom in the INSERT and ON CONFLICT update
, array_to_string(unique_columns, ', ') -- %7$: Unique columns for ON CONFLICT
);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created path-based upsert function: %', function_name;

    RETURN function_name;
END;
$generate_path_upsert_function$ LANGUAGE plpgsql;


CREATE FUNCTION admin.generate_prepare_function_for_custom(
  table_properties admin.batch_api_table_properties
)
RETURNS regprocedure LANGUAGE plpgsql AS $generate_prepare_function_for_custom$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
BEGIN
    function_name_str := 'prepare_' || table_properties.table_name || '_custom';

    -- Construct the SQL statement for the delete function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE %3$I.%4$I
       SET enabled = false
     WHERE enabled = true
       AND custom = false;

    RETURN NULL;
END;
$body$;
$function$
, function_schema   -- %1$
, function_name_str -- %2$
, table_properties.schema_name -- %3$
, table_properties.table_name -- %4$
, custom_value      -- %5$
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created prepare function: %', function_name;

    RETURN function_name;
END;
$generate_prepare_function_for_custom$;


CREATE FUNCTION admin.generate_view_triggers(view_name regclass, upsert_function_name regprocedure, prepare_function_name regprocedure)
RETURNS text[] AS $generate_triggers$
DECLARE
    view_name_str text;
    upsert_trigger_sql text;
    prepare_trigger_sql text;
    upsert_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    upsert_trigger_name text;
    prepare_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    prepare_trigger_name text := NULL;
BEGIN
    -- Lookup view_name_str
    SELECT relname INTO view_name_str
    FROM pg_catalog.pg_class
    WHERE oid = view_name;

    upsert_trigger_name_str := 'upsert_' || view_name_str;
    prepare_trigger_name_str := 'prepare_' || view_name_str;

    -- Construct the SQL statement for the upsert trigger
    upsert_trigger_sql := format($$CREATE TRIGGER %I
                                  INSTEAD OF INSERT ON %s
                                  FOR EACH ROW
                                  EXECUTE FUNCTION %s;$$,
                                  upsert_trigger_name_str, view_name::text, upsert_function_name::text);
    EXECUTE upsert_trigger_sql;
    upsert_trigger_name := format('public.%I',upsert_trigger_name_str);
    RAISE NOTICE 'Created upsert trigger: %', upsert_trigger_name;

    IF prepare_function_name IS NOT NULL THEN
      -- Construct the SQL statement for the delete trigger
      prepare_trigger_sql := format($$CREATE TRIGGER %I
                                    BEFORE INSERT ON %s
                                    FOR EACH STATEMENT
                                    EXECUTE FUNCTION %s;$$,
                                    prepare_trigger_name_str, view_name::text, prepare_function_name::text);
      -- Log and execute
      EXECUTE prepare_trigger_sql;
      prepare_trigger_name := format('public.%I',prepare_trigger_name_str);

      RAISE NOTICE 'Created prepare trigger: %', prepare_trigger_name;
    END IF;

    -- Return the regclass identifiers of the created triggers
    RETURN ARRAY[upsert_trigger_name, prepare_trigger_name];
END;
$generate_triggers$ LANGUAGE plpgsql;


CREATE FUNCTION admin.detect_batch_api_table_properties(table_name regclass)
RETURNS admin.batch_api_table_properties AS $$
DECLARE
    result admin.batch_api_table_properties;
BEGIN
    -- Initialize the result with default values
    result.has_priority := false;
    result.has_enabled := false;
    result.has_path := false;
    result.has_code := false;
    result.has_custom := false;
    result.has_description := false;
    result.schema_name := '';
    result.table_name := '';

    -- Populate schema_name and table_name
    SELECT n.nspname, c.relname
    INTO result.schema_name, result.table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Check if specific columns exist
    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'priority' AND NOT attisdropped;
    IF FOUND THEN
        result.has_priority := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'enabled' AND NOT attisdropped;
    IF FOUND THEN
        result.has_enabled := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'path' AND NOT attisdropped;
    IF FOUND THEN
        result.has_path := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'code' AND NOT attisdropped;
    IF FOUND THEN
        result.has_code := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'custom' AND NOT attisdropped;
    IF FOUND THEN
        result.has_custom := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'description' AND NOT attisdropped;
    IF FOUND THEN
        result.has_description := true;
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql;


CREATE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass)
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
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view and function names
    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_available := schema_name_str || '.' || table_name_str || '_available';
    view_name_ordered := schema_name_str || '.' || table_name_str || '_ordered';

    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';

    prepare_function_name_custom := 'admin.prepare_' || table_name_str || '_custom';

    -- Drop views
    EXECUTE 'DROP VIEW ' || view_name_custom;
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_available;
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

END;
