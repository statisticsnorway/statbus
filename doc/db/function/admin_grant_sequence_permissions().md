```sql
CREATE OR REPLACE FUNCTION admin.grant_sequence_permissions()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT n.nspname AS schema_name, c.relname AS sequence_name
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'S'  -- 'S' for sequence
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        EXECUTE format('GRANT USAGE ON SEQUENCE %I.%I TO authenticated', 
                      seq_record.schema_name, seq_record.sequence_name);
        
        RAISE NOTICE 'Granted USAGE on sequence %.% to authenticated', 
                    seq_record.schema_name, seq_record.sequence_name;
    END LOOP;
END;
$function$
```
