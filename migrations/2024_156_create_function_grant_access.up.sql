BEGIN;

-- Allow access read to the admin schema for all users,
-- as some nested UPSERT queries use views that call functions that require this.
-- This is strange, as there is no specific access to anything inside
-- admin that is requried.
GRANT USAGE ON SCHEMA admin TO authenticated;


\echo admin.grant_type_and_function_access_to_authenticated
CREATE OR REPLACE FUNCTION admin.grant_type_and_function_access_to_authenticated()
RETURNS void AS $$
DECLARE
    rec record;
    query text;
BEGIN
    -- Grant usage on the schema
    query := 'GRANT USAGE ON SCHEMA admin TO authenticated';
    RAISE DEBUG 'Executing query: %', query;
    EXECUTE query;

    -- Grant usage on all enum types in admin schema
    FOR rec IN SELECT typname FROM pg_type JOIN pg_namespace ON pg_type.typnamespace = pg_namespace.oid WHERE nspname = 'admin' AND typtype = 'e'
    LOOP
        query := format('GRANT USAGE ON TYPE admin.%I TO authenticated', rec.typname);
        RAISE DEBUG 'Executing query: %', query;
        EXECUTE query;
    END LOOP;

    -- Grant execute on all functions in admin schema
    FOR rec IN SELECT p.proname, n.nspname, p.oid,
                      pg_catalog.pg_get_function_identity_arguments(p.oid) as func_args
               FROM pg_proc p
               JOIN pg_namespace n ON p.pronamespace = n.oid
               WHERE n.nspname = 'admin'
    LOOP
        query := format('GRANT EXECUTE ON FUNCTION admin.%I(%s) TO authenticated', rec.proname, rec.func_args);
        RAISE DEBUG 'Executing query: %', query;
        EXECUTE query;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- TODO: Remove this if there is no need to grant specific read access to admin objects used by nested triggers.
--SET LOCAL client_min_messages TO DEBUG;
--SELECT admin.grant_type_and_function_access_to_authenticated();
--SET LOCAL client_min_messages TO INFO;

END;
