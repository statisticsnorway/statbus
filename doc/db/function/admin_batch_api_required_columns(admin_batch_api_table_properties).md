```sql
CREATE OR REPLACE FUNCTION admin.batch_api_required_columns(table_properties admin.batch_api_table_properties)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
