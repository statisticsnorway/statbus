-- Down Migration 20261008175137: statbus_478 generated views carry required columns
-- Restores the three generators, the status_custom/status_system views with
-- their triggers and upserts, exactly as before, and drops the helper.
BEGIN;

CREATE OR REPLACE FUNCTION admin.generate_view(table_properties admin.batch_api_table_properties, view_type admin.view_type_enum)
 RETURNS regclass
 LANGUAGE plpgsql
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION admin.generate_code_upsert_function(table_properties admin.batch_api_table_properties, view_type admin.view_type_enum)
 RETURNS regprocedure
 LANGUAGE plpgsql
AS $functionx$
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
    kind_guard text := '';
    kind text;
    other_kind text;
BEGIN
    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    -- STATBUS-477: conflict on the identity key the table actually has:
    -- (code) when the code alone is unique (one row per code, owned by one
    -- kind), else (code, custom) (one system row and at most one custom
    -- override). Never (enabled, code), which cannot see a disabled row and
    -- treats an enabled custom override and an enabled system row as one, and
    -- never an id = EXCLUDED.id predicate, which cannot fire for an identity id.
    unique_columns := admin.batch_api_identity_key(table_properties);

    -- Utilize has_description from table_properties
    IF table_properties.has_description THEN
        content_columns := content_columns || ', description';
        content_values := content_values || ', NEW.description';
        content_update_sets := content_update_sets || ', description = NEW.description';
    END IF;

    IF table_properties.has_enabled THEN
        content_columns := content_columns || ', enabled';
        -- A custom upload enables its row. A system load enables a NEW system
        -- row unless an enabled custom override of the code exists, and on
        -- update corrects the label only, never the enabled flag (the custom
        -- upload disables system rows on purpose).
        IF view_type = 'custom' THEN
            content_values := content_values || ', TRUE';
            content_update_sets := content_update_sets || ', enabled = TRUE';
        ELSIF unique_columns = ARRAY['code'] THEN
            content_values := content_values || ', TRUE';
        ELSE
            content_values := content_values || format(
                ', NOT EXISTS (SELECT 1 FROM %I.%I AS override WHERE override.code = NEW.code AND override.custom AND override.enabled)'
                , table_properties.schema_name, table_properties.table_name);
        END IF;
    END IF;

    -- Where identity is the code alone, a code belongs to one kind: refuse a
    -- code owned by the other kind with an error the operator can act on.
    IF unique_columns = ARRAY['code'] AND table_properties.has_custom THEN
        IF custom_value THEN
            kind := 'custom';
            other_kind := 'system (standard)';
        ELSE
            kind := 'system (standard)';
            other_kind := 'custom';
        END IF;
        kind_guard := format($guard$
    IF EXISTS (SELECT 1 FROM %1$I.%2$I AS t WHERE t.code = NEW.code AND t.custom IS DISTINCT FROM %3$L) THEN
        RAISE EXCEPTION %4$L, NEW.code
            USING ERRCODE = 'unique_violation', HINT = %5$L;
    END IF;
$guard$
        , table_properties.schema_name, table_properties.table_name, custom_value
        , table_name_str || ' code "%" already exists as a ' || other_kind
          || ' entry, so this ' || kind || ' upload cannot add or change it'
        , CASE WHEN custom_value
               THEN 'A custom entry cannot replace a standard one with the same code. Use a code that is not in the standard list.'
               ELSE 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.'
          END);
    END IF;

    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Construct the SQL statement for the upsert function
function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
DECLARE
    row RECORD;
    _constraint text;
    _detail text;
BEGIN%10$s
    BEGIN
        INSERT INTO %3$I.%4$I (code, %5$s, custom, updated_at)
        VALUES (NEW.code, %6$s, %7$L, statement_timestamp())
        ON CONFLICT (%9$s) DO UPDATE SET
            %8$s,
            updated_at = statement_timestamp()
        RETURNING * INTO row;
    EXCEPTION WHEN unique_violation THEN
        -- Any other unique key (e.g. name) collides: say which, for this row.
        GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
        RAISE EXCEPTION %11$L, NEW.code, _detail
            USING ERRCODE = 'unique_violation', CONSTRAINT = _constraint, HINT = %12$L;
    END;

    RAISE DEBUG 'UPSERTED %%', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
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
, array_to_string(unique_columns, ', ') -- %9$: the identity key to conflict on
, kind_guard                   -- %10$: refusal of a code owned by the other kind
, table_name_str || ' code "%" cannot be stored: another entry already has a value that must be unique (%)'
                               -- %11$: message for a collision on any other unique key
, 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.'
                               -- %12$: what the operator can do
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created code-based upsert function: %', function_name;

    RETURN function_name;
END;
$functionx$
;

CREATE OR REPLACE FUNCTION admin.generate_path_upsert_function(table_properties admin.batch_api_table_properties, view_type admin.view_type_enum)
 RETURNS regprocedure
 LANGUAGE plpgsql
AS $functionx$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    unique_columns text[];
    insert_enabled text;
    update_enabled text := '';
    description_column text := '';
    description_value text := '';
    description_update text := '';
    kind text;
    other_kind text;
    collision_message text;
    collision_hint text;
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

    -- STATBUS-477: a path table's identity key is resolved, not assumed:
    -- admin.batch_api_identity_key returns (path) when the path alone is
    -- unique (sector, tag: one row per path, owned by one kind) and
    -- (path, custom) otherwise. The upsert conflicts on it, and where identity
    -- is the path alone it updates only a row of its own kind and refuses a
    -- path the other kind owns with an error the operator can act on.
    -- (enabled, path) missed disabled rows (a system reload after a
    -- custom-only upload failed on the path key), and the id = EXCLUDED.id
    -- predicate never fired.
    unique_columns := admin.batch_api_identity_key(table_properties);
    IF unique_columns <> ARRAY['path'] THEN
        RAISE EXCEPTION 'STATBUS-477: %.% has identity key (%), but generated path upserts need one row per path (they derive parent_id by path); give the table UNIQUE (path)'
            , schema_name_str, table_name_str, array_to_string(unique_columns, ', ');
    END IF;

    -- A custom upload is visible: it inserts and keeps its row enabled. (The
    -- template used NOT custom_value, so generated custom rows were invisible.)
    -- A system load inserts enabled and on update corrects the labels only,
    -- never the enabled flag (a custom-only upload disables system rows).
    IF custom_value THEN
        insert_enabled := 'TRUE';
        update_enabled := ',' || E'\n        ' || 'enabled = TRUE';
        kind := 'custom';
        other_kind := 'system (standard)';
        collision_hint := 'A custom entry cannot replace a standard one with the same path. Use a path that is not in the standard list.';
    ELSE
        insert_enabled := 'TRUE';
        kind := 'system (standard)';
        other_kind := 'custom';
        collision_hint := 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.';
    END IF;
    collision_message := table_name_str || ' path "%" already exists as a ' || other_kind
        || ' entry, so this ' || kind || ' upload cannot add or change it';

    -- Write every column the generated views accept: the views expose
    -- description when the table has it, and it was silently dropped.
    IF table_properties.has_description THEN
        description_column := ', description';
        description_value := ', NEW.description';
        description_update := ',' || E'\n        ' || 'description = EXCLUDED.description';
    END IF;

    -- Construct the SQL statement for the upsert function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER AS $body$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM %3$I.%4$I AS t
     WHERE t.path OPERATOR(public.=) NEW.path
       AND %13$L;
    IF FOUND AND existing_custom IS DISTINCT FROM %5$L THEN
        RAISE EXCEPTION %6$L, NEW.path
            USING ERRCODE = 'unique_violation', HINT = %7$L;
    END IF;

    WITH parent AS (
        SELECT id
        FROM %3$I.%4$I
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO %3$I.%4$I (path, parent_id, name%8$s, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name%9$s, %10$s, %5$L, statement_timestamp())
    ON CONFLICT (%14$s) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name%11$s%12$s,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$body$ LANGUAGE plpgsql;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, schema_name_str              -- %3$: Schema name for the target table
, table_name_str               -- %4$: Table name
, custom_value                 -- %5$: custom value of the rows this upsert owns
, collision_message            -- %6$: error when the other kind owns the path
, collision_hint               -- %7$: what the operator can do
, description_column           -- %8$: description column, if the table has it
, description_value            -- %9$: description value
, insert_enabled               -- %10$: enabled on insert
, description_update           -- %11$: description on update
, update_enabled               -- %12$: enabled on update (custom only)
, unique_columns = ARRAY['path'] -- %13$: identity is the path alone, so a path has one owning kind
, array_to_string(unique_columns, ', ') -- %14$: the identity key to conflict on
);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created path-based upsert function: %', function_name;

    RETURN function_name;
END;
$functionx$
;

DROP VIEW public.status_custom;
DROP VIEW public.status_system;
DROP FUNCTION admin.upsert_status_custom();
DROP FUNCTION admin.upsert_status_system();
CREATE OR REPLACE FUNCTION admin.upsert_status_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
    _constraint text;
    _detail text;
BEGIN
    BEGIN
        INSERT INTO public.status (code, name, enabled, custom, updated_at)
        VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
        ON CONFLICT (code, custom) DO UPDATE SET
            name = NEW.name, enabled = TRUE,
            updated_at = statement_timestamp()
        RETURNING * INTO row;
    EXCEPTION WHEN unique_violation THEN
        -- Any other unique key (e.g. name) collides: say which, for this row.
        GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
        RAISE EXCEPTION 'status code "%" cannot be stored: another entry already has a value that must be unique (%)', NEW.code, _detail
            USING ERRCODE = 'unique_violation', CONSTRAINT = _constraint, HINT = 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.';
    END;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_status_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
    _constraint text;
    _detail text;
BEGIN
    BEGIN
        INSERT INTO public.status (code, name, enabled, custom, updated_at)
        VALUES (NEW.code, NEW.name, NOT EXISTS (SELECT 1 FROM public.status AS override WHERE override.code = NEW.code AND override.custom AND override.enabled), 'f', statement_timestamp())
        ON CONFLICT (code, custom) DO UPDATE SET
            name = NEW.name,
            updated_at = statement_timestamp()
        RETURNING * INTO row;
    EXCEPTION WHEN unique_violation THEN
        -- Any other unique key (e.g. name) collides: say which, for this row.
        GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
        RAISE EXCEPTION 'status code "%" cannot be stored: another entry already has a value that must be unique (%)', NEW.code, _detail
            USING ERRCODE = 'unique_violation', CONSTRAINT = _constraint, HINT = 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.';
    END;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE VIEW public.status_system WITH (security_invoker = on) AS
 SELECT code, name, priority FROM public.status_enabled WHERE custom = false;
CREATE VIEW public.status_custom WITH (security_invoker = on) AS
 SELECT code, name, priority FROM public.status_enabled WHERE custom = true;
CREATE TRIGGER upsert_status_system INSTEAD OF INSERT ON public.status_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_system();
CREATE TRIGGER upsert_status_custom INSTEAD OF INSERT ON public.status_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_custom();
CREATE TRIGGER prepare_status_custom BEFORE INSERT ON public.status_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_status_custom();
GRANT SELECT, INSERT ON public.status_system TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.status_custom TO authenticated, regular_user, admin_user;

DROP FUNCTION admin.batch_api_required_columns(admin.batch_api_table_properties);

END;
