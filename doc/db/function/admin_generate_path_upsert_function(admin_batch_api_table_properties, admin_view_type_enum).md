```sql
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

    -- STATBUS-477: a path table's identity is path alone (UNIQUE (path), which
    -- admin.generate_active_code_custom_unique_constraint ensures), so a path
    -- belongs to exactly one kind, system or custom. The upsert conflicts on
    -- (path), updates only a row of its own kind, and refuses a path the other
    -- kind owns with an error the operator can act on. (enabled, path) missed
    -- disabled rows (a system reload after a custom-only upload failed on the
    -- path key), and the id = EXCLUDED.id predicate never fired.
    unique_columns := ARRAY['path'];

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
     WHERE t.path OPERATOR(public.=) NEW.path;
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
    ON CONFLICT (path) DO UPDATE SET
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
);

    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created path-based upsert function: %', function_name;

    RETURN function_name;
END;
$functionx$
```
