```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution_begin()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_stock') IS NOT NULL THEN DROP TABLE pg_temp.hd_stock; END IF;
    CREATE TEMP TABLE hd_stock (LIKE public.statistical_history_facet_stock_delta_staging);
    ALTER TABLE hd_stock DROP COLUMN generation;
    IF to_regclass('pg_temp.hd_flow') IS NOT NULL THEN DROP TABLE pg_temp.hd_flow; END IF;
    CREATE TEMP TABLE hd_flow (LIKE public.statistical_history_facet_flow_delta_staging);
    ALTER TABLE hd_flow DROP COLUMN generation;
END;
$procedure$
```
