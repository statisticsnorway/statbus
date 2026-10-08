-- Down Migration 20261008172915: statbus_477 key aware generators and code keyed upserts
--
-- Restores the three generator functions and all 24 generated upserts exactly
-- as dumped (\sf) before the up migration, and drops the identity-key resolver.
-- CREATE OR REPLACE keeps the regenerated view triggers bound by name.
BEGIN;

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
BEGIN
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
        ELSE
            content_values := content_values || format(
                ', NOT EXISTS (SELECT 1 FROM %I.%I AS override WHERE override.code = NEW.code AND override.custom AND override.enabled)'
                , table_properties.schema_name, table_properties.table_name);
        END IF;
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

    -- STATBUS-477: conflict on the row's identity, (code, custom): one system
    -- row and at most one custom override per code. (enabled, code) would
    -- treat an enabled custom override and an enabled system row as one row,
    -- and an id = EXCLUDED.id predicate never fires for an identity id.
    -- admin.generate_active_code_custom_unique_constraint creates the key.
    IF table_properties.has_custom THEN
        unique_columns := ARRAY['code', 'custom'];
    ELSE
        unique_columns := ARRAY['code'];
    END IF;

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
        updated_at = statement_timestamp()
    RETURNING * INTO row;

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
, array_to_string(unique_columns, ', ') -- %9$: columns to use for conflict detection/resolution
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

CREATE OR REPLACE FUNCTION admin.upsert_legal_form_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_form_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the operator's custom-only upload disables system rows on
    -- purpose), and a new system code starts disabled while an enabled custom
    -- override of the code exists.
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.legal_form AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_data_source_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.data_source (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_data_source_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the custom upload disables system rows on purpose), and a
    -- new system code starts disabled while an enabled custom override exists.
    INSERT INTO public.data_source (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.data_source AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_foreign_participation_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.foreign_participation (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_foreign_participation_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the custom upload disables system rows on purpose), and a
    -- new system code starts disabled while an enabled custom override exists.
    INSERT INTO public.foreign_participation (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.foreign_participation AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_unit_size_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.unit_size (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_unit_size_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the custom upload disables system rows on purpose), and a
    -- new system code starts disabled while an enabled custom override exists.
    INSERT INTO public.unit_size (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.unit_size AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_status_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.status (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

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
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the custom upload disables system rows on purpose), and a
    -- new system code starts disabled while an enabled custom override exists.
    INSERT INTO public.status (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.status AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_rel_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_rel_type (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE legal_rel_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_rel_type_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_rel_type (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE legal_rel_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_reorg_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_reorg_type (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE legal_reorg_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_reorg_type_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_reorg_type (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE legal_reorg_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_person_role_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.person_role (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE person_role.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_person_role_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.person_role (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE person_role.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_power_group_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.power_group_type (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE power_group_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_power_group_type_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.power_group_type (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE power_group_type.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_region_version_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.region_version (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE region_version.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_region_version_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.region_version (code, name, description, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, NEW.description, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, description = NEW.description, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE region_version.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

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

DROP FUNCTION admin.batch_api_identity_key(admin.batch_api_table_properties);

END;
