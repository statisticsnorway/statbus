```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_import_establishment_current_without_legal_unit()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current_without_legal_unit';
    DROP VIEW public.import_establishment_current_without_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_current_without_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_current_without_legal_unit_upsert();
END;
$procedure$
```
