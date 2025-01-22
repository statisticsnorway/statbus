BEGIN;

CREATE OR REPLACE FUNCTION admin.enable_rls_on_public_tables()
RETURNS void AS $$
DECLARE
    table_regclass regclass;
BEGIN
    FOR table_regclass IN
        SELECT c.oid::regclass
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
    LOOP
        PERFORM admin.apply_rls_and_policies(table_regclass);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.enable_rls_on_public_tables();
SET LOCAL client_min_messages TO INFO;

END;
