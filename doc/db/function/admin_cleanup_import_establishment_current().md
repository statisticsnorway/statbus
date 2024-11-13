```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_import_establishment_current()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current';
    DROP VIEW public.import_establishment_current;

    RAISE NOTICE 'Deleting admin.import_establishment_current_upsert()';
    DROP FUNCTION admin.import_establishment_current_upsert();
END;
$procedure$
```
