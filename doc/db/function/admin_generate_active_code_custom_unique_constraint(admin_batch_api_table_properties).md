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
END;
$function$
```
