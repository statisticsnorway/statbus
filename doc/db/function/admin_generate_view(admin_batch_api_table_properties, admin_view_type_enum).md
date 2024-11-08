```sql
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
    WHEN 'available' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_ordered');
        IF table_properties.has_active THEN
            where_clause_str := 'WHERE active';
        ELSIF table_properties.has_archived THEN
            where_clause_str := 'WHERE NOT archived';
        ELSE
            RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
        END IF;
        columns_str := '*';
    WHEN 'system' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
        where_clause_str := 'WHERE custom = false';
    WHEN 'custom' THEN
        from_str := format('%1$I.%2$I', table_properties.schema_name, table_properties.table_name || '_available');
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
```
