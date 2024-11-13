```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_import_legal_unit_current()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE 'Deleting public.import_legal_unit_current';
    DROP VIEW public.import_legal_unit_current;
    RAISE NOTICE 'Deleting admin.import_legal_unit_current_upsert()';
    DROP FUNCTION admin.import_legal_unit_current_upsert();
END;
$procedure$
```
