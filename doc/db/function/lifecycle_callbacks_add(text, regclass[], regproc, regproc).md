```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.add(IN label text, IN table_names regclass[], IN generate_procedure regproc, IN cleanup_procedure regproc)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    missing_tables regclass[];
BEGIN
    IF array_length(table_names, 1) IS NULL THEN
        RAISE EXCEPTION 'table_names must have one entry';
    END IF;

    -- Find any tables in table_names that are not in supported_table
    SELECT ARRAY_AGG(t_name)
    INTO missing_tables
    FROM UNNEST(table_names) AS t_name
    WHERE t_name NOT IN (SELECT table_name FROM lifecycle_callbacks.supported_table);

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'One or more tables in % are not supported: %', table_names, missing_tables;
    END IF;

    -- Ensure that the procedures exist
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = generate_procedure) THEN
        RAISE EXCEPTION 'Generate procedure % does not exist.', generate_procedure;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = cleanup_procedure) THEN
        RAISE EXCEPTION 'Cleanup procedure % does not exist.', cleanup_procedure;
    END IF;

    -- Insert or update the registered_callback entry
    INSERT INTO lifecycle_callbacks.registered_callback
           (label, table_names, generate_procedure, cleanup_procedure)
    VALUES (label, table_names, generate_procedure, cleanup_procedure)
    ON CONFLICT DO NOTHING;

    -- Check if the record was inserted; if not, raise an exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Callback with label % already exists. Cannot overwrite.', label;
    END IF;
END;
$procedure$
```
