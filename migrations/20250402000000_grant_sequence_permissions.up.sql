-- Migration: Grant sequence permissions to authenticated role
BEGIN;

-- Function to grant usage on all sequences to authenticated role
CREATE OR REPLACE FUNCTION admin.grant_sequence_permissions()
RETURNS void AS $$
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
$$ LANGUAGE plpgsql;

-- Execute the function to grant permissions on all existing sequences
SELECT admin.grant_sequence_permissions();

-- Create a trigger function to automatically grant permissions on new sequences
CREATE OR REPLACE FUNCTION admin.grant_sequence_permissions_trigger()
RETURNS event_trigger AS $$
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
$$ LANGUAGE plpgsql;

-- Create an event trigger to catch all new sequence creations
DROP EVENT TRIGGER IF EXISTS grant_sequence_permissions_on_create;
CREATE EVENT TRIGGER grant_sequence_permissions_on_create 
ON ddl_command_end
WHEN TAG IN ('CREATE SEQUENCE')
EXECUTE FUNCTION admin.grant_sequence_permissions_trigger();

END;
