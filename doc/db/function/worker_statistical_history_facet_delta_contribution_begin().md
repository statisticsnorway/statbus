```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution_begin()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_rows') IS NOT NULL THEN DROP TABLE pg_temp.hd_rows; END IF;
    CREATE TEMP TABLE hd_rows (LIKE public.statistical_history_facet_delta_staging);
    ALTER TABLE hd_rows DROP COLUMN generation;
END;
$procedure$
```
