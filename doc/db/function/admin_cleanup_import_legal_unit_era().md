```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_import_legal_unit_era()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE 'Deleting public.import_legal_unit_era';
    DROP VIEW public.import_legal_unit_era;
END;
$procedure$
```
