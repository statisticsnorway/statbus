-- Migration 20261008175137: statbus_478 generated views carry required columns
--
-- STATBUS-478. public.status has assigned_by_default, used_for_counting and
-- priority NOT NULL without a default, but the generated status_custom and
-- status_system views exposed only (code, name, priority) and the generated
-- upserts wrote only code and name: every insert through them failed on a
-- NOT NULL constraint, and priority was silently dropped.
--
-- Fixed in the generators, not as a status special case:
-- * admin.batch_api_required_columns(table_properties) DERIVES the columns an
--   insert must supply that the generated upsert does not manage itself:
--   attnotnull AND NOT atthasdef AND not identity AND not generated, minus
--   id, code, path, parent_id, name, description, priority, enabled, custom,
--   created_at, updated_at (name, description and priority are handled by
--   their own table properties). Across the 12 generated tables only status
--   has any (assigned_by_default, used_for_counting).
-- * admin.generate_view puts them in the system/custom views.
-- * admin.generate_code_upsert_function and generate_path_upsert_function
--   write priority and those columns on insert and update.
-- * status_custom and status_system are recreated through the generator and
--   re-granted with the explicit GRANT path of
--   admin.grant_permissions_on_views; their two upserts are regenerated.
--   The migration asserts the ACL invariant of the batch views: the two
--   recreated views end with exactly their previous ACL, which is the
--   uniform batch-view ACL, and no other batch view's ACL changes.
-- This touches no sql_saga for_portion_of_valid view, so it does not
-- interact with STATBUS-481.
BEGIN;

CREATE FUNCTION admin.batch_api_required_columns(table_properties admin.batch_api_table_properties)
RETURNS text[]
LANGUAGE sql
STABLE
AS $batch_api_required_columns$
    -- STATBUS-478: the columns an insert through a generated system/custom
    -- view must supply and that the generated upsert does not manage itself.
    SELECT coalesce(array_agg(a.attname::text ORDER BY a.attnum), ARRAY[]::text[])
      FROM pg_catalog.pg_attribute AS a
     WHERE a.attrelid = format('%I.%I', table_properties.schema_name, table_properties.table_name)::regclass
       AND a.attnum > 0
       AND NOT a.attisdropped
       AND a.attnotnull
       AND NOT a.atthasdef
       AND a.attidentity = ''
       AND a.attgenerated = ''
       AND a.attname NOT IN ('id', 'code', 'path', 'parent_id', 'name', 'description', 'priority'
                           , 'enabled', 'custom', 'created_at', 'updated_at');
$batch_api_required_columns$;

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

      -- STATBUS-478: a system/custom view must accept every column an insert
      -- needs, or every insert through it fails on a NOT NULL constraint.
      -- The set is derived, not listed: admin.batch_api_required_columns.
      columns := columns || admin.batch_api_required_columns(table_properties);

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

    -- STATBUS-478: also write priority and the required columns the view
    -- exposes (admin.batch_api_required_columns), so a path table that has
    -- them is not broken the way status was. (No path table has any today.)
    SELECT description_column || coalesce(string_agg(', ' || quote_ident(c), '' ORDER BY o), '')
         , description_value || coalesce(string_agg(', NEW.' || quote_ident(c), '' ORDER BY o), '')
         , description_update || coalesce(string_agg(format(',' || E'\n        ' || '%1$I = EXCLUDED.%1$I', c), '' ORDER BY o), '')
      INTO description_column, description_value, description_update
      FROM unnest(
             CASE WHEN table_properties.has_priority THEN ARRAY['priority'] ELSE ARRAY[]::text[] END
             || admin.batch_api_required_columns(table_properties)
           ) WITH ORDINALITY AS r(c, o);

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

-- Snapshot every generated batch view's ACL before the recreate.
CREATE TEMP TABLE batch_view_acl_before ON COMMIT DROP AS
SELECT c.relname AS view_name, c.relacl::text AS acl
  FROM pg_catalog.pg_class AS c
 WHERE c.relnamespace = 'public'::regnamespace
   AND c.relkind = 'v'
   AND c.relname IN (
       SELECT t || '_' || v
         FROM unnest(ARRAY['legal_form', 'data_source', 'foreign_participation', 'unit_size', 'status'
                         , 'legal_rel_type', 'legal_reorg_type', 'person_role', 'power_group_type'
                         , 'region_version', 'sector', 'tag']) AS t
        CROSS JOIN unnest(ARRAY['ordered', 'enabled', 'system', 'custom']) AS v);

-- Recreate status_custom and status_system through the fixed generators, and
-- their upserts; re-grant with the same explicit GRANTs as
-- admin.grant_permissions_on_views (no inheritance-aware propagation).
DO $recreate_status_views$
DECLARE
    _properties admin.batch_api_table_properties := admin.detect_batch_api_table_properties('public.status'::regclass);
    _variant admin.view_type_enum;
    _view regclass;
BEGIN
    DROP VIEW public.status_custom;
    DROP VIEW public.status_system;
    DROP FUNCTION admin.upsert_status_custom();
    DROP FUNCTION admin.upsert_status_system();
    FOREACH _variant IN ARRAY ARRAY['system', 'custom']::admin.view_type_enum[] LOOP
        _view := admin.generate_view(_properties, _variant);
        PERFORM admin.generate_view_triggers(
              _view
            , admin.generate_code_upsert_function(_properties, _variant)
            , CASE WHEN _variant = 'custom' THEN 'admin.prepare_status_custom()'::regprocedure END);
        EXECUTE format('GRANT SELECT ON %s TO authenticated, regular_user, admin_user', _view);
        EXECUTE format('GRANT INSERT ON %s TO authenticated, regular_user, admin_user', _view);
    END LOOP;
END;
$recreate_status_views$;

-- The batch-view ACL invariant: the two recreated views have exactly their
-- previous ACL, which is the uniform ACL of their siblings, and no other batch
-- view's ACL changed. Exact entries are compared, never has_table_privilege.
DO $assert_batch_view_acl$
DECLARE
    _changed text;
    _uniform text;
BEGIN
    SELECT string_agg(b.view_name, ', ' ORDER BY b.view_name) INTO _changed
      FROM pg_temp.batch_view_acl_before AS b
      LEFT JOIN pg_catalog.pg_class AS c
        ON c.relnamespace = 'public'::regnamespace AND c.relname = b.view_name
     WHERE c.oid IS NULL OR c.relacl::text IS DISTINCT FROM b.acl;
    IF _changed IS NOT NULL THEN
        RAISE EXCEPTION 'STATBUS-478: batch view ACL changed or view missing: %', _changed;
    END IF;

    SELECT min(b.acl) INTO _uniform FROM pg_temp.batch_view_acl_before AS b
     WHERE b.view_name NOT IN ('status_custom', 'status_system');
    IF EXISTS (SELECT 1 FROM pg_temp.batch_view_acl_before AS b WHERE b.acl IS DISTINCT FROM _uniform) THEN
        RAISE EXCEPTION 'STATBUS-478: batch views do not share one ACL';
    END IF;
    RAISE NOTICE 'STATBUS-478: % batch views unchanged, all with ACL %'
        , (SELECT count(*) FROM pg_temp.batch_view_acl_before), _uniform;
END;
$assert_batch_view_acl$;

END;
