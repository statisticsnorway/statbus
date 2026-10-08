-- Down Migration 20261008172118: statbus_477 path generated upserts update existing rows
-- Restores the two generator functions and the four generated path upserts
-- exactly as dumped (\sf) before the up migration. No constraint was added.
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
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_sector_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.sector
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.sector (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, 'f', 't', statement_timestamp())
    ON CONFLICT (enabled, path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE sector.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_sector_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.sector
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.sector (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, 't', 'f', statement_timestamp())
    ON CONFLICT (enabled, path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE sector.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_tag_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, 'f', 't', statement_timestamp())
    ON CONFLICT (enabled, path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE tag.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_tag_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH parent AS (
        SELECT id
        FROM public.tag
        WHERE path OPERATOR(public.=) public.subpath(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.tag (path, parent_id, name, enabled, custom, updated_at)
    VALUES (NEW.path, (SELECT id FROM parent), NEW.name, 't', 'f', statement_timestamp())
    ON CONFLICT (enabled, path) DO UPDATE SET
        parent_id = (SELECT id FROM parent),
        name = EXCLUDED.name,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE tag.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
;

END;
