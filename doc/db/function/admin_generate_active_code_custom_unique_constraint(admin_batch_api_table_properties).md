```sql
CREATE OR REPLACE FUNCTION admin.generate_active_code_custom_unique_constraint(table_properties admin.batch_api_table_properties)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    constraint_sql text;
    unique_columns text[];
    index_name text;
    identity_columns text[];
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

    -- STATBUS-477: ensure the identity key the generated upserts conflict on
    -- (admin.batch_api_identity_key) exists: (code) / (path) or
    -- (code, custom). It is a table constraint that outlives the generated
    -- views, so it is created only when absent: drop + regenerate stays
    -- idempotent.
    IF (table_properties.has_code OR table_properties.has_path) THEN
        identity_columns := admin.batch_api_identity_key(table_properties);
        index_name := table_properties.table_name || '_' || array_to_string(identity_columns, '_') || '_key';
        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_index AS i
             WHERE i.indrelid = format('%I.%I', table_properties.schema_name, table_properties.table_name)::regclass
               AND i.indisunique
               AND i.indpred IS NULL
               AND i.indnkeyatts = array_length(identity_columns, 1)
               AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
                      FROM pg_catalog.pg_attribute AS a
                     WHERE a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey::int2[]))
                   = (SELECT array_agg(c ORDER BY c) FROM unnest(identity_columns) AS c))
        THEN
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I UNIQUE (%s)'
                , table_properties.schema_name, table_properties.table_name, index_name
                , (SELECT string_agg(quote_ident(c), ', ') FROM unnest(identity_columns) AS c));
            RAISE NOTICE 'Created identity key % for table %', index_name, table_properties.table_name;
        END IF;
    END IF;
END;
$function$
```
