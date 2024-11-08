```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_import_establishment_era()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_era';
    DROP VIEW public.import_establishment_era;
END;
$procedure$
```
