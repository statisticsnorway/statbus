```sql
CREATE OR REPLACE FUNCTION admin.set_optimal_external_idents_settings()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    SET LOCAL work_mem = '1GB';           -- Allow large hash tables in memory
    SET LOCAL enable_hashjoin = on;       -- Use hash joins for large lookups
    SET LOCAL enable_nestloop = off;      -- Avoid nested loops for large datasets
    SET LOCAL enable_mergejoin = off;     -- Avoid expensive sorts for joins
    SET LOCAL random_page_cost = 1.1;     -- Optimize for modern storage
END;
$function$
```
