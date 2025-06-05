```sql
CREATE OR REPLACE FUNCTION admin.grant_sequence_permissions_trigger()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() 
               WHERE command_tag IN ('CREATE SEQUENCE')
    LOOP
        -- Extract schema and sequence name from the object identity
        EXECUTE format('GRANT USAGE ON SEQUENCE %s TO authenticated', 
                      obj.object_identity);
        
        RAISE NOTICE 'Granted USAGE on new sequence % to authenticated', 
                    obj.object_identity;
    END LOOP;
END;
$function$
```
