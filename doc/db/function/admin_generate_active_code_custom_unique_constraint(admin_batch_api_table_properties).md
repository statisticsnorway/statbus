```sql
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
```
