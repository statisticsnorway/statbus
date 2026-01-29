```sql
CREATE OR REPLACE FUNCTION admin.index_temp_unpivoted_idents(table_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Always beneficial: index on lookup columns
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_lookup_idx ON %I (ident_type_code, ident_value)', table_name, table_name);
    
    -- Always beneficial: hash index for equality lookups  
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_hash_idx ON %I USING HASH (ident_value)', table_name, table_name);
    
    -- Always beneficial: index on data_row_id for result joining
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_data_row_idx ON %I (data_row_id)', table_name, table_name);
    
    -- Always beneficial: update statistics
    EXECUTE format('ANALYZE %I', table_name);
END;
$function$
```
