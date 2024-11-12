\echo admin.prevent_id_update
CREATE OR REPLACE FUNCTION admin.prevent_id_update()
  RETURNS TRIGGER
  AS $$
BEGIN
  IF NEW.id <> OLD.id THEN
    RAISE EXCEPTION 'Update of id column in legal_unit table is not allowed!';
  END IF;
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;


\echo admin.prevent_id_update_on_public_tables
CREATE OR REPLACE FUNCTION admin.prevent_id_update_on_public_tables()
RETURNS void AS $$
DECLARE
    table_regclass regclass;
    schema_name_str text;
    table_name_str text;
BEGIN
    FOR table_regclass, schema_name_str, table_name_str IN
        SELECT c.oid::regclass, n.nspname, c.relname
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
    LOOP
        RAISE NOTICE '%.%: Preventing id changes', schema_name_str, table_name_str;
        EXECUTE format('CREATE TRIGGER trigger_prevent_'||table_name_str||'_id_update BEFORE UPDATE OF id ON '||schema_name_str||'.'||table_name_str||' FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update();');
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.prevent_id_update_on_public_tables();
SET LOCAL client_min_messages TO INFO;