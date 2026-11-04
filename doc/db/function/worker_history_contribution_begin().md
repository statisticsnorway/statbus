```sql
CREATE OR REPLACE PROCEDURE worker.history_contribution_begin()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_stock') IS NOT NULL THEN DROP TABLE pg_temp.hd_stock; END IF;
    CREATE TEMP TABLE hd_stock (LIKE public.history_stock_delta_staging);
    IF to_regclass('pg_temp.hd_flow') IS NOT NULL THEN DROP TABLE pg_temp.hd_flow; END IF;
    CREATE TEMP TABLE hd_flow (LIKE public.history_flow_delta_staging);
END;
$procedure$
```
