```sql
CREATE OR REPLACE PROCEDURE worker.derive_quality_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    -- The findings per check in this partition, one number per check, so the parent's info sums
    -- them over its children (worker.complete_parent_if_ready).
    p_info := public.quality_finding_derive((payload->>'hash_partition')::int4range);
END;
$procedure$
```
