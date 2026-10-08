-- Migration 20261008170330: statbus_477 code generated upserts update existing rows
--
-- STATBUS-477 family B: the code-based tables whose upsert triggers are
-- produced by admin.generate_code_upsert_function: data_source,
-- foreign_participation, unit_size, status. Their upserts conflicted on
-- (enabled, code) with WHERE <t>.id = EXCLUDED.id. The predicate never fires
-- for an identity id (a corrected re-upload was INSERT 0 0), and dropping
-- only the predicate would let a system reload overwrite an enabled custom
-- override, because (enabled, code) treats the two as one row.
--
-- The identity of a row is (code, custom): one system row and at most one
-- custom override per code; enabled is a visibility flag (the custom
-- upload's prepare trigger disables system rows). So:
--   * (code, custom) becomes UNIQUE on each table, after a deterministic
--     dedupe (canonical = enabled first, then lowest id; every foreign key
--     reference moved to the canonical row first; counts reported);
--   * custom upserts update the custom row and enable it;
--   * system upserts correct the system row's label and never touch its
--     enabled flag or the custom override;
--   * the INSTEAD OF triggers return the row, so INSERT/COPY report it;
--   * the generators are patched the same way, so a table generated later
--     gets the fixed shape: generate_code_upsert_function conflicts on
--     (code, custom), and generate_active_code_custom_unique_constraint
--     creates the (code, custom) key.
-- status: its views omit NOT NULL columns, so inserts through them error
-- (STATBUS-478); it still gets the key and the fixed functions here, and the
-- end of this migration asserts the keys exist.
BEGIN;

-- Dedupe each table on (code, custom) before the key is added. A referencing
-- table with a unique constraint covering the foreign key column would need
-- its colliding row removed before repointing (as activity_category_access in
-- STATBUS-473); none exists today, so this fails loudly if one appears rather
-- than guess.
DO $dedupe_code_custom$
DECLARE
    _table text;
    _fk record;
    _moved bigint;
    _deleted bigint;
BEGIN
    FOREACH _table IN ARRAY ARRAY['data_source', 'foreign_participation', 'unit_size', 'status'] LOOP
        EXECUTE format($SQL$
            CREATE TEMP TABLE redundant ON COMMIT DROP AS
            SELECT ranked.id AS redundant_id, ranked.canonical_id
              FROM (
                SELECT t.id
                     , first_value(t.id) OVER (
                         PARTITION BY t.code, t.custom
                         ORDER BY t.enabled DESC, t.id
                       ) AS canonical_id
                  FROM public.%I AS t
              ) AS ranked
             WHERE ranked.id <> ranked.canonical_id
        $SQL$, _table);

        FOR _fk IN
            SELECT fk.conrelid::regclass AS ref_table
                 , a.attname AS ref_column
                 , EXISTS (
                     SELECT 1 FROM pg_catalog.pg_index AS i
                      WHERE i.indrelid = fk.conrelid AND i.indisunique
                        AND fk.conkey[1] = ANY (i.indkey::int2[])) AS covered_by_unique
              FROM pg_catalog.pg_constraint AS fk
              JOIN pg_catalog.pg_attribute AS a
                ON a.attrelid = fk.conrelid AND a.attnum = fk.conkey[1]
             WHERE fk.contype = 'f'
               AND fk.confrelid = format('public.%I', _table)::regclass
             ORDER BY fk.conrelid::regclass::text, a.attname
        LOOP
            IF _fk.covered_by_unique THEN
                RAISE EXCEPTION 'STATBUS-477: %.% references public.% under a unique index; resolve collisions before repointing', _fk.ref_table, _fk.ref_column, _table;
            END IF;
            EXECUTE format($SQL$
                UPDATE %s AS ref SET %I = r.canonical_id
                  FROM pg_temp.redundant AS r
                 WHERE ref.%I = r.redundant_id
            $SQL$, _fk.ref_table, _fk.ref_column, _fk.ref_column);
            GET DIAGNOSTICS _moved = ROW_COUNT;
            IF _moved > 0 THEN
                RAISE NOTICE 'STATBUS-477: moved % %.% reference(s) to the canonical public.% row', _moved, _fk.ref_table, _fk.ref_column, _table;
            END IF;
        END LOOP;

        EXECUTE format($SQL$
            DELETE FROM public.%I AS t USING pg_temp.redundant AS r WHERE t.id = r.redundant_id
        $SQL$, _table);
        GET DIAGNOSTICS _deleted = ROW_COUNT;
        RAISE NOTICE 'STATBUS-477: removed % redundant public.% row(s) duplicating (code, custom)', _deleted, _table;

        DROP TABLE pg_temp.redundant;
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (code, custom)'
            , _table, _table || '_code_custom_key');
    END LOOP;
END;
$dedupe_code_custom$;

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

-- The keys the upserts conflict on must exist (STATBUS-478 relies on status's).
DO $assert_code_custom_keys$
DECLARE
    _table text;
BEGIN
    FOREACH _table IN ARRAY ARRAY['data_source', 'foreign_participation', 'unit_size', 'status'] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_constraint AS con
             WHERE con.conrelid = format('public.%I', _table)::regclass
               AND con.contype = 'u'
               AND con.conname = _table || '_code_custom_key')
        THEN
            RAISE EXCEPTION 'STATBUS-477: missing key %_code_custom_key', _table;
        END IF;
    END LOOP;
END;
$assert_code_custom_keys$;

END;
