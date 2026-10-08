-- Migration 20261008172118: statbus_477 path generated upserts update existing rows
--
-- STATBUS-477 family D: the path-based tables whose upsert triggers come from
-- admin.generate_path_upsert_function: sector and tag. sector and tag both
-- carry UNIQUE (path) (sector_path_key, tag_path_key), so a row's identity is
-- its path alone: one row per path, owned by one kind (system or custom), and
-- a custom override of a system path is impossible by schema. Hence no new
-- key and no dedupe here: UNIQUE (path) already forbids the duplicate this
-- family would otherwise need to collapse.
--
-- Defects fixed in the generator and the four upserts it produced:
-- 1. ON CONFLICT (enabled, path) ... WHERE <t>.id = EXCLUDED.id: the predicate
--    never fires (identity id), so a corrected re-upload was INSERT 0 0; and
--    (enabled, path) cannot see a disabled row, so after the app's
--    sector_custom_only upload disables the system sectors, reloading the
--    shipped sector list failed with a duplicate key on sector_path_key.
--    Now: ON CONFLICT (path), updating only a row of the upsert's own kind.
-- 2. The custom upsert inserted with enabled = NOT custom_value, i.e. FALSE:
--    a generated custom upload landed invisible. Now it inserts enabled.
-- 3. description, which every generated view accepts, was silently dropped;
--    it is now written. (Audit: the views expose path, name, description;
--    all three are written now; parent_id is derived from path.)
-- 4. A path owned by the other kind is refused with an error that names the
--    path, the owning kind and what the operator can do, instead of a raw
--    unique_violation.
-- The INSTEAD OF triggers return the row, so INSERT/COPY report it, and
-- admin.generate_active_code_custom_unique_constraint ensures UNIQUE (path)
-- on any path table generated later.
BEGIN;

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
;

CREATE OR REPLACE FUNCTION admin.generate_active_code_custom_unique_constraint(table_properties admin.batch_api_table_properties)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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

    -- STATBUS-477: the row's identity, (code, custom), is the key the
    -- generated code upserts conflict on. It is a table constraint that
    -- outlives the generated views (admin.drop_table_views_for_batch_api
    -- leaves it), so it is created only when absent: drop + regenerate stays
    -- idempotent. (Path tables get theirs with the path family.)
    IF table_properties.has_custom AND table_properties.has_code AND NOT table_properties.has_path THEN
        index_name := table_properties.table_name || '_code_custom_key';
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_constraint AS con
             WHERE con.conrelid = format('%I.%I', table_properties.schema_name, table_properties.table_name)::regclass
               AND con.conname = index_name)
        THEN
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I UNIQUE (code, custom)'
                , table_properties.schema_name, table_properties.table_name, index_name);
            RAISE NOTICE 'Created identity key % for table %', index_name, table_properties.table_name;
        END IF;
    END IF;

    -- STATBUS-477: a path table's identity is path alone, the key the
    -- generated path upserts conflict on. Created only when absent (sector and
    -- tag already carry <table>_path_key), so drop + regenerate stays
    -- idempotent.
    IF table_properties.has_path THEN
        index_name := table_properties.table_name || '_path_key';
        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_index AS i
              JOIN pg_catalog.pg_attribute AS a
                ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
             WHERE i.indrelid = format('%I.%I', table_properties.schema_name, table_properties.table_name)::regclass
               AND i.indisunique
               AND i.indnkeyatts = 1
               AND i.indpred IS NULL
               AND a.attname = 'path')
        THEN
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I UNIQUE (path)'
                , table_properties.schema_name, table_properties.table_name, index_name);
            RAISE NOTICE 'Created identity key % for table %', index_name, table_properties.table_name;
        END IF;
    END IF;
END;
$function$
;

-- The four existing path upserts, exactly as the fixed generator above
-- produces them (CREATE OR REPLACE keeps the view triggers bound).
CREATE OR REPLACE FUNCTION admin.upsert_sector_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.sector AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 't' THEN
        RAISE EXCEPTION 'sector path "%" already exists as a system (standard) entry, so this custom upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'A custom entry cannot replace a standard one with the same path. Use a path that is not in the standard list.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.sector
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.sector (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        enabled = TRUE,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_sector_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.sector AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 'f' THEN
        RAISE EXCEPTION 'sector path "%" already exists as a custom entry, so this system (standard) upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.sector
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.sector (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_tag_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.tag AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 't' THEN
        RAISE EXCEPTION 'tag path "%" already exists as a system (standard) entry, so this custom upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'A custom entry cannot replace a standard one with the same path. Use a path that is not in the standard list.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        enabled = TRUE,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_tag_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    existing_custom boolean;
BEGIN
    SELECT t.custom INTO existing_custom
      FROM public.tag AS t
     WHERE t.path OPERATOR(public.=) NEW.path;
    IF FOUND AND existing_custom IS DISTINCT FROM 'f' THEN
        RAISE EXCEPTION 'tag path "%" already exists as a custom entry, so this system (standard) upload cannot add or change it', NEW.path
            USING ERRCODE = 'unique_violation', HINT = 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.';
    END IF;

    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, description, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

END;
