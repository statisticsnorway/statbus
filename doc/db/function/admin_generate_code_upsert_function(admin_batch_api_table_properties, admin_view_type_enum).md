```sql
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

    -- STATBUS-478: write every other column the generated view accepts:
    -- priority, and the required columns admin.generate_view exposes
    -- (admin.batch_api_required_columns). Dropping them failed every insert
    -- (NOT NULL) or silently discarded the value.
    IF table_properties.has_priority THEN
        content_columns := content_columns || ', priority';
        content_values := content_values || ', NEW.priority';
        content_update_sets := content_update_sets || ', priority = NEW.priority';
    END IF;
    SELECT content_columns || coalesce(string_agg(', ' || quote_ident(c), '' ORDER BY o), '')
         , content_values || coalesce(string_agg(', NEW.' || quote_ident(c), '' ORDER BY o), '')
         , content_update_sets || coalesce(string_agg(format(', %1$I = NEW.%1$I', c), '' ORDER BY o), '')
      INTO content_columns, content_values, content_update_sets
      FROM unnest(admin.batch_api_required_columns(table_properties)) WITH ORDINALITY AS r(c, o);

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
```
