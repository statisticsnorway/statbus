```sql
CREATE OR REPLACE FUNCTION admin.stat_definition_lu_es_rollup_recalculate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Every legal unit total and the totals above it follow the changed rule: one full derive.
    IF EXISTS (SELECT 1 FROM old_rows AS o JOIN new_rows AS n ON n.id = o.id
               WHERE o.lu_es_rollup IS DISTINCT FROM n.lu_es_rollup) THEN
        PERFORM worker.enqueue_derive_statistical_unit_all();
    END IF;
    RETURN NULL;
END;
$function$
```
